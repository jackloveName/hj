import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../services/notification_service.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';
import '../reminder_actions.dart';

/// 设置页只预览最近几条排期：排期动辄几十条（交租 / 抄表要往后排一年），
/// 全摆出来反而看不清「接下来要响的是哪几件」
const int _planPreviewCount = 3;

/// 页面 22 · 提醒设置
class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({super.key});

  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage> {
  @override
  void initState() {
    super.initState();
    // 进页面就核对一次系统授权并重排：开关是历史设置，
    // 授权可能被系统收回（iOS 上没授权时排期会被静默丢弃）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifications = context.read<NotificationService>();
      unawaited(notifications.refreshPermission());
      if (notifications.enabled) unawaited(notifications.sync());
    });
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final notifications = context.watch<NotificationService>();
    final settings = repository.settings;
    final reminders = settings.reminders;

    final upcoming = notifications.plans.take(_planPreviewCount).toList();
    // 开关下面那行只在「需要用户做点什么」时才写
    final status = _systemStatusText(notifications);

    Future<void> update(ReminderSettings value) =>
        repository.updateSettings(settings.copyWith(reminders: value));

    return ZScreen(
      child: Column(
        children: [
          const ZAppBar(title: '提醒设置', leading: ZBackButton()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                const ZSectionTitle(
                  title: '系统通知',
                  icon: Icons.notifications_active_outlined,
                ),
                ZCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: settings.systemNotifications,
                        onChanged: (value) async {
                          if (!value) {
                            await repository.updateSettings(
                              settings.copyWith(systemNotifications: false),
                            );
                            return;
                          }
                          await _turnOnSystemNotifications(
                            context,
                            repository,
                            notifications,
                          );
                        },
                        title: Text(
                          '系统通知',
                          style: ZText.label.copyWith(fontSize: 14),
                        ),
                        // 一切正常就不写这行：下面的排期清单已经把「接下来排了
                        // 哪些」说清楚了，再报一遍条数只是重复
                        subtitle: status == null
                            ? null
                            : Text(status, style: ZText.small),
                      ),
                      // 不支持时给一个「复制原因」：真机上出问题直接复制发出来，
                      // 比让人照着屏幕念错误信息靠谱
                      if (!notifications.available &&
                          notifications.lastError != null)
                        TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: notifications.lastError ?? '',
                              ),
                            );
                            if (context.mounted) zToast(context, '原因已复制');
                          },
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('复制原因'),
                        ),
                      if (settings.systemNotifications) ...[
                        Divider(height: 18, color: Z.line2),
                        if (notifications.plans.isEmpty)
                          Text(
                            '现在没有要提醒的事，等有了会自动排期',
                            style: ZText.caption.copyWith(height: 1.5),
                          )
                        else ...[
                          // 列头把「这是什么、一共几条」说清楚：以前只摆 3 行
                          // 「日期 + 标题」，既看不出还剩多少，也看不出几点响
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '接下来要提醒的',
                                  style: ZText.micro.copyWith(color: Z.ink3),
                                ),
                              ),
                              Text(
                                '共 ${notifications.plans.length} 条',
                                style: ZText.monoSmall,
                              ),
                            ],
                          ),
                          for (var i = 0; i < upcoming.length; i++)
                            _PlanRow(
                              plan: upcoming[i],
                              divider: i != upcoming.length - 1,
                            ),
                          if (notifications.plans.length > upcoming.length)
                            Text(
                              '只列最近 ${upcoming.length} 条',
                              style: ZText.small.copyWith(fontSize: 11),
                            ),
                        ],
                        const SizedBox(height: 4),
                        // 开关是历史设置，系统授权却可能从没给过或被收回
                        // （iOS 上没授权时排期会被静默丢弃）——这里把「重新授权」
                        // 摆出来，授权成功立刻重排一次
                        if (notifications.permission !=
                            NotificationPermission.granted)
                          TextButton.icon(
                            onPressed: () async {
                              final permission = await notifications
                                  .requestPermission();
                              if (!context.mounted) return;
                              if (permission !=
                                  NotificationPermission.granted) {
                                zToast(context, '还没拿到授权，请到系统设置里打开通知');
                                return;
                              }
                              await notifications.sync();
                              if (context.mounted) {
                                zToast(context, '已授权，提醒重新排好了');
                              }
                            },
                            icon: const Icon(
                              Icons.notifications_active_outlined,
                              size: 18,
                            ),
                            label: const Text('授权系统通知'),
                          ),
                        // 系统没授权时给一个直达入口，不用自己去翻设置
                        if (notifications.permission ==
                            NotificationPermission.denied)
                          TextButton.icon(
                            onPressed: notifications.openSystemSettings,
                            icon: const Icon(Icons.settings_outlined, size: 18),
                            label: const Text('去系统设置打开通知'),
                          ),
                        // 排期失败 / 系统没接下这次排期，直接把原因摆出来，
                        // 别让「点了没反应」变成一个查不出来的谜
                        if (notifications.lastError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              notifications.lastError!,
                              style: ZText.small.copyWith(
                                fontSize: 11.5,
                                height: 1.5,
                                color: Z.danger,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                const ZSectionTitle(
                  title: '交租提醒',
                  icon: Icons.payments_outlined,
                ),
                ZCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: reminders.enableRent,
                        onChanged: (value) =>
                            update(reminders.copyWith(enableRent: value)),
                        title: Text(
                          '开启交租提醒',
                          style: ZText.label.copyWith(fontSize: 14),
                        ),
                        subtitle: Text('在交租日前提醒你准备租金', style: ZText.small),
                      ),
                      if (reminders.enableRent) ...[
                        Divider(height: 18, color: Z.line2),
                        Text(
                          '提前多少天提醒',
                          style: ZText.label.copyWith(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final days in [1, 3, 5, 7])
                              ChoiceChip(
                                label: Text('$days 天'),
                                selected: reminders.rentDaysAhead == days,
                                onSelected: (_) => update(
                                  reminders.copyWith(rentDaysAhead: days),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const ZSectionTitle(
                  title: '合同到期提醒',
                  icon: Icons.event_note_outlined,
                ),
                ZCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: reminders.enableContract,
                        onChanged: (value) =>
                            update(reminders.copyWith(enableContract: value)),
                        title: Text(
                          '开启到期提醒',
                          style: ZText.label.copyWith(fontSize: 14),
                        ),
                        subtitle: Text('到期前提醒续租或搬家', style: ZText.small),
                      ),
                      if (reminders.enableContract) ...[
                        Divider(height: 18, color: Z.line2),
                        Text(
                          '提醒节点',
                          style: ZText.label.copyWith(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final days in [60, 30, 15, 7, 3])
                              FilterChip(
                                label: Text('提前 $days 天'),
                                selected: reminders.contractDaysAhead.contains(
                                  days,
                                ),
                                onSelected: (selected) {
                                  final list = [...reminders.contractDaysAhead];
                                  if (selected) {
                                    list.add(days);
                                  } else {
                                    list.remove(days);
                                  }
                                  update(
                                    reminders.copyWith(
                                      contractDaysAhead: list..sort(),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const ZSectionTitle(title: '抄表提醒', icon: Icons.bolt_outlined),
                ZCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: reminders.enableUtility,
                        onChanged: (value) =>
                            update(reminders.copyWith(enableUtility: value)),
                        title: Text(
                          '开启抄表提醒',
                          style: ZText.label.copyWith(fontSize: 14),
                        ),
                        subtitle: Text('每月提醒记录水电表读数', style: ZText.small),
                      ),
                      if (reminders.enableUtility) ...[
                        Divider(height: 18, color: Z.line2),
                        Text(
                          '每月几号提醒',
                          style: ZText.label.copyWith(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final day in [1, 5, 10, 15, 20])
                              ChoiceChip(
                                label: Text('$day 号'),
                                selected: reminders.utilityDay == day,
                                onSelected: (_) =>
                                    update(reminders.copyWith(utilityDay: day)),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const ZSectionTitle(
                  title: '押金纠纷提醒',
                  icon: Icons.savings_outlined,
                ),
                ZCard(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: reminders.enableDeposit,
                    onChanged: (value) =>
                        update(reminders.copyWith(enableDeposit: value)),
                    title: Text(
                      '押金谈不拢时提醒去维权',
                      style: ZText.label.copyWith(fontSize: 14),
                    ),
                    subtitle: Text(
                      '退租本身算流程走完，不再催押金；'
                      '只有标记了纠纷才每天提醒',
                      style: ZText.small,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () async {
                    await repository.updateSettings(
                      settings.copyWith(reminders: const ReminderSettings()),
                    );
                    if (context.mounted) zToast(context, '已恢复默认设置');
                  },
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('恢复默认设置'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 打开系统通知：先要授权，再落设置，最后立刻弹一条让用户确认确实通了
  Future<void> _turnOnSystemNotifications(
    BuildContext context,
    Repository repository,
    NotificationService notifications,
  ) async {
    final permission = await notifications.requestPermission();
    if (!context.mounted) return;
    switch (permission) {
      case NotificationPermission.denied:
        zToast(context, '系统还没允许通知，请在系统设置里打开后重试');
        return;
      case NotificationPermission.unsupported:
        zToast(
          context,
          '当前环境不支持系统通知，仅保留应用内提醒'
          '${notifications.lastError == null ? '' : '（原因：${notifications.lastError}）'}',
        );
        return;
      case NotificationPermission.granted:
      case NotificationPermission.unknown:
        break;
    }
    await repository.updateSettings(
      repository.settings.copyWith(systemNotifications: true),
    );
    // 顺手发一条，让用户当场看到通知真的能弹；发不出去的原因由设置项
    // 下面的状态行负责说，这里不再叠提示
    await notifications.showTest();
  }

  /// 开关下面那行状态说明。
  ///
  /// 只在「需要用户做点什么」时才有内容，一切正常就返回 null ——
  /// 排得好好的时候报一句「已排好 N 条」只是重复，清单里本来就看得见。
  String? _systemStatusText(NotificationService notifications) {
    if (!notifications.available) {
      final base = notifications.isWeb
          ? '当前浏览器不支持系统通知，提醒只显示在应用内'
          : '当前平台暂不支持系统通知，提醒只显示在应用内';
      // 把底层原因摆出来：光说「不支持」没法查，真机上就没法判断是插件没接上
      // 还是系统没授权
      final reason = notifications.lastError;
      return reason == null ? base : '$base（原因：$reason）';
    }
    if (!notifications.enabled) {
      return notifications.supportsScheduling
          ? '开启后，到点会弹到系统通知栏（App 没打开也能响）'
          : '开启后，页面开着时到点弹通知（浏览器不支持关掉页面后提醒）';
    }
    if (notifications.permission == NotificationPermission.denied) {
      return '系统未授权：点下面的「授权系统通知」，或到系统设置里允许租盾发送通知';
    }
    // 有计划、系统却一条都没接下（iOS 没授权时会被静默丢弃）：
    // 这种情况必须说清楚，否则页面上看着「开了」，实际一条都不会响
    if (notifications.plans.isNotEmpty && notifications.queuedCount == 0) {
      return '已开启，但系统一条排期都没接下：看下面的原因';
    }
    return null;
  }
}

/// 「几天之内算快到了」：跟交租提醒的默认提前天数（3 天）对齐
const int _planSoonDays = 3;

/// 一条排期：类型图标 + 「哪套房 · 什么时候」+ 右边一枚「还有 N 天」。
///
/// 这行说的是「系统什么时候会响」（排期本身），跟首页待办说的
/// 「现在该做什么」是两件事，所以文案各写各的，不复用待办的标题。
class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan, required this.divider});

  final NotificationPlan plan;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final days = daysFromToday(plan.when);
    // 近的用琥珀色顶出来（「就是今天」「明天」），远的保持中性不抢眼
    final (bg, fg) = ZTag.paletteOf(
      days <= _planSoonDays ? ZTone.warn : ZTone.neutral,
    );
    return ZListRow(
      title: plan.title,
      subtitle:
          '${plan.propertyName} · ${fmtMonthDay(plan.when)} '
          '${weekdayCn(plan.when)} ${fmtTime(plan.when)}',
      iconTile: _PlanIcon(slot: plan.slot),
      trailing: ZPill(label: relativeDays(days), background: bg, foreground: fg),
      divider: divider,
    );
  }
}

/// 提醒类型的图标块：形状与配色沿用首页待办卡那一套，两页对得上号
class _PlanIcon extends StatelessWidget {
  const _PlanIcon({required this.slot});

  final PlanSlot slot;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = ZTag.paletteOf(_slotTone(slot));
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(_slotIcon(slot), size: 16, color: fg),
    );
  }
}

/// 图标直接借首页待办那一套（同一个 [reminderIcon]），免得两处各画一份
IconData _slotIcon(PlanSlot slot) => reminderIcon(switch (slot) {
  PlanSlot.rentDue => ReminderKind.rentDue,
  PlanSlot.contractExpire => ReminderKind.contractExpire,
  PlanSlot.utilityReading => ReminderKind.utilityReading,
  PlanSlot.depositReturn => ReminderKind.depositReturn,
});

/// 槽位配色：钱（交租 / 押金）琥珀、日期（合同）紫、抄表蓝
ZTone _slotTone(PlanSlot slot) => switch (slot) {
  PlanSlot.rentDue || PlanSlot.depositReturn => ZTone.warn,
  PlanSlot.contractExpire => ZTone.violet,
  PlanSlot.utilityReading => ZTone.brand,
};
