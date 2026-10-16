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

/// 房源状态**不跟着押金走**（口径）：押金只是一笔钱的状态，把它改成
/// 「待退还 / 已退还 / 部分扣除 / 纠纷中」都不该顺手把房子标成「已退租」——
/// 人还住着呢，只是钱的事记了一笔（以前租住中的房子改押金会被映射成已退租，
/// 出现「没退租却变已退租」的怪事）。
///
/// 房源状态只有两个出口：退租页的「完成退租」和详情页的「去纠纷」。
/// 反过来也一样：已退租 / 纠纷中的房子改押金，房源状态一动不动。

/// 还能不能给这套房子新增抄表记录：**已退租（含维权中）之后只读归档**，
/// 只能翻记录、导出，不再允许新增或修改。
bool canAddUtility(Property property) =>
    property.status == PropertyStatus.active;

/// 还能不能改这套房的资料（房源信息、合同、照片、法律要求）：
/// **只有在租住中**。
///
/// 从「历史租住」点进来的是过去的事：已退租只允许查看，
/// 纠纷中只留「维权」相关的几件事（继续记沟通留证见 [canAddTimeline]，
/// 结算押金走退租页）。
bool canEditProperty(Property property) =>
    property.status == PropertyStatus.active;

/// 「房东要求」一共几条：记下来的约定 + 合同里写的特殊条款。
///
/// 合同里的特殊条款也是房东要求（房东要求页就是这么并排展示的），
/// 所以详情页那个格子、维权材料那行、归档视图都按这个口径数，别各数各的 ——
/// 否则合同里写着「不可养宠物」却显示「0 条约定」。
int landlordRuleCount(Property property, List<LandlordRule> rules) =>
    rules.length + (property.contract.specialTerms.trim().isEmpty ? 0 : 1);

/// 押金那行怎么说：退了 / 被扣 / 还是没退。
///
/// 历史卡片、费用页的押金总览都用它，口径一致（没退到手就照实写「未退还」）。
String depositLine(Property property) {
  final deposit = property.deposit;
  final total = property.contract.deposit;
  return switch (deposit.status) {
    DepositStatus.returned =>
      '押金已退还'
          '${deposit.returnedAmount > 0 ? ' ${fmtMoney(deposit.returnedAmount)}' : ''}',
    DepositStatus.partiallyDeducted =>
      '押金退还 ${fmtMoney(deposit.returnedAmount)}'
          ' · 扣除 ${fmtMoney(deposit.deductedAmount)}',
    DepositStatus.toBeReturned => '押金 ${fmtMoney(total)} 未退还',
    DepositStatus.inDispute =>
      '押金${deposit.status.label}（${fmtMoney(total)}）',
    // 「押金无押金」不成话：没押金的房子直接说清楚
    DepositStatus.none => '本房源无需押金',
    _ => '押金${deposit.status.label}',
  };
}

/// 还没退到手的押金：待退还算全部；纠纷中算争议的那部分（没填金额就算全部）；
/// 已退还不算。**部分扣除也不算在这条口径里** —— 那笔钱是被房东扣走的，
/// 但也确实没回到手上，所以另有 [deductedDeposit] 单独数它，
/// 摘要卡会把两者都摆出来（不然会出现「费用页说押金没退、摘要说已结清」的矛盾）。
double outstandingDeposit(Property property) {
  final deposit = property.deposit;
  return switch (deposit.status) {
    DepositStatus.toBeReturned ||
    DepositStatus.paid => property.contract.deposit,
    DepositStatus.inDispute =>
      deposit.deductedAmount > 0 ? deposit.deductedAmount : property.contract.deposit,
    _ => 0,
  };
}

/// 「部分扣除」里被房东扣走、没回到手上的那部分。
///
/// 和 [outstandingDeposit] 分开：前者是「还在等退还」，这是「已经确定被扣」，
/// 摘要里两者都算「没到手」，但说法不同。
double deductedDeposit(Property property) =>
    property.deposit.status == DepositStatus.partiallyDeducted
    ? property.deposit.deductedAmount
    : 0;

/// 这套房的押金还「没回到手上」吗 —— **看状态，不看金额**。
///
/// 只有「已退还」和「无押金」算结清；已缴纳 / 待退还 / 部分扣除 / 纠纷中都算没到手。
/// 金额可以没填（0），但状态说了算 —— 按金额判断的话，没填金额的房子
/// 会被摘要卡算成「押金都结清了」，而用户明明还等着房东退钱。
bool depositNotBack(Property property) => switch (property.deposit.status) {
  DepositStatus.returned || DepositStatus.none => false,
  _ => true,
};

/// 押金状态能不能从 [from] 改成 [to]（口径：**只能往前走，不能回头**）。
///
///   已缴纳 → 待退还 / 部分扣除 / 已退还 / 纠纷中
///   待退还 → 部分扣除 / 已退还 / 纠纷中
///   部分扣除 → 已退还 / 纠纷中
///   已退还 → 到头了，什么都不能改
///   无押金 → 先走「要不要押金」那一问（见押金追踪页的提问卡）
///   纠纷中 → 部分扣除 / 已退还（维权谈成的两个结果）
///
/// 「已缴纳」只有本来就停在它上面时才可选 —— 别处状态不能改回已缴纳。
/// 三个入口（押金追踪页的状态选择、「退租」页的押金结算、详情页的「去纠纷」）
/// 都走这一条判断，别各写一套。
bool canSwitchDeposit(DepositStatus from, DepositStatus to) {
  if (from == to) return false;
  return switch (from) {
    // 刚交完押金：往后随便走（退租结算 / 被扣 / 退到手 / 维权都行）
    DepositStatus.paid => const {
      DepositStatus.toBeReturned,
      DepositStatus.partiallyDeducted,
      DepositStatus.returned,
      DepositStatus.inDispute,
    }.contains(to),
    // 等着退还：可以变成被扣 / 退到手，或者去维权
    DepositStatus.toBeReturned => const {
      DepositStatus.partiallyDeducted,
      DepositStatus.returned,
      DepositStatus.inDispute,
    }.contains(to),
    // 已经谈成扣款：只剩「都退回来（走维权）」两条路
    DepositStatus.partiallyDeducted =>
      to == DepositStatus.returned || to == DepositStatus.inDispute,
    // 维权中：落到谈成的两个结果上
    DepositStatus.inDispute =>
      to == DepositStatus.partiallyDeducted || to == DepositStatus.returned,
    // 已退还（流程走完）、无押金（先走「要不要押金」那一问）都不在这里改
    _ => false,
  };
}

/// 退租日：优先押金退还日期，其次最后一条「退租类」状态记录，
/// 都没有就退回合同到期日（数据不全时至少给个合理的答案）。
DateTime moveOutDate(Property property) {
  final deposit = property.deposit;
  if (deposit.returnedDate != null) return dateOnly(deposit.returnedDate!);
  for (final log in deposit.logs.reversed) {
    switch (log.status) {
      case DepositStatus.toBeReturned:
      case DepositStatus.partiallyDeducted:
      case DepositStatus.returned:
      case DepositStatus.inDispute:
        return dateOnly(log.time);
      case DepositStatus.none:
      case DepositStatus.paid:
        break;
    }
  }
  return dateOnly(property.contract.contractEnd);
}

/// 这套房一共住了多少天：入住日 → 退租日，**含首尾**
/// （8/1 入住、8/31 搬走算 31 天，和「流浪天数」同一个口径）。
int livedDays(Property property) {
  final days =
      daysBetween(dateOnly(property.contract.moveInDate), moveOutDate(property)) +
      1;
  return days > 0 ? days : 0;
}

/// 「租住回顾」要用的数字：住了多少天、租了几个月、实付房租、水电燃气，
/// 以及留下多少张取证照片。已退租的房子在详情页顶部展示。
class TenancyRecap {
  const TenancyRecap({
    required this.moveInDate,
    required this.moveOutDate,
    required this.days,
    required this.contractMonths,
    required this.paidMonths,
    required this.paidRent,
    required this.utilityCost,
    required this.utilityRecords,
    required this.photos,
    required this.moveInPhotos,
    required this.moveOutPhotos,
  });

  final DateTime moveInDate;
  final DateTime moveOutDate;

  /// 真正住了多少天（含首尾：8/1 入住、8/31 搬走算 31 天）
  final int days;

  /// 合同签了几个月
  final int contractMonths;

  /// 实际付过几期房租、一共付了多少
  final int paidMonths;
  final double paidRent;

  /// 水电燃气累计支出与抄表次数
  final double utilityCost;
  final int utilityRecords;

  /// 留下的取证照片（入住 / 退租各多少）
  final int photos;
  final int moveInPhotos;
  final int moveOutPhotos;
}

TenancyRecap buildTenancyRecap({
  required Property property,
  required List<RentRecord> rents,
  required List<UtilityRecord> utilities,
  required List<EvidencePhoto> photos,
}) {
  final moveIn = dateOnly(property.contract.moveInDate);
  final moveOut = moveOutDate(property);
  final mine = photos.where((photo) => photo.propertyId == property.id);
  // 合同租期按租金计划的期数算：它就是「一共几期房租」，
  // 比 `totalMonths` 的月份差更贴近实际（后者会少算一期）
  final planned = rents.where((rent) => rent.propertyId == property.id).length;
  return TenancyRecap(
    moveInDate: moveIn,
    moveOutDate: moveOut,
    days: livedDays(property),
    contractMonths: planned > 0 ? planned : property.contract.totalMonths,
    paidMonths: countPaidMonths(rents, property.id),
    paidRent: sumPaidRent(rents, property.id),
    utilityCost: sumUtilityCost(utilities, property.id),
    utilityRecords: utilities
        .where((record) => record.propertyId == property.id)
        .length,
    photos: mine.length,
    moveInPhotos: mine
        .where((photo) => photo.phase == PhotoPhase.moveIn)
        .length,
    moveOutPhotos: mine
        .where((photo) => photo.phase == PhotoPhase.moveOut)
        .length,
  );
}

/// 这套房到底用不用燃气：**合同里勾了「有燃气表」**；
/// 另外只要抄表记录里出现过燃气读数就算（兜住旧数据 —— 那时还没有这个开关）。
///
/// 「入住时的燃气表底数」只有用燃气的房子才需要填：家里压根没有燃气表
/// 的话，逼着用户填个数（填 0 也是假的）只会让首页那条待办永远消不掉。
/// 抄表录入那边「有没有燃气表」也用同一套判断。
bool usesGas(
  ContractInfo contract,
  List<UtilityRecord> utilities,
  String propertyId,
) =>
    contract.hasGasMeter ||
    utilities.any(
      (record) => record.propertyId == propertyId && record.gas != null,
    );

/// 入住时的表底数还缺几项：电、水必填，燃气只在这套房确实用燃气时才算
/// （见 [usesGas]）。
///
/// 首页待办和合同页的「还有 N 项待补」都用它，免得两处口径跑偏 ——
/// 曾经写死「三项齐全」的判据，结果没有燃气表的房子永远清不掉那条待办。
int missingMoveInReadings(
  ContractInfo contract,
  List<UtilityRecord> utilities,
  String propertyId,
) => [
  if (contract.moveInElectricity == null) 1,
  if (contract.moveInWater == null) 1,
  if (usesGas(contract, utilities, propertyId) && contract.moveInGas == null) 1,
].length;

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
    // 已退租 / 纠纷中的房子：资料只读、也没有「本月该交租/该抄表」了，
    // 那些提醒只会变成点进去啥也干不了的死待办；只有押金相关的继续催
    final canAct = property.status == PropertyStatus.active;

    // 「已退租」就等于这套房的流程走完了：不再催押金。
    // 押金还没退到手这件事，在房源详情页的「租住回顾」里如实写着
    // （列表里也照实显示「未退还」），不需要天天弹一条待办。
    if (config.enableDeposit && property.status == PropertyStatus.dispute) {
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

    if (canAct && config.enableRent) {
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
        // 什么时候该提醒，只看「最早那期还没付的账单」。
        //
        // ⚠️ 这里不能再拿日历上的下一个交租日（nextRentDue）算：本月账单提前
        // 付掉之后，那个日子还在未来几天内，于是「费用里已经付了、待办里还提醒
        // 该交房租」。有账期时一律按账单说话 —— 一期都没生成（刚建房源）才退回
        // 日历，免得漏提醒。
        final scheduled = rents.any((r) => r.propertyId == property.id);
        final next = unpaid.isEmpty ? null : unpaid.first;
        final due =
            next?.dueDate ??
            (scheduled
                ? null
                : nextRentDue(property.contract.rentDueDay, from: now));
        if (due != null) {
          final days = daysBetween(now, due);
          if (days <= config.rentDaysAhead) {
            list.add(
              ReminderItem(
                kind: ReminderKind.rentDue,
                // 金额优先用那一期账单上的，合同月租只当兜底
                title:
                    '该交房租了 · '
                    '${fmtMoney(next?.amount ?? property.contract.monthlyRent)}',
                subtitle:
                    '${fmtMonthDay(due)} 到期 · '
                    '${property.contract.paymentMethod}',
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
    }

    if (canAct &&
        config.enableUtility &&
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

    if (canAct &&
        config.enableContract &&
        property.contract.contractEnd.isAfter(now)) {
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

    if (canAct &&
        _countPhotos(photos, property.id, phase: PhotoPhase.moveIn) == 0) {
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

    // 入住时的表底数缺了就提醒补：抄表录入的首月用量要靠它当基准，
    // 缺了就只算得出「本月读数 − 0」这种明显不对的数。
    //
    // 几个口径：
    // - 只在租住中的房子上提醒：已退租的抄表记录已经只读归档，补了也用不上
    //   （跟 canAddUtility 一个口径）；
    // - 关掉「抄表提醒」就不再催，这条待办只服务于抄表；
    // - 燃气表底数只对**确实在用燃气**的房子要求（见 [usesGas]），
    //   不然没有燃气表的房子永远清不掉这条待办。
    //
    // 不写副标题：标题已经把「水/电表数」说全了，
    // 再补一句「还差哪几块表」纯属重复占地方。
    final contract = property.contract;
    if (config.enableUtility &&
        property.status == PropertyStatus.active &&
        missingMoveInReadings(contract, utilities, property.id) > 0) {
      list.add(
        ReminderItem(
          kind: ReminderKind.moveInReading,
          title: '补填入住时的水/电表数',
          subtitle: '',
          date: now,
          daysLeft: 0,
          propertyId: property.id,
          propertyName: property.name,
          tone: ZTone.brand,
          actionLabel: '去补填',
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

/// 「流浪天数」：所有房源真正在租的天数，**按自然日去重**。
///
/// 同时在租两套房的那些天只算一天；换租、租期有重叠也一样只算一次。
/// 在租的房子算到今天，已退租 / 纠纷的算到**退租日**（见 [moveOutDate]）；
/// 入住当天也算一天，还没到入住日（入住日在未来）的不计入。
int countWanderingDays(List<Property> properties, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  final intervals = <({DateTime start, DateTime end})>[];
  for (final property in properties) {
    final start = dateOnly(property.contract.moveInDate);
    // 退租之后按实际退租日算：提前退租时合同还挂着，
    // 拿合同到期日当结束会把搬走之后（甚至未来）的天数也算成「流浪」，
    // 数字越看越大还莫名其妙
    final ended = property.status == PropertyStatus.active
        ? today
        : moveOutDate(property);
    // 兜底：结束日不该超过今天，别把未来的天数算进来
    final end = ended.isAfter(today) ? today : ended;
    if (daysBetween(start, end) < 0) continue;
    intervals.add((start: start, end: end));
  }
  if (intervals.isEmpty) return 0;
  intervals.sort((a, b) => a.start.compareTo(b.start));

  // 把重叠 / 紧邻的租期合并成几段，再按「含首尾」数天数：
  // 8/1 入住、8/31 搬走是 31 天，而不是 30 天
  var days = 0;
  var start = intervals.first.start;
  var end = intervals.first.end;
  for (final range in intervals.skip(1)) {
    if (daysBetween(end, range.start) <= 1) {
      if (range.end.isAfter(end)) end = range.end;
      continue;
    }
    days += daysBetween(start, end) + 1;
    start = range.start;
    end = range.end;
  }
  return days + daysBetween(start, end) + 1;
}

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
