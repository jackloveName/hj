import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../content/legal.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../services/cloud_service.dart';
import '../../services/session.dart';
import '../../theme/tokens.dart';
import '../auth/account_actions.dart';
import '../auth/login_page.dart';
import '../kit.dart';
import 'profile_page.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final cloud = context.watch<CloudService>();
    final session = context.watch<Session>();
    final settings = repository.settings;
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
                      // 「账号与同步」页已并进设置：登录后这里直接是退出登录 / 注销账号
                      if (session.loggedIn) ...[
                        ZListRow(
                          icon: Icons.logout_rounded,
                          title: '退出登录',
                          onTap: () => logoutAccount(context, cloud),
                        ),
                        ZListRow(
                          icon: Icons.person_off_outlined,
                          title: '注销账号',
                          titleColor: Z.danger,
                          // 卡片里最后一行：下面不再画分隔线
                          divider: false,
                          onTap: () => destroyAccount(context, cloud),
                        ),
                      ] else
                        ZListRow(
                          icon: Icons.cloud_sync_outlined,
                          title: '登录 / 注册',
                          divider: false,
                          onTap: () => zPush(context, const LoginPage()),
                        ),
                      const SizedBox(height: 3),
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
