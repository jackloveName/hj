import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../utils/format.dart';
import 'cloud_bridge.dart';
import 'cloud_ref.dart';
import 'local_store.dart';
import 'logic.dart';
import 'media_store.dart';

export 'logic.dart';

/// 应用数据中枢：所有页面读写都经过它，改动后自动落盘。
class Repository extends ChangeNotifier {
  Repository._(this._store, this._media);

  /// 游客（未登录）作用域下的本机数据键；登录后每个账号一个键，互不干扰
  static const String guestDataKey = 'zudun.data.v1';
  static const int _dataVersion = 1;

  final LocalStore _store;
  final MediaStore _media;

  String _dataKey = guestDataKey;

  /// 云端桥接（登录后由 CloudService 注入；为 null 时纯本机运行）
  CloudBridge? cloud;

  String get dataKey => _dataKey;

  final List<Property> _properties = <Property>[];
  final List<EvidencePhoto> _photos = <EvidencePhoto>[];
  final List<RentRecord> _rents = <RentRecord>[];
  final List<UtilityRecord> _utilities = <UtilityRecord>[];
  final List<RepairRecord> _repairs = <RepairRecord>[];
  final List<LandlordRule> _rules = <LandlordRule>[];
  final List<CommunicationRecord> _comms = <CommunicationRecord>[];

  /// 删除标记（墓碑）：删掉一条就记一笔，云端合并时才能知道"这是删了，不是还没有"
  final Map<String, Map<String, DateTime>> _tombstones =
      <String, Map<String, DateTime>>{};

  /// 墓碑保留期：过期后可以安全丢弃（另一台设备早就同步过了）
  static const Duration _tombstoneRetention = Duration(days: 180);

  AppSettings _settings = const AppSettings();
  String? _activeId;
  int _mediaBytes = 0;

  // 派生数据缓存：任何写操作后统一失效，避免在列表 / 网格里重复全量计算。
  Map<String, int>? _photoIndex;
  List<ReminderItem>? _reminders;
  Map<String, int>? _reminderCounts;
  DateTime? _remindersDay;
  String? _lastError;

  /// 本机数据比当前 App 新时为 true：只读保护，绝不把那份数据覆盖成空白
  bool _readOnly = false;
  String? _readOnlyNotice;

  /// 是否把数据写进本机存储。
  /// 游客模式为 false：数据只活在内存里，退出 App 就没了（登录后由账号接管）。
  bool _persistEnabled = true;

  static Future<Repository> open() async {
    final store = await LocalStore.open();
    final media = await MediaStore.open();
    final repository = Repository._(store, media);
    await repository._load();
    return repository;
  }

  // -------------------------------------------------------------------------
  // 加载 / 保存
  // -------------------------------------------------------------------------

  Future<void> _load() async {
    _readOnly = false;
    _readOnlyNotice = null;
    final raw = _store.getString(_dataKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final map = decoded.map((k, v) => MapEntry(k.toString(), v));
          final incomingVersion = map['version'];
          if (incomingVersion is int && incomingVersion > _dataVersion) {
            // 这份数据来自更高版本的 App：解析会丢字段，写回会把新版数据毁掉，
            // 所以这里什么都不做，只把状态置为只读并提示用户升级。
            _clearInMemory();
            _readOnly = true;
            _readOnlyNotice =
                '本机数据由更高版本的租盾写入（v$incomingVersion），'
                '为避免被覆盖已暂停保存。请升级 App 后再使用。';
            _lastError = _readOnlyNotice;
          } else {
            _apply(map);
          }
        }
      } catch (_) {
        // 数据损坏时从空白开始，保证应用可启动
        _clearInMemory();
      }
    } else {
      _clearInMemory();
    }
    _normalize();
    _mediaBytes = await _media.usedBytes();
    _invalidateDerived();
    notifyListeners();
  }

  void _clearInMemory() {
    _properties.clear();
    _photos.clear();
    _rents.clear();
    _utilities.clear();
    _repairs.clear();
    _rules.clear();
    _comms.clear();
    _tombstones.clear();
    _activeId = null;
    _settings = const AppSettings();
  }

  /// 记一条删除标记（墓碑）
  void _markDeleted(String recordKey, String id) {
    if (id.isEmpty) return;
    (_tombstones[recordKey] ??= <String, DateTime>{})[id] = DateTime.now();
  }

  /// 同一批删除（例如删房源连带删掉它的照片 / 记录）都要留痕
  void _markDeletedAll(String recordKey, Iterable<String> ids) {
    for (final id in ids) {
      _markDeleted(recordKey, id);
    }
  }

  /// 过期的墓碑可以丢掉，避免快照无限变大
  void _pruneTombstones() {
    final limit = DateTime.now().subtract(_tombstoneRetention);
    _tombstones.removeWhere((_, ids) {
      ids.removeWhere((_, time) => time.isBefore(limit));
      return ids.isEmpty;
    });
  }

  /// 切换数据作用域（游客 ↔ 某个账号）：换一个本机数据键并重新加载
  Future<void> useScope(String key) async {
    if (key == _dataKey) return;
    _dataKey = key;
    _clearInMemory();
    await _load();
  }

  /// 是否把数据落盘。游客模式要关掉（数据只存内存）。
  void setLocalPersist(bool enabled) => _persistEnabled = enabled;

  /// 用「空数据 + 不落盘」的游客态启动：
  /// 本机残留的游客数据不再读进来（登录时会被清掉），退出 App 即视为清空。
  Future<void> startFreshGuest() async {
    // 上一次游客会话留下的图片：一并清掉（记录早就不落盘了，图片也不能留）
    await purgeGuestMedia();
    _clearInMemory();
    _readOnly = false;
    _readOnlyNotice = null;
    _lastError = null;
    _persistEnabled = false;
    _invalidateDerived();
    notifyListeners();
  }

  void _apply(Map<String, dynamic> map) {
    // 数据版本校验：避免旧版应用直接读取更高版本的结构
    final incomingVersion = map['version'];
    if (incomingVersion is int && incomingVersion > _dataVersion) {
      throw const FormatException('这份数据来自更高版本的应用，请先升级后再导入');
    }
    _properties
      ..clear()
      ..addAll(_list(map['properties']).map(Property.fromJson));
    _photos
      ..clear()
      ..addAll(_list(map['photos']).map(EvidencePhoto.fromJson));
    _rents
      ..clear()
      ..addAll(_list(map['rents']).map(RentRecord.fromJson));
    _utilities
      ..clear()
      ..addAll(_list(map['utilities']).map(UtilityRecord.fromJson));
    _repairs
      ..clear()
      ..addAll(_list(map['repairs']).map(RepairRecord.fromJson));
    _rules
      ..clear()
      ..addAll(_list(map['rules']).map(LandlordRule.fromJson));
    _comms
      ..clear()
      ..addAll(_list(map['comms']).map(CommunicationRecord.fromJson));
    _tombstones.clear();
    final deleted = map['deleted'];
    if (deleted is Map) {
      deleted.forEach((key, value) {
        if (value is! Map) return;
        final ids = <String, DateTime>{};
        value.forEach((id, time) {
          final parsed = time is String ? DateTime.tryParse(time) : null;
          if (parsed != null) ids['$id'] = parsed;
        });
        if (ids.isNotEmpty) _tombstones['$key'] = ids;
      });
    }
    _settings = AppSettings.fromJson(
      map['settings'] is Map
          ? (map['settings'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{},
    );
    _activeId = map['activeId'] as String?;
  }

  List<Map<String, dynamic>> _list(Object? raw) => raw is List
      ? raw
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList()
      : <Map<String, dynamic>>[];

  Map<String, dynamic> _snapshot() => {
    'version': _dataVersion,
    'savedAt': DateTime.now().toIso8601String(),
    'properties': _properties.map((e) => e.toJson()).toList(),
    'photos': _photos.map((e) => e.toJson()).toList(),
    'rents': _rents.map((e) => e.toJson()).toList(),
    'utilities': _utilities.map((e) => e.toJson()).toList(),
    'repairs': _repairs.map((e) => e.toJson()).toList(),
    'rules': _rules.map((e) => e.toJson()).toList(),
    'comms': _comms.map((e) => e.toJson()).toList(),
    'deleted': <String, Map<String, String>>{
      for (final entry in _tombstones.entries)
        if (entry.value.isNotEmpty)
          entry.key: {
            for (final item in entry.value.entries)
              item.key: item.value.toIso8601String(),
          },
    },
    'settings': _settings.toJson(),
    'activeId': _activeId,
  };

  Future<void> _persist() async {
    if (_readOnly) {
      // 只读保护：一次都不写回，磁盘上那份新版本数据保持原样
      _lastError = _readOnlyNotice;
      _invalidateDerived();
      notifyListeners();
      return;
    }
    if (!_persistEnabled) {
      // 游客态：只改内存，不写存储
      _lastError = null;
      _invalidateDerived();
      notifyListeners();
      return;
    }
    try {
      _pruneTombstones();
      await _store.setString(_dataKey, jsonEncode(_snapshot()));
      _lastError = null;
    } catch (error) {
      _lastError = '数据保存失败：$error';
    }
    _invalidateDerived();
    notifyListeners();
    cloud?.schedulePush();
  }

  /// 云端同步用的紧凑 JSON
  String cloudJson() => jsonEncode(_snapshot());

  /// 应用云端数据：`merge` 为 true 时保留本机独有的记录（首次登录 / 有未同步改动）
  Future<void> applyCloudData(
    Map<String, dynamic> map, {
    bool merge = false,
  }) async {
    final incoming = merge ? mergeDatasets(map, _snapshot()) : map;
    _apply(incoming);
    _normalize();
    for (final property in _properties) {
      _ensureRentSchedule(property);
    }
    _mediaBytes = await _media.usedBytes();
    await _persist();
  }

  /// 写操作后清空派生缓存（照片计数与提醒列表都依赖全量数据）。
  void _invalidateDerived() {
    _photoIndex = null;
    _reminders = null;
    _reminderCounts = null;
    _remindersDay = null;
  }

  void _normalize() {
    _properties.sort((a, b) {
      // 租住中置顶，其余按更新时间
      final aRank = a.status == PropertyStatus.active ? 0 : 1;
      final bRank = b.status == PropertyStatus.active ? 0 : 1;
      if (aRank != bRank) return aRank - bRank;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    if (_activeId == null || !_properties.any((p) => p.id == _activeId)) {
      _activeId = _properties.isEmpty ? null : _properties.first.id;
    }
    refreshOverdue();
  }

  // -------------------------------------------------------------------------
  // 读取
  // -------------------------------------------------------------------------

  List<Property> get properties => List.unmodifiable(_properties);
  List<EvidencePhoto> get photos => List.unmodifiable(_photos);
  List<RentRecord> get rents => List.unmodifiable(_rents);
  List<UtilityRecord> get utilities => List.unmodifiable(_utilities);
  List<RepairRecord> get repairs => List.unmodifiable(_repairs);
  List<LandlordRule> get rules => List.unmodifiable(_rules);
  List<CommunicationRecord> get comms => List.unmodifiable(_comms);
  AppSettings get settings => _settings;
  String? get activeId => _activeId;
  int get mediaBytes => _mediaBytes;
  String get storageLocation => _store.location;

  /// 上一次写入失败的原因（存储空间不足 / 权限问题等），成功时自动清空。
  String? get lastError => _lastError;

  /// 只读保护状态：本机数据比 App 新，已停止写入
  bool get readOnly => _readOnly;
  String? get readOnlyNotice => _readOnlyNotice;

  /// 外观（明暗）变化时的轻量通知。
  ///
  /// 设计令牌是全局静态的，页面必须重新 build 才会换成新配色；
  /// 系统明暗变化不属于数据变更，但同样要让整棵树重画一次，所以借这条通道。
  void notifyAppearanceChanged() => notifyListeners();

  void clearError() => _lastError = null;

  Property? propertyById(String id) {
    for (final item in _properties) {
      if (item.id == id) return item;
    }
    return null;
  }

  Property? get activeProperty =>
      _activeId == null ? null : propertyById(_activeId!);

  /// 当前在租的房子：优先用户选中的那套；若它已退租，则回落到还在租的一套。
  ///
  /// 大部分租客同时只有一套房子在租，首页 / 费用页都跟随这里。
  Property? get currentProperty {
    final selected = activeProperty;
    if (selected != null && selected.status == PropertyStatus.active) {
      return selected;
    }
    for (final property in _properties) {
      if (property.status == PropertyStatus.active) return property;
    }
    return null;
  }

  /// 历史租住：已退租（含仍在维权）的房子
  List<Property> get historyProperties => List.unmodifiable(
    _properties.where((property) => property.status != PropertyStatus.active),
  );

  List<EvidencePhoto> photosOf(
    String propertyId, {
    PhotoPhase? phase,
    String? room,
  }) {
    final list = _photos.where((photo) {
      if (photo.propertyId != propertyId) return false;
      if (phase != null && photo.phase != phase) return false;
      if (room != null && photo.room != room) return false;
      return true;
    }).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  /// O(1) 计数：房间网格与存证健康度会频繁调用，避免每次全量过滤照片。
  int photoCountOf(String propertyId, {PhotoPhase? phase, String? room}) =>
      _photoCounter[_photoKey(propertyId, phase, room)] ?? 0;

  String _photoKey(String propertyId, PhotoPhase? phase, String? room) =>
      '$propertyId|${phase?.name ?? '*'}|${room ?? '*'}';

  Map<String, int> get _photoCounter {
    final cached = _photoIndex;
    if (cached != null) return cached;
    final counter = <String, int>{};
    void bump(String propertyId, PhotoPhase? phase, String? room) {
      final key = _photoKey(propertyId, phase, room);
      counter[key] = (counter[key] ?? 0) + 1;
    }

    for (final photo in _photos) {
      // 预聚合 4 种查询组合：按房间、按阶段、按阶段+房间、全部
      bump(photo.propertyId, photo.phase, photo.room);
      bump(photo.propertyId, photo.phase, null);
      bump(photo.propertyId, null, photo.room);
      bump(photo.propertyId, null, null);
    }
    return _photoIndex = counter;
  }

  EvidencePhoto? photoById(String id) {
    for (final item in _photos) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<RentRecord> rentsOf(String propertyId) =>
      _rents.where((r) => r.propertyId == propertyId).toList()
        ..sort((a, b) => b.month.compareTo(a.month));

  RentRecord? rentOfMonth(String propertyId, String month) {
    for (final item in _rents) {
      if (item.propertyId == propertyId && item.month == month) return item;
    }
    return null;
  }

  List<UtilityRecord> utilitiesOf(String propertyId) =>
      _utilities.where((u) => u.propertyId == propertyId).toList()
        ..sort((a, b) => b.month.compareTo(a.month));

  UtilityRecord? utilityOfMonth(String propertyId, String month) {
    for (final item in _utilities) {
      if (item.propertyId == propertyId && item.month == month) return item;
    }
    return null;
  }

  List<RepairRecord> repairsOf(String propertyId) =>
      _repairs.where((r) => r.propertyId == propertyId).toList()
        ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));

  List<LandlordRule> rulesOf(String propertyId) =>
      _rules.where((r) => r.propertyId == propertyId).toList()
        ..sort((a, b) => b.source.weight.compareTo(a.source.weight));

  List<CommunicationRecord> commsOf(String propertyId) =>
      _comms.where((c) => c.propertyId == propertyId).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  // -------------------------------------------------------------------------
  // 房源
  // -------------------------------------------------------------------------

  Future<Property> addProperty(Property property) async {
    _properties.add(property);
    _activeId = property.id;
    _ensureRentSchedule(property);
    _normalize();
    await _persist();
    return property;
  }

  Future<void> updateProperty(Property property) async {
    final index = _properties.indexWhere((p) => p.id == property.id);
    if (index < 0) return;
    _properties[index] = property.copyWith(updatedAt: DateTime.now());
    _ensureRentSchedule(_properties[index]);
    await _persist();
  }

  Future<void> deleteProperty(String id) async {
    for (final photo in _photos.where((p) => p.propertyId == id).toList()) {
      await _deletePhotoFiles(photo);
    }
    // 连带删掉的每一条都留墓碑，否则同步时会被另一台设备/云端"复活"
    _markDeleted('properties', id);
    _markDeletedAll(
      'photos',
      _photos.where((p) => p.propertyId == id).map((p) => p.id),
    );
    _markDeletedAll(
      'rents',
      _rents.where((r) => r.propertyId == id).map((r) => r.id),
    );
    _markDeletedAll(
      'utilities',
      _utilities.where((u) => u.propertyId == id).map((u) => u.id),
    );
    _markDeletedAll(
      'repairs',
      _repairs.where((r) => r.propertyId == id).map((r) => r.id),
    );
    _markDeletedAll(
      'rules',
      _rules.where((r) => r.propertyId == id).map((r) => r.id),
    );
    _markDeletedAll(
      'comms',
      _comms.where((c) => c.propertyId == id).map((c) => c.id),
    );
    _properties.removeWhere((p) => p.id == id);
    _photos.removeWhere((p) => p.propertyId == id);
    _rents.removeWhere((r) => r.propertyId == id);
    _utilities.removeWhere((u) => u.propertyId == id);
    _repairs.removeWhere((r) => r.propertyId == id);
    _rules.removeWhere((r) => r.propertyId == id);
    _comms.removeWhere((c) => c.propertyId == id);
    _normalize();
    _mediaBytes = await _media.usedBytes();
    await _persist();
  }

  Future<void> setActive(String id) async {
    _activeId = id;
    await _persist();
  }

  void _ensureRentSchedule(Property property) {
    final existing = _rents.where((r) => r.propertyId == property.id).toList();
    final planned = buildRentSchedule(
      property: property,
      existing: existing,
      today: dateOnly(DateTime.now()),
    );
    _rents.removeWhere((r) => r.propertyId == property.id);
    _rents.addAll(mergeRentSchedule(existing: existing, planned: planned));
  }

  void refreshOverdue() {
    final today = dateOnly(DateTime.now());
    for (var i = 0; i < _rents.length; i++) {
      final record = _rents[i];
      if (record.status == RentStatus.paid) continue;
      final target = record.dueDate.isBefore(today)
          ? RentStatus.overdue
          : RentStatus.pending;
      if (record.status != target) {
        _rents[i] = record.copyWith(status: target);
      }
    }
  }

  // -------------------------------------------------------------------------
  // 取证
  // -------------------------------------------------------------------------

  Future<EvidencePhoto> addPhoto(EvidencePhoto photo) async {
    _photos.add(photo);
    final property = propertyById(photo.propertyId);
    if (property != null &&
        (property.coverRef == null || property.coverRef!.isEmpty) &&
        photo.phase == PhotoPhase.moveIn) {
      final index = _properties.indexWhere((p) => p.id == property.id);
      _properties[index] = property.copyWith(coverRef: photo.thumbRef);
    }
    _mediaBytes = await _media.usedBytes();
    await _persist();
    return photo;
  }

  Future<void> updatePhoto(EvidencePhoto photo, {String? auditEntry}) async {
    final index = _photos.indexWhere((p) => p.id == photo.id);
    if (index < 0) return;
    final log = <String>[...photo.auditLog];
    if (auditEntry != null && auditEntry.isNotEmpty) {
      log.add('${fmtDateTime(DateTime.now())} $auditEntry');
    }
    _photos[index] = EvidencePhoto(
      id: photo.id,
      propertyId: photo.propertyId,
      room: photo.room,
      imageRef: photo.imageRef,
      thumbRef: photo.thumbRef,
      timestamp: photo.timestamp,
      location: photo.location,
      issueType: photo.issueType,
      description: photo.description,
      annotations: photo.annotations,
      phase: photo.phase,
      width: photo.width,
      height: photo.height,
      watermarked: photo.watermarked,
      auditLog: log,
    );
    await _persist();
  }

  Future<void> deletePhoto(String id) async {
    final photo = photoById(id);
    if (photo == null) return;
    _markDeleted('photos', id);
    await _deletePhotoFiles(photo);
    _photos.removeWhere((p) => p.id == id);

    // 删掉的正好是房源封面时，顺延到另一张入住照片，避免封面指向已删除文件
    final property = propertyById(photo.propertyId);
    if (property != null && property.coverRef == photo.thumbRef) {
      final fallback =
          _photos
              .where(
                (p) =>
                    p.propertyId == photo.propertyId &&
                    p.phase == PhotoPhase.moveIn,
              )
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final index = _properties.indexWhere((p) => p.id == property.id);
      _properties[index] = property.copyWith(
        coverRef: fallback.isEmpty ? null : fallback.first.thumbRef,
        clearCover: fallback.isEmpty,
      );
    }
    _mediaBytes = await _media.usedBytes();
    await _persist();
  }

  /// 存证健康度（对应设计稿「存证健康度」）
  EvidenceHealth healthOf(String propertyId) {
    final property = propertyById(propertyId);
    if (property == null) return const EvidenceHealth(ratio: 0, items: []);
    return buildHealth(
      property: property,
      photos: _photos,
      utilities: _utilities,
      now: DateTime.now(),
    );
  }

  // -------------------------------------------------------------------------
  // 费用
  // -------------------------------------------------------------------------

  Future<void> saveRent(RentRecord record) async {
    final index = _rents.indexWhere((r) => r.id == record.id);
    if (index >= 0) {
      _rents[index] = record;
    } else {
      _rents.add(record);
    }
    refreshOverdue();
    await _persist();
  }

  Future<void> markRentPaid(
    RentRecord record, {
    DateTime? paidDate,
    String note = '',
  }) => saveRent(
    record.copyWith(
      status: RentStatus.paid,
      paidDate: paidDate ?? DateTime.now(),
      note: note,
    ),
  );

  Future<void> markRentUnpaid(RentRecord record) => saveRent(
    record.copyWith(
      status: record.dueDate.isBefore(dateOnly(DateTime.now()))
          ? RentStatus.overdue
          : RentStatus.pending,
      clearPaidDate: true,
    ),
  );

  Future<void> saveUtility(UtilityRecord record) async {
    final index = _utilities.indexWhere((u) => u.id == record.id);
    if (index >= 0) {
      _utilities[index] = record;
    } else {
      _utilities.add(record);
    }
    await _persist();
  }

  Future<void> deleteUtility(String id) async {
    _markDeleted('utilities', id);
    _utilities.removeWhere((u) => u.id == id);
    await _persist();
  }

  double totalPaidRent(String propertyId) => sumPaidRent(_rents, propertyId);

  /// 已缴月数（与「累计已付租金」同源，避免两个口径打架）。
  int paidMonthsOf(String propertyId) => countPaidMonths(_rents, propertyId);

  double totalUtilityCost(String propertyId) =>
      sumUtilityCost(_utilities, propertyId);

  /// 某月支出构成（对应设计稿「本月构成」）
  MonthlyExpense expenseOfMonth(String propertyId, String month) {
    return computeMonthlyExpense(
      rents: _rents,
      utilities: _utilities,
      propertyId: propertyId,
      month: month,
    );
  }

  /// 最近 N 个月支出（按时间正序）
  List<MonthlyExpense> expenseTrend(String propertyId, {int months = 6}) {
    return buildExpenseTrend(
      rents: _rents,
      utilities: _utilities,
      propertyId: propertyId,
      now: DateTime.now(),
      months: months,
    );
  }

  double yearlyExpense(String propertyId, int year) =>
      sumYearlyExpense(_rents, _utilities, propertyId, year);

  // -------------------------------------------------------------------------
  // 维修 / 房东要求 / 沟通
  // -------------------------------------------------------------------------

  Future<void> saveRepair(RepairRecord record) async {
    final index = _repairs.indexWhere((r) => r.id == record.id);
    if (index >= 0) {
      _repairs[index] = record;
    } else {
      _repairs.add(record);
    }
    await _persist();
  }

  Future<void> deleteRepair(String id) async {
    _markDeleted('repairs', id);
    _repairs.removeWhere((r) => r.id == id);
    await _persist();
  }

  Future<void> saveRule(LandlordRule rule) async {
    final index = _rules.indexWhere((r) => r.id == rule.id);
    if (index >= 0) {
      _rules[index] = rule;
    } else {
      _rules.add(rule);
    }
    await _persist();
  }

  Future<void> deleteRule(String id) async {
    _markDeleted('rules', id);
    _rules.removeWhere((r) => r.id == id);
    await _persist();
  }

  Future<void> saveComm(CommunicationRecord record) async {
    final index = _comms.indexWhere((c) => c.id == record.id);
    if (index >= 0) {
      _comms[index] = record;
    } else {
      _comms.add(record);
    }
    await _persist();
  }

  Future<void> deleteComm(String id) async {
    _markDeleted('comms', id);
    _comms.removeWhere((c) => c.id == id);
    await _persist();
  }

  // -------------------------------------------------------------------------
  // 设置 / 媒体 / 备份
  // -------------------------------------------------------------------------

  Future<void> updateSettings(AppSettings value) async {
    _settings = value;
    await _persist();
  }

  Future<String> saveMedia(
    Uint8List bytes, {
    required String folder,
    required String name,
  }) async {
    String localRef;
    try {
      // 先落本机：断网 / 未登录时照片依然可用
      localRef = await _media.saveBytes(bytes, folder: folder, name: name);
      // 游客态：图片也不留在本机 —— 记一笔，下次以游客身份启动时删掉
      if (!_persistEnabled) await _rememberGuestMedia(localRef);
      _mediaBytes = await _media.usedBytes();
      if (!_media.lastWritePersisted) {
        _lastError =
            '浏览器存储空间不足：照片只在本次会话中可见，刷新后会丢失。'
            '建议先导出备份，或改用手机 / 桌面版。';
      }
    } catch (error) {
      _lastError = '图片保存失败（可能是存储空间不足）：$error';
      rethrow;
    }

    final bridge = cloud;
    if (bridge == null || !bridge.enabled) return localRef;
    try {
      final remoteRef = await bridge.uploadMedia(bytes, name: name);
      if (remoteRef == null) return localRef;
      // 上传过的字节直接进缓存，避免马上又要下载回来
      await _media.saveCloudBytes(remoteRef, bytes);
      return remoteRef;
    } catch (error) {
      _lastError = '照片已保存在本机，但上传云端失败：$error';
      return localRef;
    }
  }

  /// 游客态写过的图片文件（下次以游客身份启动时删掉，见 [purgeGuestMedia]）
  static const String _guestMediaKey = 'zudun.guest_media';

  Future<void> _rememberGuestMedia(String ref) async {
    if (ref.isEmpty) return;
    final list = _guestMediaRefs()..add(ref);
    await _store.setString(_guestMediaKey, jsonEncode(list));
  }

  List<String> _guestMediaRefs() {
    final raw = _store.getString(_guestMediaKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((item) => '$item').toList();
    } catch (_) {
      // 记坏了就当没有：图片文件本来就只是缓存
    }
    return [];
  }

  /// 清掉游客态留下的图片：记录已经不落盘了，图片也不能留
  Future<void> purgeGuestMedia() async {
    final refs = _guestMediaRefs();
    if (refs.isEmpty) return;
    await _store.remove(_guestMediaKey);
    for (final ref in refs) {
      try {
        await _media.delete(ref);
      } catch (_) {
        // 文件已经不在了也无所谓
      }
    }
    _mediaBytes = await _media.usedBytes();
  }

  /// 游客数据已经交给账号：这些图片从此算账号的，别再当"游客临时文件"清掉
  Future<void> forgetGuestMedia() => _store.remove(_guestMediaKey);

  Future<Uint8List?> readMedia(String ref) {
    if (!OssRef.isRemote(ref)) return _media.read(ref);
    return _readRemoteMedia(ref);
  }

  Future<Uint8List?> _readRemoteMedia(String ref) async {
    final cached = await _media.readCloudBytes(ref);
    if (cached != null) return cached;
    final bridge = cloud;
    if (bridge == null) return null;
    final bytes = await bridge.readRemoteMedia(ref);
    if (bytes != null) await _media.saveCloudBytes(ref, bytes);
    return bytes;
  }

  /// 本机键值存储（会话与配置也用同一个实例，避免两个写入方互相覆盖）
  LocalStore get store => _store;

  /// 读取某个作用域已落盘的数据（登录时用于合并上一个作用域的数据）
  String? rawDataOf(String key) => _store.getString(key);

  /// 删除某个作用域在本机的数据（注销账号时清理）
  Future<void> purgeScope(String key) async {
    if (key.isEmpty) return;
    await _store.remove(key);
  }

  /// 删除本机这份数据引用到的所有媒体文件（注销账号时用）。
  ///
  /// 本机文件直接删；云端引用会清掉本机缓存，并尽力请求服务端一起删除。
  /// [keep] 里的引用会跳过（例如这套照片同时被游客数据引用着）。
  Future<void> purgeLocalMedia({Set<String> keep = const {}}) async {
    for (final photo in _photos) {
      final shared =
          keep.contains(photo.imageRef) || keep.contains(photo.thumbRef);
      if (shared) continue;
      await _deletePhotoFiles(photo);
    }
    _mediaBytes = await _media.usedBytes();
  }

  /// 只删本机缓存，不动云端文件（云端照片的本地副本）
  Future<void> dropMediaCache(String ref) async {
    if (!OssRef.isRemote(ref)) return;
    await _media.deleteCloudBytes(ref);
  }

  /// 删除一份媒体：本机文件直接删；云端引用清掉缓存并尽力删除云端文件
  Future<void> _deleteMediaRef(String ref) async {
    if (ref.isEmpty) return;
    if (!OssRef.isRemote(ref)) {
      await _media.delete(ref);
      return;
    }
    await _media.deleteCloudBytes(ref);
    final bridge = cloud;
    if (bridge != null && bridge.enabled) {
      await bridge.releaseRemoteMedia([ref]);
    }
  }

  Future<void> _deletePhotoFiles(EvidencePhoto photo) async {
    await _deleteMediaRef(photo.imageRef);
    if (photo.thumbRef != photo.imageRef) {
      await _deleteMediaRef(photo.thumbRef);
    }
  }

  String backupJson() =>
      const JsonEncoder.withIndent('  ').convert(_snapshot());

  Future<void> restoreFromJson(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('数据格式不正确');
    // 覆盖前先清理旧媒体文件，避免留下永远不会再被引用的孤儿照片
    for (final photo in _photos) {
      await _deletePhotoFiles(photo);
    }
    _apply(decoded.map((k, v) => MapEntry(k.toString(), v)));
    _normalize();
    for (final property in _properties) {
      _ensureRentSchedule(property);
    }
    _mediaBytes = await _media.usedBytes();
    await _persist();
  }

  Future<void> clearAll() async {
    for (final photo in _photos) {
      await _deletePhotoFiles(photo);
    }
    _properties.clear();
    _photos.clear();
    _rents.clear();
    _utilities.clear();
    _repairs.clear();
    _rules.clear();
    _comms.clear();
    _activeId = null;
    _settings = const AppSettings();
    await _store.remove(_dataKey);
    _mediaBytes = await _media.usedBytes();
    await _persist();
  }

  // -------------------------------------------------------------------------
  // 提醒（对应设计稿首页「待办提醒」）
  // -------------------------------------------------------------------------

  List<ReminderItem> get reminders {
    // 按「天」失效：应用跨零点不重启时，倒计时天数也能自动更新
    final today = dateOnly(DateTime.now());
    if (_reminders == null || _remindersDay != today) {
      _remindersDay = today;
      _reminders = buildReminders(
        properties: _properties,
        photos: _photos,
        utilities: _utilities,
        rents: _rents,
        config: _settings.reminders,
        now: today,
      );
    }
    return _reminders!;
  }

  /// 单个房源的待办数量。列表页每张卡片都会用到，因此单独缓存成 map。
  int reminderCountOf(String propertyId) {
    final counts = _reminderCounts ??= () {
      final map = <String, int>{};
      for (final item in reminders) {
        map[item.propertyId] = (map[item.propertyId] ?? 0) + 1;
      }
      return map;
    }();
    return counts[propertyId] ?? 0;
  }
}
