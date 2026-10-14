import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../services/protocol_service.dart';
import '../theme/tokens.dart';
import 'kit.dart';
import 'legal_sheets.dart';

/// 本机记下「已同意的协议版本」的键。
/// 版本号见 [zudunProtocolVersion]：协议有实质更新时 +1，下次启动会重新征询。
const String kPrivacyConsentKey = 'zudun.privacy.agreedVersion';

/// 首次启动（或协议版本更新后）先征询同意。
///
/// 对齐安卓应用市场的合规要求，和 uni-app 的 `androidPrivacy.json` 一个路子：
/// - 「同意并接受」→ 记下同意的版本，正常进入；
/// - 「暂不同意」→ 二次确认；再不同意就退出应用（安卓可退，
///   Web / iOS 不允许程序自己退出，就停在提示上，下次启动继续征询）。
Future<void> ensurePrivacyConsent(BuildContext context) async {
  final store = context.read<Repository>().store;
  if (store.getString(kPrivacyConsentKey) == zudunProtocolVersion) return;
  if (!context.mounted) return;

  final agreed = await _showConsentDialog(context);
  if (!agreed) return;
  await store.setString(kPrivacyConsentKey, zudunProtocolVersion);
}

/// 弹「服务协议和隐私政策」；返回是否最终同意
Future<bool> _showConsentDialog(BuildContext context) async {
  final accept = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ConsentDialog(),
  );
  if (accept == true) return true;
  if (!context.mounted) return false;

  // 暂不同意 → 二次确认：不同意就退出应用
  final again = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _SecondConfirmDialog(),
  );
  if (again == true) return true;

  if (context.mounted) _quitApp(context);
  return false;
}

/// 能退就退（安卓）；Web / iOS 静默退出不礼貌也不允许，给个提示就好
void _quitApp(BuildContext context) {
  if (!kIsWeb && Platform.isAndroid) {
    SystemNavigator.pop();
    return;
  }
  zToast(context, '同意后才能继续使用，下次打开会再问你一次');
}

/// 可点击的《隐私政策》/《平台注册协议》
Widget _protocolLink(
  BuildContext context,
  String label,
  ProtocolKind kind,
  TextStyle style,
) => InkWell(
  onTap: () => showProtocolSheet(context, kind),
  child: Text(label, style: style.copyWith(color: Z.brand)),
);

class _ConsentDialog extends StatelessWidget {
  const _ConsentDialog();

  @override
  Widget build(BuildContext context) {
    final body = ZText.body.copyWith(fontSize: 13, height: 1.8);
    return AlertDialog(
      title: const Text('服务协议和隐私政策'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '　　请你务必审慎阅读、充分理解以下条款。为了向你提供服务，'
              '我们需要在你拍摄取证照片时使用相机与相册，'
              '并把房源、合同与费用记录保存在你的设备或云端账号中。',
              style: body,
            ),
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('　　你可阅读', style: body),
                _protocolLink(context, '《隐私政策》', ProtocolKind.privacy, body),
                Text('和', style: body),
                _protocolLink(
                  context,
                  '《平台注册协议》',
                  ProtocolKind.agreement,
                  body,
                ),
                Text('了解详细信息。如果你同意，请点击下面按钮开始接受我们的服务。', style: body),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('暂不同意', style: ZText.label.copyWith(color: Z.ink3)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('同意并接受'),
        ),
      ],
    );
  }
}

class _SecondConfirmDialog extends StatelessWidget {
  const _SecondConfirmDialog();

  @override
  Widget build(BuildContext context) {
    final body = ZText.body.copyWith(fontSize: 13, height: 1.8);
    return AlertDialog(
      title: const Text('确认提示'),
      content: SingleChildScrollView(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('　　进入应用前，你需先同意', style: body),
            _protocolLink(context, '《隐私政策》', ProtocolKind.privacy, body),
            Text('和', style: body),
            _protocolLink(context, '《平台注册协议》', ProtocolKind.agreement, body),
            Text('，否则将退出应用。', style: body),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('退出应用', style: ZText.label.copyWith(color: Z.ink3)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('同意并继续'),
        ),
      ],
    );
  }
}
