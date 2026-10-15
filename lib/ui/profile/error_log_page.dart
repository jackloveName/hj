import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/error_log.dart';
import '../../theme/tokens.dart';
import '../kit.dart';

/// 错误日志：把本机记录到的异常列出来，方便复制发给开发定位
class ErrorLogPage extends StatelessWidget {
  const ErrorLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final log = context.watch<ErrorLog>()..load();

    return ZScreen(
      child: Column(
        children: [
          ZAppBar(
            leading: const ZBackButton(),
            title: '错误日志',
            actions: [
              if (!log.isEmpty)
                ZIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: '清空',
                  color: Z.ink,
                  onTap: () => _clear(context, log),
                ),
            ],
          ),
          Expanded(
            child: log.isEmpty
                ? const ZEmpty(
                    icon: Icons.verified_outlined,
                    title: '没有错误记录',
                    message: 'App 运行中遇到的异常会记在这里，\n遇到问题时可以复制发给客服。',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      const ZHintBar(
                        text: '日志只存在这台设备上，不会自动上传；遇到问题点右上角复制发给客服即可。',
                        icon: Icons.privacy_tip_outlined,
                      ),
                      const SizedBox(height: 10),
                      for (final entry in log.entries)
                        ZCard(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.time
                                    .toIso8601String()
                                    .replaceFirst('T', ' ')
                                    .split('.')
                                    .first,
                                style: ZText.monoSmall.copyWith(
                                  fontSize: 11.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                entry.message,
                                style: ZText.body.copyWith(
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                              if (entry.detail.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  entry.detail,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: ZText.monoSmall.copyWith(
                                    fontSize: 11,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          if (!log.isEmpty)
            ZBottomBar(
              child: ZButton(
                label: '复制全部日志',
                icon: Icons.copy_all_outlined,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: log.text));
                  if (context.mounted) zToast(context, '已复制，粘贴发给客服即可');
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _clear(BuildContext context, ErrorLog log) async {
    final ok = await zConfirm(
      context,
      title: '清空错误日志',
      message: '清空后无法恢复，建议先复制一份再清空。',
      confirmText: '清空',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    await log.clear();
    if (context.mounted) zToast(context, '已清空');
  }
}
