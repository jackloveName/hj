import '../models/models.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';

/// 纯业务逻辑层：不依赖任何存储 / 平台能力，可直接单元测试。

class HealthItem {
  const HealthItem({required this.label, required this.ok, required this.hint});

  final String label;
  final bool ok;
  final String hint;
}

class EvidenceHealth {
  const EvidenceHealth({required this.ratio, required this.items});

  final double ratio;
  final List<HealthItem> items;
}

/// 按合同租期生成租金计划。
/// 已存在的记录按月份保留（含 id 与已付状态），只补缺失月份、刷新未付月份的金额与应付日。
List<RentRecord> buildRentSchedule({
  required Property property,
  required List<RentRecord> existing,
  required DateTime today,
}) {
  final contract = property.contract;
  final months = <String>[];
  var cursor = DateTime(contract.moveInDate.year, contract.moveInDate.month, 1);
  final end = DateTime(
    contract.contractEnd.year,
    contract.contractEnd.month,
    1,
  );
  var guard = 0;
  // 上限 50 年：防止到期日填错（如 2126 年）时无限生成
  while (!cursor.isAfter(end) && guard < 600) {
    months.add(monthKey(cursor));
    cursor = DateTime(cursor.year, cursor.month + 1, 1);
    guard++;
  }

  final day = contract.rentDueDay.clamp(1, 28);
  final byMonth = <String, RentRecord>{
    for (final record in existing) record.month: record,
  };
  final result = <RentRecord>[];
  for (final month in months) {
    final parts = month.split('-');
    final due = DateTime(int.parse(parts[0]), int.parse(parts[1]), day);
    final record = byMonth[month];
    if (record == null) {
      // 入住当月的房租：到了交租日（含当天）就默认算已交 —— 签合同时付首月是常态，
      // 而且过了日子还算逾期会平白多出一条「房租已逾期」的待办。
      // 但**还没到交租日**就不能默认「已交」：刚建完房源、一天没住，
      // 不该看到「已缴 1 个月」。
      final moveInPaid = month == months.first && !due.isAfter(today);
      result.add(
        RentRecord(
          id: newId('rent'),
          propertyId: property.id,
          month: month,
          amount: contract.monthlyRent,
          dueDate: due,
          status: moveInPaid
              ? RentStatus.paid
              : (due.isBefore(today)
                    ? RentStatus.overdue
                    : RentStatus.pending),
          paidDate: moveInPaid ? contract.moveInDate : null,
        ),
      );
    } else if (record.status == RentStatus.paid) {
      result.add(record);
    } else {
      result.add(record.copyWith(amount: contract.monthlyRent, dueDate: due));
    }
  }
  return result;
}

/// 合并租金计划：计划内的月份以计划为准，计划外（合同改短后遗留）的历史记录原样保留，
/// 避免编辑房源时误删已付账单。
List<RentRecord> mergeRentSchedule({
  required List<RentRecord> existing,
  required List<RentRecord> planned,
}) {
  final plannedByMonth = <String, RentRecord>{
    for (final record in planned) record.month: record,
  };
  final merged = <RentRecord>[];
  for (final record in existing) {
    merged.add(plannedByMonth.remove(record.month) ?? record);
  }
  merged.addAll(plannedByMonth.values);
  merged.sort((a, b) => a.month.compareTo(b.month));
  return merged;
}

/// 已缴月数：以真实已付记录为准，保证与「累计已付租金」口径一致。
int countPaidMonths(List<RentRecord> rents, String propertyId) => rents
    .where((r) => r.propertyId == propertyId && r.status == RentStatus.paid)
    .length;

/// 押金状态 → 房源状态的联动规则（双向可改，不会把房源状态锁死）。
PropertyStatus statusForDeposit(DepositStatus deposit) => switch (deposit) {
  DepositStatus.none => PropertyStatus.active,
  DepositStatus.paid => PropertyStatus.active,
  DepositStatus.toBeReturned => PropertyStatus.ended,
  DepositStatus.partiallyDeducted => PropertyStatus.ended,
  DepositStatus.returned => PropertyStatus.ended,
  DepositStatus.inDispute => PropertyStatus.dispute,
};

/// 还能不能给这套房子新增抄表记录：**已退租（含维权中）之后只读归档**，
/// 只能翻记录、导出，不再允许新增或修改。
bool canAddUtility(Property property) =>
    property.status == PropertyStatus.active;

/// 还能不能新增维修 / 沟通记录：已退租就归档只读；
/// 押金纠纷期间仍然允许继续记录沟通（维权要留证）。
bool canAddTimeline(Property property) =>
    property.status != PropertyStatus.ended;

int _countPhotos(
  List<EvidencePhoto> photos,
  String propertyId, {
  PhotoPhase? phase,
  String? room,
}) => photos
    .where(
      (photo) =>
          photo.propertyId == propertyId &&
          (phase == null || photo.phase == phase) &&
          (room == null || photo.room == room),
    )
    .length;

UtilityRecord? _utilityOf(
  List<UtilityRecord> utilities,
  String propertyId,
  String month,
) {
  for (final record in utilities) {
    if (record.propertyId == propertyId && record.month == month) {
      return record;
    }
  }
  return null;
}

/// 「日历上一个月」的月份键：2026-01 → 2025-12。
/// 抄表录入的「上月读数」按自然月取，而不是取最近一条记录。
String previousMonthKey(String month) {
  final parts = month.split('-');
  if (parts.length != 2) return month;
  final year = int.tryParse(parts[0]);
  final index = int.tryParse(parts[1]);
  if (year == null || index == null || index < 1 || index > 12) return month;
  return monthKey(DateTime(year, index - 1, 1));
}

/// 取「日历上一月」的抄表记录；没有则返回 null（视为无上月读数）。
UtilityRecord? previousUtilityOf({
  required List<UtilityRecord> utilities,
  required String propertyId,
  required String month,
}) => _utilityOf(utilities, propertyId, previousMonthKey(month));

/// 存证健康度（对应设计稿「存证健康度」）
EvidenceHealth buildHealth({
  required Property property,
  required List<EvidencePhoto> photos,
  required List<UtilityRecord> utilities,
  required DateTime now,
}) {
  final rooms = property.allRooms;
  final covered = rooms
      .where(
        (room) =>
            _countPhotos(
              photos,
              property.id,
              phase: PhotoPhase.moveIn,
              room: room,
            ) >
            0,
      )
      .length;
  final contractOk = property.contract.contractPhotoRefs.isNotEmpty;
  final utilityOk = _utilityOf(utilities, property.id, monthKey(now)) != null;
  final moveOutCount = _countPhotos(
    photos,
    property.id,
    phase: PhotoPhase.moveOut,
  );

  final roomRatio = rooms.isEmpty ? 0.0 : covered / rooms.length;
  var score = roomRatio * 0.5;
  score += contractOk ? 0.2 : 0;
  score += utilityOk ? 0.15 : 0;
  score += moveOutCount > 0 ? 0.15 : 0;

  return EvidenceHealth(
    ratio: score.clamp(0.0, 1.0),
    items: [
      HealthItem(
        label: '已取证房间',
        ok: covered == rooms.length,
        hint:
            '$covered / ${rooms.length}${covered == rooms.length ? ' ✓' : ''}',
      ),
      HealthItem(
        label: '合同照片',
        ok: contractOk,
        hint: contractOk
            ? '${property.contract.contractPhotoRefs.length} 张'
            : '未上传（建议补）',
      ),
      HealthItem(
        label: '水电读数',
        ok: utilityOk,
        hint: utilityOk ? '本月已记录' : '本月未记录',
      ),
      HealthItem(
        label: '退租取证',
        ok: moveOutCount > 0,
        hint: moveOutCount > 0 ? '$moveOutCount 张' : '未开始',
      ),
    ],
  );
}

/// 待办提醒（对应设计稿首页「待办提醒」）
List<ReminderItem> buildReminders({
  required List<Property> properties,
  required List<EvidencePhoto> photos,
  required List<UtilityRecord> utilities,
  required List<RentRecord> rents,
  required ReminderSettings config,
  required DateTime now,
}) {
  final list = <ReminderItem>[];
  final today = dateOnly(now);

  for (final property in properties) {
    final waitingDays = now.difference(property.updatedAt).inDays;

    if (config.enableDeposit &&
        property.status == PropertyStatus.ended &&
        property.deposit.status == DepositStatus.toBeReturned) {
      list.add(
        ReminderItem(
          kind: ReminderKind.depositReturn,
          title: '押金待退还',
          subtitle: '${property.name} · 已等待 $waitingDays 天',
          date: property.updatedAt,
          daysLeft: 0,
          propertyId: property.id,
          propertyName: property.name,
          tone: ZTone.warn,
          actionLabel: '催要押金',
        ),
      );
    }
    if (property.status == PropertyStatus.dispute) {
      list.add(
        ReminderItem(
          kind: ReminderKind.depositReturn,
          title: '押金纠纷维权中',
          subtitle: '${property.name} · 可导出对比报告与催告函',
          date: property.updatedAt,
          daysLeft: 0,
          propertyId: property.id,
          propertyName: property.name,
          tone: ZTone.danger,
          actionLabel: '去维权',
        ),
      );
    }
    if (property.status != PropertyStatus.active) continue;

    if (config.enableRent) {
      // 优先提示真正未付的账单：交租日过去后不能再跳到下一个月
      final unpaid =
          rents
              .where(
                (r) =>
                    r.propertyId == property.id && r.status != RentStatus.paid,
              )
              .toList()
            ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
      final overdue = unpaid.where((r) => r.dueDate.isBefore(today)).toList();

      if (overdue.isNotEmpty) {
        final record = overdue.first;
        final overdueDays = daysBetween(record.dueDate, now);
        list.add(
          ReminderItem(
            kind: ReminderKind.rentDue,
            title: '房租已逾期 · ${fmtMoney(record.amount)}',
            subtitle: '${fmtMonthDay(record.dueDate)} 应付 · 已逾期 $overdueDays 天',
            date: record.dueDate,
            daysLeft: -overdueDays,
            propertyId: property.id,
            propertyName: property.name,
            tone: ZTone.danger,
            actionLabel: '已逾期',
          ),
        );
      } else {
        final due = nextRentDue(property.contract.rentDueDay, from: now);
        final days = daysBetween(now, due);
        if (days <= config.rentDaysAhead) {
          list.add(
            ReminderItem(
              kind: ReminderKind.rentDue,
              title: '该交房租了 · ${fmtMoney(property.contract.monthlyRent)}',
              subtitle:
                  '${fmtMonthDay(due)} 到期 · ${property.contract.paymentMethod}',
              date: due,
              daysLeft: days,
              propertyId: property.id,
              propertyName: property.name,
              tone: ZTone.warn,
              // 别写死「N 天后」：当天是「就是今天」、第二天是「明天」
              actionLabel: relativeDays(days),
              // 交租提醒不该排到合同到期之后
              until: property.contract.contractEnd,
            ),
          );
        }
      }
    }

    if (config.enableUtility &&
        _utilityOf(utilities, property.id, monthKey(now)) == null) {
      final latest = utilities
          .where((u) => u.propertyId == property.id)
          .fold<UtilityRecord?>(
            null,
            (best, item) =>
                best == null || item.recordedAt.isAfter(best.recordedAt)
                ? item
                : best,
          );
      list.add(
        ReminderItem(
          kind: ReminderKind.utilityReading,
          title: '本月水电还没抄表',
          subtitle: latest == null
              ? '建议本月抄表并拍照留证'
              : '上次记录 ${fmtMonthDay(latest.recordedAt)}',
          date: DateTime(now.year, now.month, config.utilityDay),
          daysLeft: 0,
          propertyId: property.id,
          propertyName: property.name,
          tone: ZTone.brand,
          actionLabel: '去记录',
        ),
      );
    }

    if (config.enableContract && property.contract.contractEnd.isAfter(now)) {
      final days = daysBetween(now, property.contract.contractEnd);
      final thresholds = [...config.contractDaysAhead]..sort();
      final max = thresholds.isEmpty ? 30 : thresholds.last;
      if (days <= max) {
        list.add(
          ReminderItem(
            kind: ReminderKind.contractExpire,
            title: '合同到期提醒',
            subtitle:
                '${fmtDate(property.contract.contractEnd)} 到期 · 提前 $max 天',
            date: property.contract.contractEnd,
            daysLeft: days,
            propertyId: property.id,
            propertyName: property.name,
            tone: days <= (thresholds.isEmpty ? 7 : thresholds.first)
                ? ZTone.danger
                : ZTone.brand,
            actionLabel: relativeDays(days),
          ),
        );
      }
    }

    if (_countPhotos(photos, property.id, phase: PhotoPhase.moveIn) == 0) {
      list.add(
        ReminderItem(
          kind: ReminderKind.photoMissing,
          title: '还没有入住取证',
          subtitle: '入住时拍照留证，退租时才说得清',
          date: now,
          daysLeft: 0,
          propertyId: property.id,
          propertyName: property.name,
          tone: ZTone.brand,
          actionLabel: '去拍照',
        ),
      );
    }
  }

  // 逾期 > 待处理 > 提醒 > 提示：天数越紧越靠前
  list.sort((a, b) {
    final byUrgency = _urgency(a.tone).compareTo(_urgency(b.tone));
    if (byUrgency != 0) return byUrgency;
    return a.daysLeft.compareTo(b.daysLeft);
  });
  return list;
}

/// 语义色 → 提醒紧急度（数字越小越紧急）。
int _urgency(ZTone tone) => switch (tone) {
  ZTone.danger => 0,
  ZTone.warn => 1,
  ZTone.violet => 2,
  ZTone.brand => 3,
  ZTone.neutral => 4,
  ZTone.ok => 5,
};

/// 某月支出构成（对应设计稿「本月构成」）
MonthlyExpense computeMonthlyExpense({
  required List<RentRecord> rents,
  required List<UtilityRecord> utilities,
  required String propertyId,
  required String month,
}) {
  RentRecord? rent;
  for (final record in rents) {
    if (record.propertyId == propertyId && record.month == month) {
      rent = record;
      break;
    }
  }
  final utility = _utilityOf(utilities, propertyId, month);
  return MonthlyExpense(
    month: month,
    rent: rent?.amount ?? 0,
    utility: utility?.utilityCost ?? 0,
    other:
        (utility?.propertyFee ?? 0) +
        (utility?.networkFee ?? 0) +
        (utility?.otherCost ?? 0),
  );
}

/// 最近 N 个月支出（按时间正序）
List<MonthlyExpense> buildExpenseTrend({
  required List<RentRecord> rents,
  required List<UtilityRecord> utilities,
  required String propertyId,
  required DateTime now,
  int months = 6,
}) => [
  for (var i = months - 1; i >= 0; i--)
    computeMonthlyExpense(
      rents: rents,
      utilities: utilities,
      propertyId: propertyId,
      month: monthKey(DateTime(now.year, now.month - i, 1)),
    ),
];

double sumPaidRent(List<RentRecord> rents, String propertyId) => rents
    .where((r) => r.propertyId == propertyId && r.status == RentStatus.paid)
    .fold(0.0, (sum, r) => sum + r.amount);

double sumUtilityCost(List<UtilityRecord> utilities, String propertyId) =>
    utilities
        .where((u) => u.propertyId == propertyId)
        .fold(0.0, (sum, u) => sum + u.totalCost);

/// 某年的抄表合计：金额、三种表的用量、固定费用
class UtilityYearSummary {
  const UtilityYearSummary({
    this.months = 0,
    this.cost = 0,
    this.electricity = 0,
    this.water = 0,
    this.gas = 0,
    this.propertyFee = 0,
    this.networkFee = 0,
  });

  /// 有记录的月份数
  final int months;

  /// 合计金额（含物业 / 网络）
  final double cost;
  final double electricity;
  final double water;
  final double gas;
  final double propertyFee;
  final double networkFee;

  static const UtilityYearSummary empty = UtilityYearSummary();
}

/// 汇总某个年份的抄表数据（用于「全部抄表记录」的年度合计）
UtilityYearSummary summarizeUtilityYear(
  List<UtilityRecord> utilities,
  String propertyId,
  String year,
) {
  var summary = UtilityYearSummary.empty;
  for (final record in utilities) {
    if (record.propertyId != propertyId) continue;
    if (!record.month.startsWith(year)) continue;
    summary = UtilityYearSummary(
      months: summary.months + 1,
      cost: summary.cost + record.totalCost,
      electricity:
          summary.electricity + (record.electricity?.usage ?? 0),
      water: summary.water + (record.water?.usage ?? 0),
      gas: summary.gas + (record.gas?.usage ?? 0),
      propertyFee: summary.propertyFee + record.propertyFee,
      networkFee: summary.networkFee + record.networkFee,
    );
  }
  return summary;
}

double sumYearlyExpense(
  List<RentRecord> rents,
  List<UtilityRecord> utilities,
  String propertyId,
  int year,
) {
  final rent = rents
      .where(
        (r) =>
            r.propertyId == propertyId &&
            r.month.startsWith('$year') &&
            r.status == RentStatus.paid,
      )
      .fold(0.0, (sum, r) => sum + r.amount);
  final utility = utilities
      .where((u) => u.propertyId == propertyId && u.month.startsWith('$year'))
      .fold(0.0, (sum, u) => sum + u.totalCost);
  return rent + utility;
}

/// 云端与本机数据的合并策略：以云端为准，本机独有的记录按 id 追加。
///
/// 用于「游客数据并入账号」和「本机有未同步改动时的合并」，
/// 避免任一侧的数据被直接覆盖掉。
Map<String, dynamic> mergeDatasets(
  Map<String, dynamic> cloud,
  Map<String, dynamic> local,
) {
  final merged = Map<String, dynamic>.from(cloud);
  // 删除标记先合并：只要有一端删过，这条就不该再出现（删除优先），
  // 否则"在 A 设备删掉的记录会被 B 设备/云端带回来"
  final tombstones = _mergeTombstones(cloud, local);
  for (final key in _recordKeys) {
    final cloudList = _records(cloud[key]);
    final dead = tombstones[key] ?? const <String, String>{};
    // 租金与抄表是「一套房子 + 一个月一条」：按这个键去重，
    // 否则两台设备各自生成过同月账单，合并后会同一个月出现两条
    final byMonth = key == 'rents' || key == 'utilities';
    final seen = <String>{
      for (final record in cloudList)
        byMonth
            ? '${record['propertyId']}|${record['month']}'
            : '${record['id']}',
    };
    final extra = [
      for (final record in _records(local[key]))
        if (!seen.contains(
          byMonth
              ? '${record['propertyId']}|${record['month']}'
              : '${record['id']}',
        ))
          record,
    ];
    merged[key] = [
      for (final record in [...cloudList, ...extra])
        if (!_isDeleted(record, key, dead)) record,
    ];
  }
  if (tombstones.isNotEmpty) merged['deleted'] = tombstones;
  // 设置与当前房源：云端有值就以云端为准，避免本机默认值盖掉云端配置
  merged['settings'] = cloud['settings'] ?? local['settings'];
  merged['activeId'] = cloud['activeId'] ?? local['activeId'];
  final cloudVersion = cloud['version'];
  final localVersion = local['version'];
  merged['version'] = cloudVersion is int
      ? cloudVersion
      : (localVersion is int ? localVersion : 1);
  return merged;
}

/// 两端的删除标记取并集，同一个 id 取更晚的时间
Map<String, Map<String, String>> _mergeTombstones(
  Map<String, dynamic> cloud,
  Map<String, dynamic> local,
) {
  final result = <String, Map<String, String>>{};
  for (final source in [cloud['deleted'], local['deleted']]) {
    if (source is! Map) continue;
    source.forEach((key, value) {
      if (value is! Map) return;
      final ids = result['$key'] ??= <String, String>{};
      value.forEach((id, time) {
        final name = '$id';
        final stamp = '$time';
        final existing = ids[name];
        if (existing == null || stamp.compareTo(existing) > 0) {
          ids[name] = stamp;
        }
      });
    });
  }
  result.removeWhere((_, ids) => ids.isEmpty);
  return result;
}

/// 这条记录是否已被标记删除（租金 / 抄表按「房子 + 月份」判，其余按 id）
bool _isDeleted(
  Map<String, dynamic> record,
  String key,
  Map<String, String> dead,
) {
  if (dead.isEmpty) return false;
  if (key == 'rents' || key == 'utilities') {
    if (dead.containsKey('${record['id']}')) return true;
    final monthKey = '${record['propertyId']}|${record['month']}';
    return dead.containsKey(monthKey);
  }
  return dead.containsKey('${record['id']}');
}

const List<String> _recordKeys = [
  'properties',
  'photos',
  'rents',
  'utilities',
  'repairs',
  'rules',
  'comms',
];

List<Map<String, dynamic>> _records(Object? raw) => raw is List
    ? [
        for (final item in raw)
          if (item is Map) item.map((k, v) => MapEntry(k.toString(), v)),
      ]
    : <Map<String, dynamic>>[];
