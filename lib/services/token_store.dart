import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/local_store.dart';

/// 存放访问凭证的地方。
///
/// 为什么单独抽出来：Token 比其它数据敏感，移动端应该进系统的
/// Keychain / Keystore，而不是明文躺在 SharedPreferences 里。
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// 旧路径：仍放在本机存储（SharedPreferences / localStorage）
class LocalTokenStore implements TokenStore {
  LocalTokenStore(this._store, {required this.key});

  final LocalStore _store;
  final String key;

  @override
  Future<String?> read() async => _store.getString(key);

  @override
  Future<void> write(String token) => _store.setString(key, token);

  @override
  Future<void> clear() => _store.remove(key);
}

/// 移动端：进 Keychain / Keystore（Android 用 EncryptedSharedPreferences）
///
/// 第一次读到老的明文 Token 时会自动搬到安全存储并删掉明文副本；
/// 万一安全存储不可用（模拟器没配好等），退回明文存储，别把登录态弄丢。
class SecureTokenStore implements TokenStore {
  SecureTokenStore(this._fallback);

  final LocalTokenStore _fallback;

  // flutter_secure_storage 11 的默认实现就是加密的
  // （Android：AES-GCM + RSA 包裹密钥，需 API 23+；iOS：Keychain）
  FlutterSecureStorage get _storage => const FlutterSecureStorage();

  @override
  Future<String?> read() async {
    final key = _fallback.key;
    try {
      final stored = await _storage.read(key: key);
      if (stored != null && stored.isNotEmpty) return stored;
    } catch (error) {
      debugPrint('读取安全存储失败，退回本机存储：$error');
      return _fallback.read();
    }
    // 安全存储里没有：看看老数据里有没有明文 Token，有就迁移过来
    final legacy = await _fallback.read();
    if (legacy != null && legacy.isNotEmpty) {
      try {
        await _storage.write(key: key, value: legacy);
        await _fallback.clear();
      } catch (error) {
        debugPrint('Token 迁移到安全存储失败：$error');
      }
    }
    return legacy;
  }

  @override
  Future<void> write(String token) async {
    try {
      await _storage.write(key: _fallback.key, value: token);
      await _fallback.clear();
    } catch (error) {
      debugPrint('写入安全存储失败，退回本机存储：$error');
      await _fallback.write(token);
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _fallback.key);
    } catch (error) {
      debugPrint('清理安全存储失败：$error');
    }
    await _fallback.clear();
  }
}

/// 按平台挑：Android / iOS 用系统安全存储，其余平台沿用本机存储
TokenStore createTokenStore(LocalStore store, {required String key}) {
  final local = LocalTokenStore(store, key: key);
  if (kIsWeb) return local;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => SecureTokenStore(local),
    _ => local,
  };
}
