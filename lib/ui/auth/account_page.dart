import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/cloud_service.dart';
import '../../services/session.dart';
import '../../theme/tokens.dart';
import '../kit.dart';

/// 账号与同步（已登录时从「我的」进入）
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudService>();
    final session = context.watch<Session>();

    return ZScreen(
      child: Column(
        children: [
          const ZAppBar(leading: ZBackButton(), title: '账号与同步'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                ZCard(
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: Z.logoGradient,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(session.displayName, style: ZText.bodyStrong),
                            const SizedBox(height: 3),
                            Text(
                              maskPhone(session.phone),
                              style: ZText.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // 同步状态不摆在账号页上：只在真的出错时提示一次
                if (cloud.lastError != null) ...[
                  const SizedBox(height: 10),
                  ZHintBar(
                    text: cloud.lastError!,
                    tone: ZTone.danger,
                    icon: Icons.error_outline_rounded,
                  ),
                ],
                const ZSectionTitle(
                  title: '账号管理',
                  icon: Icons.manage_accounts_outlined,
                ),
                ZCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 3,
                  ),
                  child: Column(
                    children: [
                      ZListRow(
                        icon: Icons.logout_rounded,
                        title: '退出登录',
                        subtitle: '本机数据保留，只断开这个账号',
                        onTap: () => _logout(context, cloud),
                      ),
                      ZListRow(
                        icon: Icons.delete_sweep_outlined,
                        title: '清除本机数据',
                        subtitle: '删掉这台设备上的房源与照片，云端不受影响',
                        onTap: () => _clearLocal(context, cloud),
                      ),
                      ZListRow(
                        icon: Icons.delete_forever_outlined,
                        title: '注销账号',
                        subtitle: '删除云端数据与账号，不可恢复',
                        titleColor: Z.danger,
                        divider: false,
                        onTap: () => _destroy(context, cloud),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '注销会同时删除云端照片；本机这份账号数据也会一并清掉，'
                  '退出登录则只是断开账号。',
                  style: ZText.micro.copyWith(fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 138****6677
String maskPhone(String phone) {
  if (phone.length < 8) return phone;
  return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
}

/// 退出登录：只断开账号，本机数据保留
Future<void> _logout(BuildContext context, CloudService cloud) async {
  final ok = await zConfirm(
    context,
    title: '退出登录',
    message: '退出后本机数据仍然保留，云端数据不会被删除。',
    confirmText: '退出',
  );
  if (!ok || !context.mounted) return;
  await cloud.logout();
  if (!context.mounted) return;
  zToast(context, '已退出登录');
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// 清除本机数据：账号还在、云端不动，只清这台设备
Future<void> _clearLocal(BuildContext context, CloudService cloud) async {
  final ok = await zConfirm(
    context,
    title: '清除本机数据',
    message:
        '将删除这台设备上的房源、照片与记录（云端与账号不受影响）。'
        '下次同步会把云端那份拉回来，操作前建议确认云端已经同步完成。',
    confirmText: '清除',
    danger: true,
  );
  if (!ok || !context.mounted) return;
  await cloud.clearLocalData();
  if (!context.mounted) return;
  zToast(context, '本机数据已清除');
}

/// 注销账号：删除云端账号与本机这份账号数据，需要二次确认
Future<void> _destroy(BuildContext context, CloudService cloud) async {
  final phone = maskPhone(cloud.session.phone);
  final ok = await zConfirm(
    context,
    title: '注销账号',
    message: '将删除 $phone 在服务器上的租盾数据（含照片）并注销账号，操作不可恢复。',
    confirmText: '继续',
    danger: true,
  );
  if (!ok || !context.mounted) return;

  final sure = await zConfirm(
    context,
    title: '再次确认注销',
    message: '删除后无法找回，本机这份账号数据也会被清掉。确定要注销吗？',
    confirmText: '注销账号',
    danger: true,
  );
  if (!sure || !context.mounted) return;

  try {
    await cloud.destroyAccount();
  } catch (error) {
    if (context.mounted) zToast(context, '注销失败：$error');
    return;
  }
  if (!context.mounted) return;
  zToast(context, '账号已注销');
  Navigator.of(context).popUntil((route) => route.isFirst);
}
