import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../services/notification_service.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';

/// 页面 22 · 提醒设置
class ReminderSettingsPage extends StatelessWidget {
  const ReminderSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final notifications = context.watch<NotificationService>();
    final settings = repository.settings;
    final reminders = settings.reminders;

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
                const ZHintBar(text: '提醒会在首页「待办提醒」中按设置展示。所有计算都在本机完成，不需要联网。'),
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
                          '提醒到点弹到系统通知栏',
                          style: ZText.label.copyWith(fontSize: 14),
                        ),
                        subtitle: Text(
                          _systemStatusText(notifications),
                          style: ZText.small,
                        ),
                      ),
                      if (settings.systemNotifications) ...[
                        Divider(height: 18, color: Z.line2),
                        for (final plan in notifications.plans.take(3))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 76,
                                  child: Text(
                                    fmtMonthDay(plan.when),
                                    style: ZText.mono.copyWith(
                                      fontSize: 12,
                                      color: Z.ink3,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    plan.title,
                                    style: ZText.small.copyWith(
                                      fontSize: 12,
                                      color: Z.ink2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (notifications.plans.isEmpty)
                          Text(
                            '现在没有要提醒的事，等有了会自动排期',
                            style: ZText.small.copyWith(fontSize: 12),
                          ),
                        const SizedBox(height: 4),
                        TextButton.icon(
                          // 环境不支持时也让人点：点了会说清楚为什么没弹。
                          // 灰着不给原因，最容易让人以为「这按钮点了没用」。
                          onPressed: () async {
                            final message = await notifications.showTest();
                            if (context.mounted) zToast(context, message);
                          },
                          icon: const Icon(
                            Icons.notifications_none_rounded,
                            size: 18,
                          ),
                          label: const Text('发一条测试通知'),
                        ),
                        // 系统没授权时给一个直达入口，不用自己去翻设置
                        if (notifications.permission ==
                            NotificationPermission.denied)
                          TextButton.icon(
                            onPressed: notifications.openSystemSettings,
                            icon: const Icon(Icons.settings_outlined, size: 18),
                            label: const Text('去系统设置打开通知'),
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
                  title: '押金退还提醒',
                  icon: Icons.savings_outlined,
                ),
                ZCard(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: reminders.enableDeposit,
                    onChanged: (value) =>
                        update(reminders.copyWith(enableDeposit: value)),
                    title: Text(
                      '退租后持续提醒催要押金',
                      style: ZText.label.copyWith(fontSize: 14),
                    ),
                    subtitle: Text('避免忘记要回押金', style: ZText.small),
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
                const SizedBox(height: 8),
                Text(
                  '系统通知只在到点时推送「交租、合同到期、抄表、押金退还」四类；'
                  '取证待办这类没有到点概念的事项，仍然只出现在首页待办里。',
                  style: ZText.small.copyWith(fontSize: 11.5, height: 1.6),
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
        zToast(context, '当前环境不支持系统通知，仅保留应用内提醒');
        return;
      case NotificationPermission.granted:
      case NotificationPermission.unknown:
        break;
    }
    await repository.updateSettings(
      repository.settings.copyWith(systemNotifications: true),
    );
    await notifications.showTest();
  }

  /// 开关下面那行状态说明
  String _systemStatusText(NotificationService notifications) {
    if (!notifications.available) {
      return notifications.isWeb
          ? '当前浏览器不支持系统通知，提醒只显示在应用内'
          : '当前平台暂不支持系统通知，提醒只显示在应用内';
    }
    if (!notifications.enabled) {
      return notifications.supportsScheduling
          ? '开启后，到点会弹到系统通知栏（App 没打开也能响）'
          : '开启后，页面开着时到点弹通知（浏览器不支持关掉页面后提醒）';
    }
    if (notifications.permission == NotificationPermission.denied) {
      return '系统未授权：请到系统设置里允许租盾发送通知';
    }
    final count = notifications.plans.length;
    if (count == 0) return '已开启，当前没有需要提醒的事项';
    return '已开启，接下来有 $count 条提醒';
  }
}
