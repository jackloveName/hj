import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update.dart';
import '../theme/tokens.dart';
import 'kit.dart';

/// 版本更新弹窗：可关闭（强制更新除外），下载地址可复制
class AppUpdateDialog extends StatelessWidget {
  const AppUpdateDialog({
    super.key,
    required this.info,
    required this.currentVersion,
  });

  final AppUpdateInfo info;
  final String currentVersion;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('发现新版本 v${info.version}', style: ZText.title3),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('当前版本 v$currentVersion', style: ZText.caption),
          if (info.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              info.notes,
              style: ZText.body.copyWith(fontSize: 13, height: 1.6),
            ),
          ],
        ],
      ),
      actions: [
        // 锁死用户的前提是「点得到立即更新」；没有下载地址时必须留退路
        if (!info.blocking)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('稍后再说', style: TextStyle(color: Z.ink3)),
          ),
        if (info.url.isNotEmpty)
          FilledButton(
            onPressed: () => _open(context),
            child: const Text('立即更新'),
          ),
      ],
    );
  }

  /// 优先用系统浏览器 / 应用商店打开；打不开就退回复制地址，不让用户卡住
  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(info.url);
    var launched = false;
    if (uri != null) {
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        launched = false;
      }
    }
    if (!context.mounted) return;
    if (launched) {
      Navigator.of(context).pop();
      return;
    }
    await Clipboard.setData(ClipboardData(text: info.url));
    if (!context.mounted) return;
    Navigator.of(context).pop();
    zToast(context, '下载地址已复制，可粘贴到浏览器打开');
  }
}

/// 弹一次升级框。调用方负责判断「确实有更高版本」，
/// 所以这里只管展示与「立即更新 / 稍后再说」的交互。
Future<void> showAppUpdateDialog({
  required BuildContext context,
  required AppUpdateInfo info,
  required String currentVersion,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: !info.blocking,
    builder: (_) => AppUpdateDialog(info: info, currentVersion: currentVersion),
  );
}
