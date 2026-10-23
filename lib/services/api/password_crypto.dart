import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 登录密码加密：与平台前端保持一致
/// （AES-ECB + PKCS7，明文为「毫秒时间戳 + 密码」，输出 Base64）。
String encryptPassword(
  String password, {
  required String secret,
  int? timestampMs,
}) {
  final plain = utf8.encode(
    '${timestampMs ?? DateTime.now().millisecondsSinceEpoch}$password',
  );
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()))..init(
        true,
        PaddedBlockCipherParameters<KeyParameter, Null>(
          KeyParameter(Uint8List.fromList(utf8.encode(secret))),
          null,
        ),
      );
  final encrypted = cipher.process(Uint8List.fromList(plain));
  return base64.encode(encrypted);
}
