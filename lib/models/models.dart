import 'package:flutter/painting.dart';

import '../theme/tokens.dart';
import '../utils/format.dart';

// ---------------------------------------------------------------------------
// 通用转换
// ---------------------------------------------------------------------------

T _enum<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is String) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
  }
  return fallback;
}

double _double(Object? raw, [double fallback = 0]) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw) ?? fallback;
  return fallback;
}

/// 可空数字：没写 / 空串 / 解析不出来都是 null。
///
/// 用来区分「填了 0」和「还没填」—— 入住时的表底数就是这种：
/// 填了 0 是「表本来就是 0」，没填是「还没抄」，两者不能混。
double? _optionalDouble(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString().trim());
}

/// [ContractInfo.copyWith] 的哨兵值：区分「参数没传」（保持原值）和
/// 「传了 null」（把这一项清空）。三项表底数是可空的，用户把输入框清空时
/// 得能真的清掉 —— 直接写 `??` 的话 null 会被当成「不改」。
const Object _unset = Object();

/// [ContractInfo.copyWith] 里的表底数取值：
/// 没传 → 保持原值；传了 null → 清空；传了数（int / double 都行）→ 存成 double。
double? _readingValue(Object? value, double? current) {
  if (identical(value, _unset)) return current;
  if (value == null) return null;
  return (value as num).toDouble();
}

int _int(Object? raw, [int fallback = 0]) {
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? fallback;
  return fallback;
}

String _string(Object? raw, [String fallback = '']) =>
    raw is String ? raw : fallback;

bool _bool(Object? raw, [bool fallback = false]) =>
    raw is bool ? raw : fallback;

List<String> _strings(Object? raw) =>
    raw is List ? raw.whereType<String>().toList() : <String>[];

Map<String, dynamic> _map(Object? raw) => raw is Map
    ? raw.map((k, v) => MapEntry(k.toString(), v))
    : <String, dynamic>{};

List<Map<String, dynamic>> _maps(Object? raw) =>
    raw is List ? raw.map(_map).toList() : <Map<String, dynamic>>[];

// ---------------------------------------------------------------------------
// 枚举
// ---------------------------------------------------------------------------

/// 房源状态
enum PropertyStatus {
  active('租住中', ZTone.ok),
  ended('已退租', ZTone.neutral),
  dispute('纠纷中', ZTone.danger);

  const PropertyStatus(this.label, this.tone);
  final String label;
  final ZTone tone;
}

/// 押金状态：六种，其中「无押金」由「要不要押金」那一问决定、
/// 「纠纷中」跟着房源状态走，界面上可选的是中间四种（且只能往前走）
enum DepositStatus {
  none('无押金', ZTone.ok, '本房源无需押金。'),
  paid('已缴纳', ZTone.brand, '入住时已支付押金，退租时记得要回。'),
  toBeReturned('待退还', ZTone.warn, '押金等着房东退还，退到手再更新。'),
  partiallyDeducted('部分扣除', ZTone.warn, '房东扣除了部分押金，请核对扣款理由。'),
  returned('已退还', ZTone.ok, '押金已全额退还。'),
  inDispute('纠纷中', ZTone.danger, '押金被无理扣除，正在维权。');

  const DepositStatus(this.label, this.tone, this.hint);
  final String label;
  final ZTone tone;
  final String hint;
}

/// 租金三态
enum RentStatus {
  paid('已付', ZTone.ok),
  pending('待付', ZTone.warn),
  overdue('逾期', ZTone.danger);

  const RentStatus(this.label, this.tone);
  final String label;
  final ZTone tone;
}

enum PhotoPhase {
  moveIn('入住取证'),
  during('居住期间'),
  moveOut('退租取证');

  const PhotoPhase(this.label);
  final String label;
}

/// 8 类问题标注
enum IssueType {
  none('无问题', '✅', '状态良好，无需标注', ZTone.ok),
  wall('墙面破损', '🧱', '裂缝、掉漆、发霉', ZTone.danger),
  floor('地板问题', '🪵', '划痕、起翘、污渍', ZTone.danger),
  furniture('家具损坏', '🪑', '破损、缺件、松动', ZTone.warn),
  appliance('家电问题', '📺', '不工作、异响、外壳破损', ZTone.warn),
  doorWindow('门窗问题', '🚪', '关不严、锁松动、纱窗破', ZTone.warn),
  plumbing('水暖问题', '🚿', '漏水、堵塞、水压不足', ZTone.brand),
  electric('电路问题', '🔌', '插座松动、灯不亮', ZTone.brand),
  other('其他', '📌', '自定义描述', ZTone.neutral);

  const IssueType(this.label, this.emoji, this.examples, this.tone);
  final String label;
  final String emoji;
  final String examples;
  final ZTone tone;
}

enum RepairStatus {
  pending('待处理', ZTone.warn),
  inProgress('处理中', ZTone.brand),
  completed('已完成', ZTone.ok);

  const RepairStatus(this.label, this.tone);
  final String label;
  final ZTone tone;
}

enum CostBearer {
  landlord('房东承担'),
  tenant('租客承担'),
  shared('共同承担'),
  undecided('待确认');

  const CostBearer(this.label);
  final String label;
}

enum RuleSource {
  contract('合同写明', 3),
  verbal('口头约定', 1),
  chat('聊天记录', 2);

  const RuleSource(this.label, this.weight);
  final String label;
  final int weight;
}

enum CommType {
  text('文字记录'),
  screenshot('截图留存');

  const CommType(this.label);
  final String label;
}

// ---------------------------------------------------------------------------
// 房源 / 合同 / 押金
// ---------------------------------------------------------------------------

class Landlord {
  const Landlord({this.name = '', this.phone = '', this.wechat = ''});

  final String name;
  final String phone;
  final String wechat;

  Landlord copyWith({String? name, String? phone, String? wechat}) => Landlord(
    name: name ?? this.name,
    phone: phone ?? this.phone,
    wechat: wechat ?? this.wechat,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'wechat': wechat,
  };

  factory Landlord.fromJson(Map<String, dynamic> json) => Landlord(
    name: _string(json['name']),
    phone: _string(json['phone']),
    wechat: _string(json['wechat']),
  );
}

class ContractInfo {
  const ContractInfo({
    this.monthlyRent = 0,
    this.deposit = 0,
    this.paymentMethod = '押一付三',
    required this.moveInDate,
    required this.contractEnd,
    this.rentDueDay = 13,
    this.minLeaseMonths = 1,
    this.noticeDays = 30,
    this.rentScope = '整租',
    this.earlyTermination = '',
    this.renewalTerms = '',
    this.specialTerms = '',
    this.contractPhotoRefs = const [],
    this.hasGasMeter = false,
    this.moveInElectricity,
    this.moveInWater,
    this.moveInGas,
  });

  final double monthlyRent;
  final double deposit;
  final String paymentMethod;
  final DateTime moveInDate;
  final DateTime contractEnd;
  final int rentDueDay;
  final int minLeaseMonths;

  /// 这套房有没有燃气表。默认「没有」—— 家里没燃气表却逼着填一个燃气表底数
  /// （填 0 也是假的）只会让待办永远消不掉。
  /// 它同时决定抄表录入里燃气那一项要不要开着。
  final bool hasGasMeter;

  /// 入住时的表底数（水 m³ / 电 kWh / 燃气 m³）。
  /// 留空表示还没抄：抄表录入的首月用量要靠它当基准，
  /// 缺了会在首页待办里提醒补填。旧数据没有这三项，读出来是 null。
  final double? moveInElectricity;
  final double? moveInWater;
  final double? moveInGas;

  /// 退租需要提前多少天通知房东
  final int noticeDays;

  /// 整租 / 合租
  final String rentScope;
  final String earlyTermination;
  final String renewalTerms;
  final String specialTerms;
  final List<String> contractPhotoRefs;

  static const List<String> paymentMethods = [
    '押一付一',
    '押一付三',
    '押二付一',
    '押一付六',
    '押一付十二',
    '季度付',
    '年付',
    '其他',
  ];

  /// 合同一共几期（含首尾月）：和按租期生成的租金计划期数一致 ——
  /// 2026-03-01 签到 2026-12-31 是 10 期。
  /// 以前用纯月份差，会少算一期（向导里那句「共 N 期」当时也跟着错）
  int get totalMonths {
    final months =
        (contractEnd.year - moveInDate.year) * 12 +
        (contractEnd.month - moveInDate.month) +
        1;
    return months <= 0 ? 1 : months;
  }

  double get progress {
    final total = contractEnd.difference(moveInDate).inDays;
    if (total <= 0) return 0;
    final passed = DateTime.now().difference(moveInDate).inDays;
    return (passed / total).clamp(0.0, 1.0);
  }

  ContractInfo copyWith({
    double? monthlyRent,
    double? deposit,
    String? paymentMethod,
    DateTime? moveInDate,
    DateTime? contractEnd,
    int? rentDueDay,
    int? minLeaseMonths,
    int? noticeDays,
    String? rentScope,
    String? earlyTermination,
    String? renewalTerms,
    String? specialTerms,
    List<String>? contractPhotoRefs,
    bool? hasGasMeter,
    // 传 null 表示清空这一项（见 [_unset]）
    Object? moveInElectricity = _unset,
    Object? moveInWater = _unset,
    Object? moveInGas = _unset,
  }) => ContractInfo(
    monthlyRent: monthlyRent ?? this.monthlyRent,
    deposit: deposit ?? this.deposit,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    moveInDate: moveInDate ?? this.moveInDate,
    contractEnd: contractEnd ?? this.contractEnd,
    rentDueDay: rentDueDay ?? this.rentDueDay,
    minLeaseMonths: minLeaseMonths ?? this.minLeaseMonths,
    noticeDays: noticeDays ?? this.noticeDays,
    rentScope: rentScope ?? this.rentScope,
    earlyTermination: earlyTermination ?? this.earlyTermination,
    renewalTerms: renewalTerms ?? this.renewalTerms,
    specialTerms: specialTerms ?? this.specialTerms,
    contractPhotoRefs: contractPhotoRefs ?? this.contractPhotoRefs,
    hasGasMeter: hasGasMeter ?? this.hasGasMeter,
    moveInElectricity: _readingValue(moveInElectricity, this.moveInElectricity),
    moveInWater: _readingValue(moveInWater, this.moveInWater),
    moveInGas: _readingValue(moveInGas, this.moveInGas),
  );

  Map<String, dynamic> toJson() => {
    'monthlyRent': monthlyRent,
    'deposit': deposit,
    'paymentMethod': paymentMethod,
    'moveInDate': moveInDate.toIso8601String(),
    'contractEnd': contractEnd.toIso8601String(),
    'rentDueDay': rentDueDay,
    'minLeaseMonths': minLeaseMonths,
    'noticeDays': noticeDays,
    'rentScope': rentScope,
    'earlyTermination': earlyTermination,
    'renewalTerms': renewalTerms,
    'specialTerms': specialTerms,
    'contractPhotoRefs': contractPhotoRefs,
    'hasGasMeter': hasGasMeter,
    'moveInElectricity': moveInElectricity,
    'moveInWater': moveInWater,
    'moveInGas': moveInGas,
  };

  factory ContractInfo.fromJson(Map<String, dynamic> json) => ContractInfo(
    monthlyRent: _double(json['monthlyRent']),
    deposit: _double(json['deposit']),
    paymentMethod: _string(json['paymentMethod'], '押一付三'),
    moveInDate: parseDate(_string(json['moveInDate'])),
    contractEnd: parseDate(
      _string(json['contractEnd']),
      fallback: DateTime.now().add(const Duration(days: 365)),
    ),
    rentDueDay: _int(json['rentDueDay'], 13),
    minLeaseMonths: _int(json['minLeaseMonths'], 1),
    noticeDays: _int(json['noticeDays'], 30),
    rentScope: _string(json['rentScope'], '整租'),
    earlyTermination: _string(json['earlyTermination']),
    renewalTerms: _string(json['renewalTerms']),
    specialTerms: _string(json['specialTerms']),
    contractPhotoRefs: _strings(json['contractPhotoRefs']),
    hasGasMeter: _bool(json['hasGasMeter']),
    moveInElectricity: _optionalDouble(json['moveInElectricity']),
    moveInWater: _optionalDouble(json['moveInWater']),
    moveInGas: _optionalDouble(json['moveInGas']),
  );
}

class DepositLog {
  const DepositLog({required this.status, required this.time, this.note = ''});

  final DepositStatus status;
  final DateTime time;
  final String note;

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'time': time.toIso8601String(),
    'note': note,
  };

  factory DepositLog.fromJson(Map<String, dynamic> json) => DepositLog(
    status: _enum(DepositStatus.values, json['status'], DepositStatus.paid),
    time: parseDate(_string(json['time'])),
    note: _string(json['note']),
  );
}

class DepositInfo {
  const DepositInfo({
    this.status = DepositStatus.paid,
    this.deductedAmount = 0,
    this.deductReason = '',
    this.returnedAmount = 0,
    this.returnedDate,
    this.disputeNote = '',
    this.handoverDone = false,
    this.handoverNote = '',
    this.logs = const [],
  });

  final DepositStatus status;
  final double deductedAmount;
  final String deductReason;
  final double returnedAmount;
  final DateTime? returnedDate;
  final String disputeNote;

  /// 与房东的退租对接是否已经谈妥（钥匙交还、水电燃气结清、退租验收）
  final bool handoverDone;

  /// 交接时的备注：遗留问题、口头约定
  final String handoverNote;

  final List<DepositLog> logs;

  DepositInfo copyWith({
    DepositStatus? status,
    double? deductedAmount,
    String? deductReason,
    double? returnedAmount,
    DateTime? returnedDate,
    String? disputeNote,
    bool? handoverDone,
    String? handoverNote,
    List<DepositLog>? logs,
  }) => DepositInfo(
    status: status ?? this.status,
    deductedAmount: deductedAmount ?? this.deductedAmount,
    deductReason: deductReason ?? this.deductReason,
    returnedAmount: returnedAmount ?? this.returnedAmount,
    returnedDate: returnedDate ?? this.returnedDate,
    disputeNote: disputeNote ?? this.disputeNote,
    handoverDone: handoverDone ?? this.handoverDone,
    handoverNote: handoverNote ?? this.handoverNote,
    logs: logs ?? this.logs,
  );

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'deductedAmount': deductedAmount,
    'deductReason': deductReason,
    'returnedAmount': returnedAmount,
    'returnedDate': returnedDate?.toIso8601String(),
    'disputeNote': disputeNote,
    'handoverDone': handoverDone,
    'handoverNote': handoverNote,
    'logs': logs.map((e) => e.toJson()).toList(),
  };

  factory DepositInfo.fromJson(Map<String, dynamic> json) => DepositInfo(
    status: _enum(DepositStatus.values, json['status'], DepositStatus.paid),
    deductedAmount: _double(json['deductedAmount']),
    deductReason: _string(json['deductReason']),
    returnedAmount: _double(json['returnedAmount']),
    returnedDate: json['returnedDate'] == null
        ? null
        : parseDate(_string(json['returnedDate'])),
    disputeNote: _string(json['disputeNote']),
    handoverDone: _bool(json['handoverDone']),
    handoverNote: _string(json['handoverNote']),
    logs: _maps(json['logs']).map(DepositLog.fromJson).toList(),
  );
}

class Property {
  const Property({
    required this.id,
    required this.name,
    required this.address,
    required this.landlord,
    required this.contract,
    this.status = PropertyStatus.active,
    this.deposit = const DepositInfo(),
    required this.createdAt,
    required this.updatedAt,
    this.coverRef,
    this.rooms = const [],
    this.area = '',
    this.layout = '',
  });

  final String id;
  final String name;
  final String address;
  final Landlord landlord;
  final ContractInfo contract;
  final PropertyStatus status;
  final DepositInfo deposit;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? coverRef;
  final List<String> rooms;
  final String area;
  final String layout;

  static const List<String> defaultRooms = [
    '客厅',
    '主卧',
    '次卧',
    '厨房',
    '卫生间',
    '阳台',
    '玄关',
    '储物间',
  ];

  List<String> get allRooms {
    final list = <String>[...defaultRooms];
    for (final room in rooms) {
      if (!list.contains(room)) list.add(room);
    }
    return list;
  }

  String get subtitle {
    final parts = <String>[
      if (layout.isNotEmpty) layout,
      if (area.isNotEmpty) area,
    ];
    if (parts.isEmpty) return address;
    return parts.join(' · ');
  }

  Property copyWith({
    String? name,
    String? address,
    Landlord? landlord,
    ContractInfo? contract,
    PropertyStatus? status,
    DepositInfo? deposit,
    DateTime? updatedAt,
    String? coverRef,
    bool clearCover = false,
    List<String>? rooms,
    String? area,
    String? layout,
  }) => Property(
    id: id,
    name: name ?? this.name,
    address: address ?? this.address,
    landlord: landlord ?? this.landlord,
    contract: contract ?? this.contract,
    status: status ?? this.status,
    deposit: deposit ?? this.deposit,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
    coverRef: clearCover ? null : (coverRef ?? this.coverRef),
    rooms: rooms ?? this.rooms,
    area: area ?? this.area,
    layout: layout ?? this.layout,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'landlord': landlord.toJson(),
    'contract': contract.toJson(),
    'status': status.name,
    'deposit': deposit.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'coverRef': coverRef,
    'rooms': rooms,
    'area': area,
    'layout': layout,
  };

  factory Property.fromJson(Map<String, dynamic> json) => Property(
    id: _string(json['id']),
    name: _string(json['name']),
    address: _string(json['address']),
    landlord: Landlord.fromJson(_map(json['landlord'])),
    contract: ContractInfo.fromJson(_map(json['contract'])),
    status: _enum(PropertyStatus.values, json['status'], PropertyStatus.active),
    deposit: DepositInfo.fromJson(_map(json['deposit'])),
    createdAt: parseDate(_string(json['createdAt'])),
    updatedAt: parseDate(_string(json['updatedAt'])),
    coverRef: json['coverRef'] as String?,
    rooms: _strings(json['rooms']),
    area: _string(json['area']),
    layout: _string(json['layout']),
  );
}

// ---------------------------------------------------------------------------
// 取证
// ---------------------------------------------------------------------------

class AnnotationShape {
  const AnnotationShape({
    required this.type,
    required this.points,
    this.text = '',
    this.colorValue = 0xFFFF4D4F,
    this.strokeWidth = 0.006,
  });

  /// circle / arrow / rect / free / text
  final String type;

  /// 归一化坐标（0~1），与原图分辨率解耦
  final List<Offset> points;
  final String text;
  final int colorValue;
  final double strokeWidth;

  Color get color => Color(colorValue);

  AnnotationShape copyWith({
    String? type,
    List<Offset>? points,
    String? text,
    int? colorValue,
    double? strokeWidth,
  }) => AnnotationShape(
    type: type ?? this.type,
    points: points ?? this.points,
    text: text ?? this.text,
    colorValue: colorValue ?? this.colorValue,
    strokeWidth: strokeWidth ?? this.strokeWidth,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'points': points.map((p) => [p.dx, p.dy]).toList(),
    'text': text,
    'colorValue': colorValue,
    'strokeWidth': strokeWidth,
  };

  factory AnnotationShape.fromJson(Map<String, dynamic> json) {
    final points = <Offset>[];
    final raw = json['points'];
    if (raw is List) {
      for (final item in raw) {
        if (item is List && item.length >= 2) {
          points.add(Offset(_double(item[0]), _double(item[1])));
        }
      }
    }
    return AnnotationShape(
      type: _string(json['type'], 'circle'),
      points: points,
      text: _string(json['text']),
      colorValue: _int(json['colorValue'], 0xFFFF4D4F),
      strokeWidth: _double(json['strokeWidth'], 0.006),
    );
  }
}

class GeoLocation {
  const GeoLocation({this.lat = 0, this.lng = 0, this.address = ''});

  final double lat;
  final double lng;
  final String address;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'address': address};

  factory GeoLocation.fromJson(Map<String, dynamic> json) => GeoLocation(
    lat: _double(json['lat']),
    lng: _double(json['lng']),
    address: _string(json['address']),
  );
}

class EvidencePhoto {
  const EvidencePhoto({
    required this.id,
    required this.propertyId,
    required this.room,
    required this.imageRef,
    required this.thumbRef,
    required this.timestamp,
    this.location,
    this.issueType = IssueType.none,
    this.description = '',
    this.annotations = const [],
    this.phase = PhotoPhase.moveIn,
    this.width = 0,
    this.height = 0,
    this.watermarked = true,
    this.auditLog = const [],
  });

  final String id;
  final String propertyId;
  final String room;
  final String imageRef;
  final String thumbRef;
  final DateTime timestamp;
  final GeoLocation? location;
  final IssueType issueType;
  final String description;
  final List<AnnotationShape> annotations;
  final PhotoPhase phase;
  final int width;
  final int height;
  final bool watermarked;

  /// 追加式操作记录：原始照片永不覆盖
  final List<String> auditLog;

  EvidencePhoto copyWith({
    String? room,
    IssueType? issueType,
    String? description,
    List<AnnotationShape>? annotations,
    PhotoPhase? phase,
    List<String>? auditLog,
    String? imageRef,
    String? thumbRef,
    String? locationText,
  }) => EvidencePhoto(
    id: id,
    propertyId: propertyId,
    room: room ?? this.room,
    imageRef: imageRef ?? this.imageRef,
    thumbRef: thumbRef ?? this.thumbRef,
    timestamp: timestamp,
    location: locationText == null
        ? location
        : GeoLocation(address: locationText),
    issueType: issueType ?? this.issueType,
    description: description ?? this.description,
    annotations: annotations ?? this.annotations,
    phase: phase ?? this.phase,
    width: width,
    height: height,
    watermarked: watermarked,
    auditLog: auditLog ?? this.auditLog,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'propertyId': propertyId,
    'room': room,
    'imageRef': imageRef,
    'thumbRef': thumbRef,
    'timestamp': timestamp.toIso8601String(),
    'location': location?.toJson(),
    'issueType': issueType.name,
    'description': description,
    'annotations': annotations.map((e) => e.toJson()).toList(),
    'phase': phase.name,
    'width': width,
    'height': height,
    'watermarked': watermarked,
    'auditLog': auditLog,
  };

  factory EvidencePhoto.fromJson(Map<String, dynamic> json) => EvidencePhoto(
    id: _string(json['id']),
    propertyId: _string(json['propertyId']),
    room: _string(json['room']),
    imageRef: _string(json['imageRef']),
    thumbRef: _string(json['thumbRef']),
    timestamp: parseDate(_string(json['timestamp'])),
    location: json['location'] == null
        ? null
        : GeoLocation.fromJson(_map(json['location'])),
    issueType: _enum(IssueType.values, json['issueType'], IssueType.none),
    description: _string(json['description']),
    annotations: _maps(json['annotations'])
        .map(AnnotationShape.fromJson)
        .toList(),
    phase: _enum(PhotoPhase.values, json['phase'], PhotoPhase.moveIn),
    width: _int(json['width']),
    height: _int(json['height']),
    watermarked: _bool(json['watermarked'], true),
    auditLog: _strings(json['auditLog']),
  );
}

// ---------------------------------------------------------------------------
// 费用
// ---------------------------------------------------------------------------

class RentRecord {
  const RentRecord({
    required this.id,
    required this.propertyId,
    required this.month,
    required this.amount,
    required this.dueDate,
    this.paidDate,
    this.status = RentStatus.pending,
    this.paymentMethod = '',
    this.note = '',
  });

  final String id;
  final String propertyId;
  final String month; // YYYY-MM
  final double amount;
  final DateTime dueDate;
  final DateTime? paidDate;
  final RentStatus status;
  final String paymentMethod;
  final String note;

  int get overdueDays {
    if (status == RentStatus.paid) return 0;
    final days = daysFromToday(dueDate);
    return days < 0 ? -days : 0;
  }

  RentRecord copyWith({
    double? amount,
    DateTime? dueDate,
    DateTime? paidDate,
    bool clearPaidDate = false,
    RentStatus? status,
    String? paymentMethod,
    String? note,
  }) => RentRecord(
    id: id,
    propertyId: propertyId,
    month: month,
    amount: amount ?? this.amount,
    dueDate: dueDate ?? this.dueDate,
    paidDate: clearPaidDate ? null : (paidDate ?? this.paidDate),
    status: status ?? this.status,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'propertyId': propertyId,
    'month': month,
    'amount': amount,
    'dueDate': dueDate.toIso8601String(),
    'paidDate': paidDate?.toIso8601String(),
    'status': status.name,
    'paymentMethod': paymentMethod,
    'note': note,
  };

  factory RentRecord.fromJson(Map<String, dynamic> json) => RentRecord(
    id: _string(json['id']),
    propertyId: _string(json['propertyId']),
    month: _string(json['month']),
    amount: _double(json['amount']),
    dueDate: parseDate(_string(json['dueDate'])),
    paidDate: json['paidDate'] == null
        ? null
        : parseDate(_string(json['paidDate'])),
    status: _enum(RentStatus.values, json['status'], RentStatus.pending),
    paymentMethod: _string(json['paymentMethod']),
    note: _string(json['note']),
  );
}

class UtilityReading {
  const UtilityReading({
    this.reading = 0,
    this.previousReading = 0,
    this.unitPrice = 0,
    this.photoRef,
    this.unit = '',
  });

  final double reading;
  final double previousReading;
  final double unitPrice;
  final String? photoRef;
  final String unit;

  double get usage {
    final value = reading - previousReading;
    return value > 0 ? value : 0;
  }

  double get cost => usage * unitPrice;

  UtilityReading copyWith({
    double? reading,
    double? previousReading,
    double? unitPrice,
    String? photoRef,
    String? unit,
  }) => UtilityReading(
    reading: reading ?? this.reading,
    previousReading: previousReading ?? this.previousReading,
    unitPrice: unitPrice ?? this.unitPrice,
    photoRef: photoRef ?? this.photoRef,
    unit: unit ?? this.unit,
  );

  Map<String, dynamic> toJson() => {
    'reading': reading,
    'previousReading': previousReading,
    'unitPrice': unitPrice,
    'photoRef': photoRef,
    'unit': unit,
  };

  factory UtilityReading.fromJson(Map<String, dynamic> json) => UtilityReading(
    reading: _double(json['reading']),
    previousReading: _double(json['previousReading']),
    unitPrice: _double(json['unitPrice']),
    photoRef: json['photoRef'] as String?,
    unit: _string(json['unit']),
  );
}

class UtilityRecord {
  const UtilityRecord({
    required this.id,
    required this.propertyId,
    required this.month,
    this.water,
    this.electricity,
    this.gas,
    this.otherCost = 0,
    this.otherNote = '',
    this.propertyFee = 0,
    this.networkFee = 0,
    required this.recordedAt,
    this.note = '',
    this.photoRef,
  });

  final String id;
  final String propertyId;
  final String month;
  final UtilityReading? water;
  final UtilityReading? electricity;
  final UtilityReading? gas;
  final double otherCost;
  final String otherNote;
  final double propertyFee;
  final double networkFee;
  final DateTime recordedAt;
  final String note;
  final String? photoRef;

  double get utilityCost =>
      (water?.cost ?? 0) + (electricity?.cost ?? 0) + (gas?.cost ?? 0);

  double get totalCost => utilityCost + otherCost + propertyFee + networkFee;

  UtilityRecord copyWith({
    UtilityReading? water,
    UtilityReading? electricity,
    UtilityReading? gas,
    double? otherCost,
    String? otherNote,
    double? propertyFee,
    double? networkFee,
    String? note,
    String? photoRef,
  }) => UtilityRecord(
    id: id,
    propertyId: propertyId,
    month: month,
    water: water ?? this.water,
    electricity: electricity ?? this.electricity,
    gas: gas ?? this.gas,
    otherCost: otherCost ?? this.otherCost,
    otherNote: otherNote ?? this.otherNote,
    propertyFee: propertyFee ?? this.propertyFee,
    networkFee: networkFee ?? this.networkFee,
    recordedAt: recordedAt,
    note: note ?? this.note,
    photoRef: photoRef ?? this.photoRef,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'propertyId': propertyId,
    'month': month,
    'water': water?.toJson(),
    'electricity': electricity?.toJson(),
    'gas': gas?.toJson(),
    'otherCost': otherCost,
    'otherNote': otherNote,
    'propertyFee': propertyFee,
    'networkFee': networkFee,
    'recordedAt': recordedAt.toIso8601String(),
    'note': note,
    'photoRef': photoRef,
  };

  factory UtilityRecord.fromJson(Map<String, dynamic> json) => UtilityRecord(
    id: _string(json['id']),
    propertyId: _string(json['propertyId']),
    month: _string(json['month']),
    water: json['water'] == null
        ? null
        : UtilityReading.fromJson(_map(json['water'])),
    electricity: json['electricity'] == null
        ? null
        : UtilityReading.fromJson(_map(json['electricity'])),
    gas: json['gas'] == null
        ? null
        : UtilityReading.fromJson(_map(json['gas'])),
    otherCost: _double(json['otherCost']),
    otherNote: _string(json['otherNote']),
    propertyFee: _double(json['propertyFee']),
    networkFee: _double(json['networkFee']),
    recordedAt: parseDate(_string(json['recordedAt'])),
    note: _string(json['note']),
    photoRef: json['photoRef'] as String?,
  );
}

class MonthlyExpense {
  const MonthlyExpense({
    required this.month,
    required this.rent,
    required this.utility,
    required this.other,
  });

  final String month;
  final double rent;
  final double utility;
  final double other;

  double get total => rent + utility + other;
}

// ---------------------------------------------------------------------------
// 维修 / 房东要求 / 沟通
// ---------------------------------------------------------------------------

class RepairRecord {
  const RepairRecord({
    required this.id,
    required this.propertyId,
    required this.item,
    required this.description,
    this.photoRefs = const [],
    required this.reportedAt,
    this.status = RepairStatus.pending,
    this.completedAt,
    this.costPaidBy = CostBearer.undecided,
    this.cost = 0,
    this.note = '',
  });

  final String id;
  final String propertyId;
  final String item;
  final String description;
  final List<String> photoRefs;
  final DateTime reportedAt;
  final RepairStatus status;
  final DateTime? completedAt;
  final CostBearer costPaidBy;
  final double cost;
  final String note;

  static const List<String> commonItems = [
    '热水器',
    '马桶',
    '空调',
    '门锁',
    '水龙头',
    '洗衣机',
    '冰箱',
    '燃气灶',
    '灯具',
    '网络',
    '其他',
  ];

  RepairRecord copyWith({
    String? item,
    String? description,
    List<String>? photoRefs,
    RepairStatus? status,
    DateTime? completedAt,
    CostBearer? costPaidBy,
    double? cost,
    String? note,
  }) => RepairRecord(
    id: id,
    propertyId: propertyId,
    item: item ?? this.item,
    description: description ?? this.description,
    photoRefs: photoRefs ?? this.photoRefs,
    reportedAt: reportedAt,
    status: status ?? this.status,
    completedAt: completedAt ?? this.completedAt,
    costPaidBy: costPaidBy ?? this.costPaidBy,
    cost: cost ?? this.cost,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'propertyId': propertyId,
    'item': item,
    'description': description,
    'photoRefs': photoRefs,
    'reportedAt': reportedAt.toIso8601String(),
    'status': status.name,
    'completedAt': completedAt?.toIso8601String(),
    'costPaidBy': costPaidBy.name,
    'cost': cost,
    'note': note,
  };

  factory RepairRecord.fromJson(Map<String, dynamic> json) => RepairRecord(
    id: _string(json['id']),
    propertyId: _string(json['propertyId']),
    item: _string(json['item']),
    description: _string(json['description']),
    photoRefs: _strings(json['photoRefs']),
    reportedAt: parseDate(_string(json['reportedAt'])),
    status: _enum(RepairStatus.values, json['status'], RepairStatus.pending),
    completedAt: json['completedAt'] == null
        ? null
        : parseDate(_string(json['completedAt'])),
    costPaidBy: _enum(
      CostBearer.values,
      json['costPaidBy'],
      CostBearer.undecided,
    ),
    cost: _double(json['cost']),
    note: _string(json['note']),
  );
}

class LandlordRule {
  const LandlordRule({
    required this.id,
    required this.propertyId,
    required this.content,
    this.source = RuleSource.contract,
    this.evidenceRefs = const [],
    required this.createdAt,
  });

  final String id;
  final String propertyId;
  final String content;
  final RuleSource source;
  final List<String> evidenceRefs;
  final DateTime createdAt;

  static const List<String> presets = [
    '不可养宠物',
    '不可在墙上钉钉 / 打孔',
    '不可转租',
    '不可改变房屋结构',
    '退租需恢复原样',
    '退租需提前 30 天通知',
    '不可使用某间房间',
  ];

  LandlordRule copyWith({
    String? content,
    RuleSource? source,
    List<String>? evidenceRefs,
  }) => LandlordRule(
    id: id,
    propertyId: propertyId,
    content: content ?? this.content,
    source: source ?? this.source,
    evidenceRefs: evidenceRefs ?? this.evidenceRefs,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'propertyId': propertyId,
    'content': content,
    'source': source.name,
    'evidenceRefs': evidenceRefs,
    'createdAt': createdAt.toIso8601String(),
  };

  factory LandlordRule.fromJson(Map<String, dynamic> json) => LandlordRule(
    id: _string(json['id']),
    propertyId: _string(json['propertyId']),
    content: _string(json['content']),
    source: _enum(RuleSource.values, json['source'], RuleSource.contract),
    evidenceRefs: _strings(json['evidenceRefs']),
    createdAt: parseDate(_string(json['createdAt'])),
  );
}

class CommunicationRecord {
  const CommunicationRecord({
    required this.id,
    required this.propertyId,
    this.type = CommType.text,
    this.content = '',
    this.screenshotRefs = const [],
    this.tags = const [],
    required this.timestamp,
    this.isKeyPromise = false,
  });

  final String id;
  final String propertyId;
  final CommType type;
  final String content;
  final List<String> screenshotRefs;
  final List<String> tags;
  final DateTime timestamp;

  /// 关键承诺：退租时的反驳依据
  final bool isKeyPromise;

  static const List<String> tagOptions = ['押金', '维修', '续租', '退租', '涨租', '其他'];

  CommunicationRecord copyWith({
    CommType? type,
    String? content,
    List<String>? screenshotRefs,
    List<String>? tags,
    bool? isKeyPromise,
  }) => CommunicationRecord(
    id: id,
    propertyId: propertyId,
    type: type ?? this.type,
    content: content ?? this.content,
    screenshotRefs: screenshotRefs ?? this.screenshotRefs,
    tags: tags ?? this.tags,
    timestamp: timestamp,
    isKeyPromise: isKeyPromise ?? this.isKeyPromise,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'propertyId': propertyId,
    'type': type.name,
    'content': content,
    'screenshotRefs': screenshotRefs,
    'tags': tags,
    'timestamp': timestamp.toIso8601String(),
    'isKeyPromise': isKeyPromise,
  };

  factory CommunicationRecord.fromJson(Map<String, dynamic> json) =>
      CommunicationRecord(
        id: _string(json['id']),
        propertyId: _string(json['propertyId']),
        type: _enum(CommType.values, json['type'], CommType.text),
        content: _string(json['content']),
        screenshotRefs: _strings(json['screenshotRefs']),
        tags: _strings(json['tags']),
        timestamp: parseDate(_string(json['timestamp'])),
        isKeyPromise: _bool(json['isKeyPromise']),
      );
}

// ---------------------------------------------------------------------------
// 设置 / 提醒
// ---------------------------------------------------------------------------

class ReminderSettings {
  const ReminderSettings({
    this.enableRent = true,
    this.rentDaysAhead = 3,
    this.enableContract = true,
    this.contractDaysAhead = const [30, 7],
    this.enableUtility = true,
    this.utilityDay = 1,
    this.enableDeposit = true,
  });

  final bool enableRent;
  final int rentDaysAhead;
  final bool enableContract;
  final List<int> contractDaysAhead;
  final bool enableUtility;
  final int utilityDay;
  final bool enableDeposit;

  ReminderSettings copyWith({
    bool? enableRent,
    int? rentDaysAhead,
    bool? enableContract,
    List<int>? contractDaysAhead,
    bool? enableUtility,
    int? utilityDay,
    bool? enableDeposit,
  }) => ReminderSettings(
    enableRent: enableRent ?? this.enableRent,
    rentDaysAhead: rentDaysAhead ?? this.rentDaysAhead,
    enableContract: enableContract ?? this.enableContract,
    contractDaysAhead: contractDaysAhead ?? this.contractDaysAhead,
    enableUtility: enableUtility ?? this.enableUtility,
    utilityDay: utilityDay ?? this.utilityDay,
    enableDeposit: enableDeposit ?? this.enableDeposit,
  );

  Map<String, dynamic> toJson() => {
    'enableRent': enableRent,
    'rentDaysAhead': rentDaysAhead,
    'enableContract': enableContract,
    'contractDaysAhead': contractDaysAhead,
    'enableUtility': enableUtility,
    'utilityDay': utilityDay,
    'enableDeposit': enableDeposit,
  };

  factory ReminderSettings.fromJson(Map<String, dynamic> json) {
    final days = json['contractDaysAhead'];
    return ReminderSettings(
      enableRent: _bool(json['enableRent'], true),
      rentDaysAhead: _int(json['rentDaysAhead'], 3),
      enableContract: _bool(json['enableContract'], true),
      contractDaysAhead: days is List
          ? days.map((e) => _int(e)).toList()
          : const [30, 7],
      enableUtility: _bool(json['enableUtility'], true),
      utilityDay: _int(json['utilityDay'], 1),
      enableDeposit: _bool(json['enableDeposit'], true),
    );
  }
}

/// 外观偏好：跟随系统 / 浅色 / 深色
enum AppAppearance {
  system('跟随系统'),
  light('浅色'),
  dark('深色');

  const AppAppearance(this.label);
  final String label;
}

class AppSettings {
  const AppSettings({
    this.reminders = const ReminderSettings(),
    this.userName = '',
    this.avatarRef = '',
    this.birthday = '',
    this.appearance = AppAppearance.system,
    this.systemNotifications = false,
    this.defaultWaterPrice = 3.5,
    this.defaultElectricityPrice = 0.55,
    this.defaultGasPrice = 2.6,
  });

  final ReminderSettings reminders;
  final String userName;

  /// 头像：登录后是云端路径，游客是本机媒体引用
  final String avatarRef;

  /// 生日（yyyy-MM-dd），留空表示没填
  final String birthday;
  final AppAppearance appearance;

  /// 是否把待办推送到系统通知栏（默认关：需要用户授权，不在启动时打扰）
  final bool systemNotifications;
  final double defaultWaterPrice;
  final double defaultElectricityPrice;
  final double defaultGasPrice;

  AppSettings copyWith({
    ReminderSettings? reminders,
    String? userName,
    String? avatarRef,
    String? birthday,
    AppAppearance? appearance,
    bool? systemNotifications,
    double? defaultWaterPrice,
    double? defaultElectricityPrice,
    double? defaultGasPrice,
  }) => AppSettings(
    reminders: reminders ?? this.reminders,
    userName: userName ?? this.userName,
    avatarRef: avatarRef ?? this.avatarRef,
    birthday: birthday ?? this.birthday,
    appearance: appearance ?? this.appearance,
    systemNotifications: systemNotifications ?? this.systemNotifications,
    defaultWaterPrice: defaultWaterPrice ?? this.defaultWaterPrice,
    defaultElectricityPrice:
        defaultElectricityPrice ?? this.defaultElectricityPrice,
    defaultGasPrice: defaultGasPrice ?? this.defaultGasPrice,
  );

  Map<String, dynamic> toJson() => {
    'reminders': reminders.toJson(),
    'userName': userName,
    'avatarRef': avatarRef,
    'birthday': birthday,
    'appearance': appearance.name,
    'systemNotifications': systemNotifications,
    'defaultWaterPrice': defaultWaterPrice,
    'defaultElectricityPrice': defaultElectricityPrice,
    'defaultGasPrice': defaultGasPrice,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    reminders: ReminderSettings.fromJson(_map(json['reminders'])),
    userName: _string(json['userName']),
    avatarRef: _string(json['avatarRef']),
    birthday: _string(json['birthday']),
    appearance: _enum(
      AppAppearance.values,
      json['appearance'],
      AppAppearance.system,
    ),
    systemNotifications: _bool(json['systemNotifications'], false),
    defaultWaterPrice: _double(json['defaultWaterPrice'], 3.5),
    defaultElectricityPrice: _double(json['defaultElectricityPrice'], 0.55),
    defaultGasPrice: _double(json['defaultGasPrice'], 2.6),
  );
}

enum ReminderKind {
  rentDue('交租提醒'),
  contractExpire('合同到期'),
  utilityReading('抄表提醒'),
  depositReturn('押金退还'),
  photoMissing('取证待办'),
  moveInReading('表底数待补');

  const ReminderKind(this.label);
  final String label;
}

class ReminderItem {
  const ReminderItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.date,
    required this.daysLeft,
    required this.propertyId,
    required this.propertyName,
    this.tone = ZTone.brand,
    this.actionLabel = '去处理',
    this.until,
  });

  final ReminderKind kind;
  final String title;
  final String subtitle;
  final DateTime date;
  final int daysLeft;
  final String propertyId;
  final String propertyName;
  final ZTone tone;
  final String actionLabel;

  /// 这件事的有效期上限（例如交租提醒不该排到合同到期之后）
  final DateTime? until;
}
