// 云端资源引用：`oss:/dir/file.jpg`。
//
// 本地引用（文件路径 / `media:` 键）与云端引用用前缀区分，
// 这样同一份数据在「本机模式」和「云端账号」之间切换都不会混淆。
class OssRef {
  OssRef._();

  static const String prefix = 'oss:';

  static bool isRemote(String ref) => ref.startsWith(prefix);

  static String of(String remotePath) =>
      '$prefix${normalizeRemotePath(remotePath)}';

  /// `oss:/dir/a.jpg` → `/dir/a.jpg`
  static String pathOf(String ref) =>
      normalizeRemotePath(ref.substring(prefix.length));
}

/// 统一成 `/dir/file.jpg` 的形式
String normalizeRemotePath(String raw) {
  final joined = raw.replaceAll('\\', '/').replaceAll(RegExp(r'/+'), '/');
  return joined.startsWith('/') ? joined : '/$joined';
}
