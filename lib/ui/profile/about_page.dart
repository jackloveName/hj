import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../content/legal.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../services/cloud_service.dart';
import '../../services/error_log.dart';
import '../../services/session.dart';
import '../../theme/tokens.dart';
import '../auth/account_page.dart';
import '../auth/login_page.dart';
import '../kit.dart';
import 'error_log_page.dart';
import 'profile_page.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final cloud = context.watch<CloudService>();
    final session = context.watch<Session>();
    final settings = repository.settings;
    // 错误日志可能没接（测试环境），用 read 不当依赖
    final errorCount = context.read<ErrorLog?>()?.entries.length ?? 0;

    return ZScreen(
      child: Column(
        children: [
          // 从「我的」右上角齿轮进来，页内就是各项设置
          const ZAppBar(title: '设置', leading: ZBackButton()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: Z.heroGradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: Z.e2,
                      ),
                      child: const Icon(
                        Icons.verified_user_rounded,
                        size: 30,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('租盾', style: ZText.title1.copyWith(fontSize: 20)),
                    const SizedBox(height: 4),
                    Text(
                      '从入住到退租，全程守护你的押金',
                      style: ZText.caption.copyWith(fontSize: 13),
                    ),
                  ],
                ),
                const ZSectionTitle(title: '常规', icon: Icons.tune_rounded),
                ZCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 3,
                  ),
                  child: Column(
                    children: [
                      ZListRow(
                        icon: Icons.person_outline_rounded,
                        // 编辑资料统一收到「设置」里：头像 / 用户名 / 生日都在弹层里改
                        title: '编辑资料',
                        subtitle: session.loggedIn
                            ? '头像 · 用户名 · 生日'
                            : '登录后可编辑头像、用户名与生日',
                        onTap: () => ProfilePage.showEditProfileSheet(
                          context,
                          repository: repository,
                          session: session,
                          cloud: cloud,
                        ),
                      ),
                      ZListRow(
                        icon: Icons.dark_mode_outlined,
                        title: '外观',
                        trailing: Text(
                          settings.appearance.label,
                          style: ZText.label.copyWith(
                            fontSize: 13,
                            color: Z.ink2,
                          ),
                        ),
                        onTap: () => _pickAppearance(context, repository),
                      ),
                      ZListRow(
                        icon: Icons.cloud_sync_outlined,
                        title: session.loggedIn ? '账号与同步' : '登录 / 注册',
                        subtitle: session.loggedIn
                            ? '${session.displayName} · ${cloud.statusLabel}'
                            : '登录后可在多设备之间同步数据',
                        onTap: () => zPush(
                          context,
                          session.loggedIn
                              ? const AccountPage()
                              : const LoginPage(),
                        ),
                      ),
                      ZListRow(
                        icon: Icons.bug_report_outlined,
                        title: '错误日志',
                        subtitle: errorCount == 0
                            ? 'App 出问题时可以在这里复制日志'
                            : '有 $errorCount 条记录，可复制发给客服',
                        divider: false,
                        onTap: () => zPush(context, const ErrorLogPage()),
                      ),
                    ],
                  ),
                ),
                const ZSectionTitle(title: '免责声明', icon: Icons.gavel_outlined),
                ZCard(
                  child: Text(
                    '$legalDisclaimer\n\n'
                    '本 App 生成的报告与文书为自助工具，仅供参考；'
                    '取证照片的证明力最终由争议处理机构认定。',
                    style: ZText.body.copyWith(fontSize: 13, height: 1.8),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    '让每一次租房，都不被坑。',
                    style: TextStyle(
                      fontFamily: Z.font,
                      fontFamilyFallback: Z.fallback,
                      fontSize: 12,
                      color: Z.ink4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 外观：跟随系统 / 浅色 / 深色
  Future<void> _pickAppearance(
    BuildContext context,
    Repository repository,
  ) async {
    final current = repository.settings.appearance;
    final picked = await showModalBottomSheet<AppAppearance>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('外观', style: ZText.title3.copyWith(fontSize: 15)),
            ),
            for (final option in AppAppearance.values)
              ListTile(
                title: Text(option.label, style: ZText.body),
                trailing: option == current
                    ? const Icon(Icons.check_rounded, size: 18, color: Z.brand)
                    : null,
                onTap: () => Navigator.of(ctx).pop(option),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;
    if (!context.mounted) return;
    await repository.updateSettings(
      repository.settings.copyWith(appearance: picked),
    );
  }
}
