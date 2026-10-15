import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/cloud_service.dart';
import '../services/protocol_service.dart';
import '../theme/tokens.dart';
import 'kit.dart';

/// 协议弹层：正文只从服务端取（`ZD_PRIVACY_PROTOC` / `ZD_REGISTER_PROTOC`），
/// 不做本地兜底；加载失败给「重试」，不拿旧文本顶上。
///
Future<void> showProtocolSheet(BuildContext context, ProtocolKind kind) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Z.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Z.rXl)),
      ),
      builder: (_) => _ProtocolSheet(kind: kind),
    );

class _ProtocolSheet extends StatefulWidget {
  const _ProtocolSheet({required this.kind});

  final ProtocolKind kind;

  @override
  State<_ProtocolSheet> createState() => _ProtocolSheetState();
}

class _ProtocolSheetState extends State<_ProtocolSheet> {
  late final ProtocolService _service = context.read<CloudService>().protocols;
  late Future<String> _future = _service.load(widget.kind);

  String get _title =>
      widget.kind == ProtocolKind.privacy ? '隐私政策' : '平台注册协议';

  void _retry() =>
      setState(() => _future = _service.load(widget.kind, refresh: true));

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // 标题与按钮固定，只有正文滚动，长协议也不会把按钮顶出屏幕
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Z.contentMaxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Z.s4, Z.s2, Z.s4, Z.s4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Z.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: Z.s4),
                  Text(_title, style: ZText.title2),
                  const SizedBox(height: Z.s3),
                  Flexible(
                    child: FutureBuilder<String>(
                      future: _future,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const _Loading();
                        }
                        final text = snapshot.data;
                        if (text == null || text.isEmpty) {
                          return _Failed(
                            message:
                                '${snapshot.error ?? '协议内容暂不可用'}',
                            onRetry: _retry,
                          );
                        }
                        return SingleChildScrollView(
                          child: Text(
                            text,
                            style: ZText.body.copyWith(
                              fontSize: 13,
                              height: 1.9,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: Z.s4),
                  ZButton(
                    label: '我知道了',
                    style: ZButtonStyle.ghost,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 36),
    child: Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      ),
    ),
  );
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: ZIcon.xl,
            color: Z.ink4,
          ),
          const SizedBox(height: 10),
          Text(
            '协议加载失败，请检查网络后重试',
            textAlign: TextAlign.center,
            style: ZText.body.copyWith(color: Z.ink2),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: ZText.caption,
          ),
          const SizedBox(height: 14),
          ZButton(
            label: '重试',
            icon: Icons.refresh_rounded,
            height: 42,
            style: ZButtonStyle.ghost,
            onTap: onRetry,
          ),
        ],
      ),
    );
  }
}
