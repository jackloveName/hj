import '../models/models.dart';

/// 系统通知的业务槽位：决定文案与去重键
enum PlanSlot { rentDue, contractExpire, utilityReading, depositReturn }

/// 一条「到点弹给用户」的系统通知
class NotificationPlan {
  const NotificationPlan({
    required this.id,
    required this.slot,
    required this.title,
    required this.body,
    required this.when,
    required this.propertyId,
    required this.propertyName,
  });

  /// 稳定 id：同一件事每次算出来都一样，重复同步不会堆一堆通知
  final int id;
  final PlanSlot slot;
  final String title;
  final String body;
  final DateTime when;
  final String propertyId;

  /// 房源名。设置页要按「哪套房 · 什么时候」把排期列出来，
  /// 页面不该去拆 [body] 拿名字，所以这里存一份
  final String propertyName;

  /// 点开通知后用来决定跳哪个页面
  String get payload => '$propertyId|${slot.name}';

  @override
  String toString() => 'NotificationPlan(#$id ${slot.name} $when)';
}

/// 稳定 id：FNV-1a 32 位，跨进程 / 跨平台一致（`hashCode` 不保证）
int notificationId(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF;
}

/// 把首页「待办提醒」翻译成「系统通知计划」。
///
/// 几个刻意的取舍：
/// - 只排未来的时刻：已经过点的提醒不再补弹，避免一开 App 就轰炸
/// - 交租：提前 N 天 + 当天各一条；已逾期则改成第二天早上提醒
/// - 合同到期：按用户勾的每个节点各排一条，外加到期当天
/// - 抄表：本月提醒日已过就排到下个月，并**预排未来一年**（长期不打开 App 也能每月收到）
/// - 交租：同样往后预排 `lookAheadMonths` 个月，避免只提醒一次
/// - 押金：退租后每天早上提醒一次（每次同步重排，所以只会有一天一条）
/// - 取证待办、入住表底数待补不进系统通知：它们没有「到点」的概念，
///   留在首页待办里，用户点进去顺手就做了
List<NotificationPlan> buildNotificationPlan({
  required List<ReminderItem> reminders,
  required ReminderSettings config,
  required DateTime now,
  int hour = 9,

  /// 往后预排多少个月（交租 / 抄表这类周期性的），0 表示只排最近一次
  int lookAheadMonths = 12,
}) {
  final plans = <NotificationPlan>[];

  /// 系统排期上限：别把几百条都塞给系统
  const maxPlans = 60;

  void add({
    required PlanSlot slot,
    required DateTime when,
    required String title,
    required String body,
    required String propertyId,
    required String propertyName,
  }) {
    if (plans.length >= maxPlans) return;
    if (!when.isAfter(now)) return;
    final id = notificationId(
      '${slot.name}|$propertyId|${when.toIso8601String()}',
    );
    if (plans.any((plan) => plan.id == id)) return;
    plans.add(
      NotificationPlan(
        id: id,
        slot: slot,
        title: title,
        body: body,
        when: when,
        propertyId: propertyId,
        propertyName: propertyName,
      ),
    );
  }

  /// 当天 hour 点（不会踩到夏令时那种「这天少一小时」的坑）
  DateTime atHour(DateTime day, int hour) =>
      DateTime(day.year, day.month, day.day, hour);

  /// 往前挪 N 天（日期运算，跨月跨年都对）
  DateTime daysBefore(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day - days, hour);

  for (final reminder in reminders) {
    switch (reminder.kind) {
      case ReminderKind.rentDue:
        if (reminder.daysLeft < 0) {
          // 已经逾期：第二天早上再提醒一次
          final tomorrow = atHour(now, hour);
          add(
            slot: PlanSlot.rentDue,
            when: tomorrow.isAfter(now)
                ? tomorrow
                : atHour(now.add(const Duration(days: 1)), hour),
            title: '房租还没交',
            body: '${reminder.propertyName} · ${reminder.subtitle}',
            propertyId: reminder.propertyId,
            propertyName: reminder.propertyName,
          );
          break;
        }
        final due = reminder.date;
        final until = reminder.until;
        // 每个月都排「提前 N 天 + 当天」，直到合同到期或排满预排月份
        for (var i = 0; i <= lookAheadMonths; i++) {
          final monthDue = DateTime(due.year, due.month + i, due.day);
          if (until != null && monthDue.isAfter(until)) break;
          add(
            slot: PlanSlot.rentDue,
            when: daysBefore(monthDue, config.rentDaysAhead),
            title: '该交房租了',
            body: '${reminder.propertyName} · ${reminder.subtitle}',
            propertyId: reminder.propertyId,
            propertyName: reminder.propertyName,
          );
          add(
            slot: PlanSlot.rentDue,
            when: atHour(monthDue, hour),
            title: '今天该交房租了',
            body: '${reminder.propertyName} · ${reminder.subtitle}',
            propertyId: reminder.propertyId,
            propertyName: reminder.propertyName,
          );
        }
      case ReminderKind.contractExpire:
        final end = reminder.date;
        for (final days in config.contractDaysAhead.toSet().toList()..sort()) {
          add(
            slot: PlanSlot.contractExpire,
            when: daysBefore(end, days),
            title: '合同还有 $days 天到期',
            body: '${reminder.propertyName} · 记得决定续租还是搬家',
            propertyId: reminder.propertyId,
            propertyName: reminder.propertyName,
          );
        }
        add(
          slot: PlanSlot.contractExpire,
          when: atHour(end, hour),
          title: '合同今天到期',
          body: '${reminder.propertyName} · 退租记得现场对照片、要押金',
          propertyId: reminder.propertyId,
          propertyName: reminder.propertyName,
        );
      case ReminderKind.utilityReading:
        // 从「本月提醒日」开始预排一整年；已经过去的月份自然会被 add() 丢掉
        for (var i = 0; i <= lookAheadMonths; i++) {
          add(
            slot: PlanSlot.utilityReading,
            when: DateTime(
              reminder.date.year,
              reminder.date.month + i,
              config.utilityDay,
              hour,
            ),
            title: '该抄水电表了',
            body: '${reminder.propertyName} · 每月记一次，退租结算才说得清',
            propertyId: reminder.propertyId,
            propertyName: reminder.propertyName,
          );
        }
      case ReminderKind.depositReturn:
        final tomorrow = atHour(now, hour);
        add(
          slot: PlanSlot.depositReturn,
          when: tomorrow.isAfter(now)
              ? tomorrow
              : atHour(now.add(const Duration(days: 1)), hour),
          title: reminder.title,
          body: '${reminder.propertyName} · ${reminder.subtitle}',
          propertyId: reminder.propertyId,
          propertyName: reminder.propertyName,
        );
      case ReminderKind.photoMissing:
        // 没有「到点」语义，留在首页待办
        break;
      case ReminderKind.moveInReading:
        // 同上：填个表底数没有「什么时候该填」，
        // 排成系统通知只会变成一条催命符，留在首页待办里就行
        break;
    }
  }

  plans.sort((a, b) => a.when.compareTo(b.when));
  return plans;
}
