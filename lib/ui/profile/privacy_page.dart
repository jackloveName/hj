import 'package:flutter/material.dart';

import '../../services/protocol_service.dart';
import '../../theme/tokens.dart';
import '../kit.dart';
import '../legal_sheets.dart';

/// 隐私政策和平台注册协议：只留两份协议的入口。
/// 备份、账号同步、注销这些操作都在「设置 / 账号与同步」里，这里不重复摆。
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ZScreen(
      child: Column(
        children: [
          const ZAppBar(
            leading: ZBackButton(),
            title: '隐私政策和平台注册协议',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                const ZSectionTitle(
                  title: '协议全文',
                  icon: Icons.privacy_tip_outlined,
                ),
                ZCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 3,
                  ),
                  child: Column(
                    children: [
                      ZListRow(
                        icon: Icons.privacy_tip_outlined,
                        title: '隐私政策',
                        subtitle: '我们收集哪些信息、怎么用、存多久',
                        onTap: () =>
                            showProtocolSheet(context, ProtocolKind.privacy),
                      ),
                      ZListRow(
                        icon: Icons.description_outlined,
                        title: '平台注册协议',
                        subtitle: '账号注册、数据归属与服务约定',
                        divider: false,
                        onTap: () =>
                            showProtocolSheet(context, ProtocolKind.agreement),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '协议正文由平台下发，更新后这里会同步显示最新版本。',
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
