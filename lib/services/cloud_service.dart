import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/cloud_bridge.dart';
import '../data/cloud_ref.dart';
import '../data/repository.dart';
import 'api/agreement_api.dart';
import 'api/api_client.dart';
import 'api/api_settings.dart';
import 'api/auth_api.dart';
import 'api/config_api.dart';
import 'api/profile_api.dart';
import 'api/upload_api.dart';
import 'protocol_service.dart';
import 'session.dart';

/// 同步状态（用于界面提示）
enum SyncState {
  /// 未登录：数据只在本机
  local,

  /// 已与云端一致
  idle,

  /// 正在同步
  syncing,

  /// 本机有改动等待上传
  pending,

  /// 上次同步失败
  failed,
}

/// 账号与云端同步：登录、拉取、上传，以及云端照片的读写。
///
/// 数据策略：
/// - 未登录 = 游客作用域，数据只落在本机（与旧版本行为一致）；
/// - 登录后每个手机号一个作用域（本机缓存键 + 云端配置键都按手机号区分）；
/// - 登录时若云端已有数据、本机旧作用域也有数据，则按 id 合并后再上传，避免互相覆盖；
/// - 平时本机改动会防抖上传；上次没传完的改动（pending）在下次启动时改为合并拉取。
class CloudService extends ChangeNotifier implements CloudBridge {
  CloudService({
    required this.repository,
    required this.session,
    required this.settings,
    ApiClient? client,
    http.Client? httpClient,
  }) : api =
           client ??
           ApiClient(baseUrl: settings.baseUrl, httpClient: httpClient) {
    api.tokenProvider = () => session.token;
    api.onUnauthorized = _handleUnauthorized;
    auth = AuthApi(api);
    agreement = AgreementApi(api);
    config = ConfigApi(api);
    profile = ProfileApi(api);
    upload = UploadApi(api: api, settings: settings, profile: profile);
    repository.cloud = this;
  }

  static const String _pendingKey = 'zudun.sync.pending';
  static const String _scopeKey = 'zudun.sync.scope';
  static const Duration _pushDebounce = Duration(milliseconds: 900);

  final Repository repository;
  final Session session;
  final ApiSettings settings;
  final ApiClient api;
  late final AuthApi auth;
  late final AgreementApi agreement;
  late final ConfigApi config;
  late final ProfileApi profile;
  late final UploadApi upload;

  /// 协议正文（隐私政策 / 平台注册协议）读取器，全应用共用一个缓存
  late final ProtocolService protocols = ProtocolService(config);

  Timer? _pushTimer;
  bool _applyingRemote = false;
  bool _remoteBroken = false;
  SyncState _state = SyncState.local;
  String? _lastError;
  DateTime? _lastSyncedAt;
  bool _lastPullMerged = false;

  SyncState get state => _state;
  String? get lastError => _lastError;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool get loggedIn => session.loggedIn;

  /// 首屏是否需要先显示登录页（未登录、且没选择过本机模式）
  bool get needsLogin => !session.loggedIn && !session.guestMode;

  bool get remoteBroken => _remoteBroken;

  @override
  bool get enabled => session.loggedIn;

  String get statusLabel => switch (_state) {
    SyncState.local => '本机模式',
    SyncState.syncing => '同步中…',
    SyncState.pending => '有改动待同步',
    SyncState.failed => '同步失败',
    SyncState.idle => '云端已同步',
  };

  /// 是否按「合并」方式拉取（上次有未上传的改动时）
  bool get _hasPending => repository.store.getString(_pendingKey) == 'true';

  Future<void> _setPending(bool value) => value
      ? repository.store.setString(_pendingKey, 'true')
      : repository.store.remove(_pendingKey);

  // ---------------------------------------------------------------------------
  // 启动 / 登录 / 退出
  // ---------------------------------------------------------------------------

  /// 启动时恢复会话：切到对应作用域并拉取云端数据（不阻塞首屏）
  Future<void> restore() async {
    await session.restore();
    api.baseUrl = settings.baseUrl;
    if (!session.loggedIn) {
      // 数据不保存在本机：没登录就用「空数据 + 不落盘」的游客态启动。
      // 老版本残留在本机的游客数据不再读进来（登录时会被清掉）。
      await repository.startFreshGuest();
      _setState(SyncState.local);
      return;
    }
    await _useScopeOf(session.scope);
    _setState(_hasPending ? SyncState.pending : SyncState.idle);
    unawaited(_refreshAfterRestore());
  }

  Future<void> _refreshAfterRestore() async {
    await refreshUser();
    await pull();
  }

  Future<void> sendLoginCode(String mobile) =>
      auth.sendLoginCode(mobile: mobile);

  /// 登录：验证码或密码
  Future<void> signIn({
    required String phone,
    String? validCode,
    String? password,
    required bool byPassword,
  }) async {
    final token = byPassword
        ? await auth.loginWithPassword(phone: phone, password: password ?? '')
        : await auth.loginWithCode(phone: phone, validCode: validCode ?? '');

    // 只并入「游客作用域」的数据：登录后按 id 并进账号。
    // 若上一个作用域是别的账号（例如登录态失效后没回到游客作用域），
    // 绝不能把它的数据带进新账号，否则会出现账号间数据串号。
    final fromGuest = repository.dataKey == Repository.guestDataKey;
    final previousJson = fromGuest
        ? repository.rawDataOf(Repository.guestDataKey)
        : null;

    await session.saveLogin(
      token: token,
      phone: phone,
      provider: byPassword ? 'password' : 'code',
    );
    await _useScopeOf(session.scope);
    await refreshUser();

    _setState(SyncState.syncing);
    try {
      await _mergeAfterLogin(previousJson);
      // 游客数据已被本账号接管：清掉游客键，
      // 否则下次登录别的账号又会把这份数据并进去（串号）。
      if (fromGuest) {
        await repository.purgeScope(Repository.guestDataKey);
        // 游客期间拍的照片这时已经归账号了，别让它们被当成"游客临时文件"清掉
        await repository.forgetGuestMedia();
      }
      await repository.store.setString(_scopeKey, session.scope);
      await _setPending(false);
      _lastSyncedAt = DateTime.now();
      _lastError = null;
      _setState(SyncState.idle);
    } on ApiException catch (error) {
      _fail(error.message);
    }
  }

  Future<void> _mergeAfterLogin(String? previousJson) async {
    final cloudMap = await _fetchRemote();
    final localMap = _decode(previousJson);
    final Map<String, dynamic>? next;
    if (cloudMap == null && localMap == null) {
      next = null;
    } else if (cloudMap == null) {
      next = localMap; // 云端还没有数据：把本机现有数据带上去
    } else if (localMap == null) {
      next = cloudMap; // 本机没数据：直接用云端
    } else {
      next = mergeDatasets(cloudMap, localMap); // 两边都有：按 id 合并
    }
    if (next == null) return;
    await _applyRemote(next);
    await push();
  }

  /// 刷新用户详情（昵称 / 头像）
  Future<void> refreshUser({bool silent = false}) async {
    if (!session.loggedIn) return;
    try {
      final detail = await auth.userDetail();
      await session.updateUser(detail);
    } on ApiException catch (error) {
      if (!silent || !error.reachable) rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await profile.logout();
    } catch (_) {
      // 退出登录以本机为准：即使服务端调用失败也要清干净
    }
    await session.clear();
    await _useScopeOf(Session.guestScope);
    _setState(SyncState.local);
  }

  /// 只清这台设备上的账号数据与照片：云端不动，账号仍登录着。
  /// 用在「共用设备 / 借给别人用之前」把本机痕迹清干净。
  Future<void> clearLocalData() async {
    if (!session.loggedIn) return;
    final scope = session.scope;
    await repository.purgeLocalMedia(
      keep: _mediaRefsOf(Repository.guestDataKey),
    );
    // 本机数据键是 `zudun.data.v1.<scope>`（见 _useScopeOf），
    // 用云端键 Session.dataKeyOf 去删本机数据只会删到一个不存在的键，数据其实没被清掉。
    await repository.purgeScope('${Repository.guestDataKey}.$scope');
    // 清完立即回到空数据；下一次同步会把云端那份拉回来
    await _useScopeOf(scope);
    _setState(_hasPending ? SyncState.pending : SyncState.idle);
  }

  /// 注销账号：删除云端数据与账号，并清掉本机这份账号数据
  Future<void> destroyAccount() async {
    if (!session.loggedIn) return;
    await _setPending(false);
    final scope = session.scope;
    // 先完成服务端删除（失败就抛错，避免出现「账号还在、本机却清空了」）
    await config.saveUserConfig(
      paramKey: session.dataKey,
      paramValue: 'null',
      remark: '哆米记账数据（账号注销前清理）',
    );
    await profile.destroyUser();
    // 服务端删除成功后再清本机：账号数据、云端照片缓存、登录态
    await session.clear();
    await _purgeLocalScope(scope);
    await _useScopeOf(Session.guestScope);
    _setState(SyncState.local);
  }

  /// 清掉某个作用域在本机留下的数据（注销账号时使用）
  Future<void> _purgeLocalScope(String scope) async {
    if (scope == Session.guestScope) return;
    // 先删照片文件（本机的直接删，云端的清缓存并请求一起删除），再删数据本体；
    // 反过来的话数据一没，这些文件就再也没人引用了
    await repository.purgeLocalMedia(
      keep: _mediaRefsOf(Repository.guestDataKey),
    );
    // 本机账号数据键是 `zudun.data.v1.<scope>`（见 _useScopeOf）：
    // 用云端键 Session.dataKeyOf 去删本机数据只会删到一个不存在的键，
    // 账号数据会留在本机（重新登录还会被推回云端）。
    await repository.purgeScope('${Repository.guestDataKey}.$scope');
    await repository.store.remove(_scopeKey);
  }

  /// 读取某个作用域数据里引用到的照片路径（用于判断文件是否还有人用）
  Set<String> _mediaRefsOf(String key) {
    final raw = repository.rawDataOf(key);
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final photos = decoded['photos'];
      if (photos is! List) return const {};
      return {
        for (final photo in photos)
          if (photo is Map) ...[
            if (photo['imageRef'] is String) '${photo['imageRef']}',
            if (photo['thumbRef'] is String) '${photo['thumbRef']}',
          ],
      };
    } catch (_) {
      return const {};
    }
  }

  // ---------------------------------------------------------------------------
  // 同步
  // ---------------------------------------------------------------------------

  /// 手动同步：把本机数据推上云端
  Future<void> syncNow() async {
    if (!session.loggedIn) return;
    await push();
  }

  /// 上传本机数据到云端
  Future<void> push() async {
    if (!session.loggedIn) return;
    _pushTimer?.cancel();
    if (_remoteBroken) {
      _fail('云端数据读取异常，为避免覆盖云端，本次未上传。请稍后重试');
      return;
    }
    _setState(SyncState.syncing);
    try {
      // 先把还只在本机的照片补传成云端引用：游客态拍的和当时上传失败的都算。
      // 以前 push 只推 JSON，本机路径会被原样写进云端，换设备后那一串引用
      // 全是读不到的路径。
      await repository.backfillCloudMedia();
      await config.saveUserConfig(
        paramKey: session.dataKey,
        paramValue: repository.cloudJson(),
        remark: '哆米记账数据',
      );
      // 数据确实进了云端之后，本机这份原图才可以删（本机只留浏览缓存）
      await repository.releaseLocalMedia();
      await _setPending(false);
      await repository.store.setString(_scopeKey, session.scope);
      _lastSyncedAt = DateTime.now();
      _lastError = null;
      _setState(SyncState.idle);
    } on ApiException catch (error) {
      _fail(error.message);
    }
  }

  /// 拉取云端数据：`merge` 为 true 时保留本机独有的记录
  Future<void> pull({bool? merge}) async {
    if (!session.loggedIn) return;
    final scopeChanged = repository.store.getString(_scopeKey) != session.scope;
    final useMerge = merge ?? (_hasPending || scopeChanged);
    _setState(SyncState.syncing);
    try {
      final cloudMap = await _fetchRemote();
      if (cloudMap == null) {
        // 云端还没数据：把本机数据传上去，避免「登录后一片空白」
        await push();
        return;
      }
      await _applyRemote(cloudMap, merge: useMerge);
      await _setPending(false);
      await repository.store.setString(_scopeKey, session.scope);
      _lastSyncedAt = DateTime.now();
      _lastError = null;
      _lastPullMerged = useMerge;
      _setState(SyncState.idle);
    } on ApiException catch (error) {
      _fail(error.message);
    }
  }

  /// 上次拉取是否做过合并（界面提示用）
  bool get lastPullMerged => _lastPullMerged;

  @override
  void schedulePush() {
    if (!session.loggedIn || _applyingRemote) return;
    unawaited(_setPending(true));
    _pushTimer?.cancel();
    _pushTimer = Timer(_pushDebounce, () => unawaited(push()));
  }

  Future<Map<String, dynamic>?> _fetchRemote() async {
    final raw = await config.readUserConfig(session.dataKey);
    final isEmpty =
        raw == null ||
        (raw is String && const ['', 'null', '{}', '[]'].contains(raw.trim()));
    if (isEmpty) {
      _remoteBroken = false;
      return null;
    }
    final map = parseConfigMap(raw);
    _remoteBroken = map == null;
    if (map == null) {
      throw ApiException('云端数据格式异常，已保留本机数据。请稍后重试或联系管理员');
    }
    return map;
  }

  Future<void> _applyRemote(
    Map<String, dynamic> map, {
    bool merge = false,
  }) async {
    _applyingRemote = true;
    try {
      await repository.applyCloudData(map, merge: merge);
    } finally {
      _applyingRemote = false;
    }
  }

  Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? decoded.map((k, v) => MapEntry(k.toString(), v))
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _useScopeOf(String scope) async {
    final guest = scope == Session.guestScope;
    await repository.useScope(
      guest ? Repository.guestDataKey : '${Repository.guestDataKey}.$scope',
    );
    // 游客数据只存内存；切到账号作用域（登录后）才重新落盘
    repository.setLocalPersist(!guest);
  }

  // ---------------------------------------------------------------------------
  // 云端照片
  // ---------------------------------------------------------------------------

  @override
  Future<Uint8List?> readRemoteMedia(String ref) async {
    final url = upload.publicUrlOfRef(ref);
    if (url.isEmpty) return null;
    try {
      final bytes = await api.getBytes(url);
      return Uint8List.fromList(bytes);
    } on ApiException catch (error) {
      _lastError = error.message;
      notifyListeners();
      return null;
    }
  }

  @override
  Future<String?> uploadMedia(Uint8List bytes, {required String name}) async {
    if (!session.loggedIn) return null;
    final uploaded = await upload.uploadBytes(bytes, fileName: name);
    return uploaded.ref;
  }

  @override
  Future<void> releaseRemoteMedia(List<String> refs) async {
    if (!session.loggedIn) return;
    final paths = refs.where(OssRef.isRemote).toList();
    if (paths.isEmpty) return;
    await upload.delete(paths);
  }

  // ---------------------------------------------------------------------------
  // 内部状态
  // ---------------------------------------------------------------------------

  void _handleUnauthorized() {
    unawaited(_clearSessionOnUnauthorized());
  }

  Future<void> _clearSessionOnUnauthorized() async {
    await session.clear();
    // 登录态失效后必须回到游客作用域：否则内存里仍指向旧账号的数据键，
    // 用户下一次登录会把旧账号的数据并进新账号（串号）。
    await _useScopeOf(Session.guestScope);
    await _setPending(false);
    _lastError = '登录已失效，请重新登录';
    _setState(SyncState.local);
  }

  void _fail(String message) {
    _lastError = message;
    unawaited(_setPending(true));
    _setState(SyncState.failed);
  }

  void _setState(SyncState state) {
    if (_state == state && _lastError == null) {
      notifyListeners();
      return;
    }
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _pushTimer?.cancel();
    api.close();
    super.dispose();
  }
}
