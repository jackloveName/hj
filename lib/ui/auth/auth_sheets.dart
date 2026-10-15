import 'package:flutter/material.dart';

import '../../services/api/api_settings.dart';
import '../../services/cloud_service.dart';
import '../../theme/tokens.dart';
import '../kit.dart';

/// 服务器地址设置：默认使用平台网关，可改后立即生效
Future<void> showServerAddressDialog(
  BuildContext context, {
  required ApiSettings settings,
  required CloudService cloud,
}) async {
  final controller = TextEditingController(text: settings.baseUrl);
  final value = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('服务器地址'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '网关地址',
              hintText: ApiSettings.defaultBaseUrl,
            ),
          ),
          const SizedBox(height: 8),
          Text('留空或填写错误会回到默认网关。', style: ZText.caption),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop('reset'),
          child: Text('恢复默认', style: TextStyle(color: Z.ink3)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('取消', style: TextStyle(color: Z.ink3)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (value == null || !context.mounted) return;

  if (value == 'reset') {
    await settings.setBaseUrl(ApiSettings.defaultBaseUrl);
  } else {
    await settings.setBaseUrl(value);
  }
  cloud.api.baseUrl = settings.baseUrl;
  if (context.mounted) zToast(context, '服务器地址已更新：${settings.baseUrl}');
}
