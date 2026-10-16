import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'media_cache_name.dart';

/// 本机媒体引用的前缀：`media:<folder>/<name>`。
///
/// 引用必须**可移植**：iOS 的应用容器路径（那段 UUID）每次重装 / 从备份
/// 恢复到新机都会变，把绝对路径写进数据里，等于照片只在「拍它的那次安装」里有效。
/// Web 端一直用的就是这个形式，两端现在统一。
const String localMediaRefPrefix = 'media:';

class MediaStore {
  MediaStore._(this.root);

  final Directory root;

  /// 旧引用里那段固定目录名，用来在容器路径变化后把文件重新找回来
  static String get _rootMarker =>
      '${Platform.pathSeparator}zudun_media${Platform.pathSeparator}';

  /// 文件系统写入失败会直接抛出异常，因此这里恒为 true。
  bool get lastWritePersisted => true;

  static Future<MediaStore> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory('${dir.path}${Platform.pathSeparator}zudun_media');
    if (!await root.exists()) await root.create(recursive: true);
    return MediaStore._(root);
  }

  String _join(String a, String b) => '$a${Platform.pathSeparator}$b';

  Future<String> saveBytes(
    Uint8List bytes, {
    required String folder,
    required String name,
  }) async {
    final dir = Directory(_join(root.path, folder));
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(_join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    // 返回可移植引用，而不是 file.path
    return '$localMediaRefPrefix$folder/$name';
  }

  /// 一个引用对应的候选文件，按顺序试：
  ///
  /// 1. `media:<folder>/<name>` → 当前媒体目录下（现在的正常形态）
  /// 2. 旧版本写进数据里的绝对路径 → 原样
  /// 3. 旧绝对路径但容器已经变了（重装 / 恢复到新机）→ 按 `zudun_media/` 之后那段重拼
  List<File> _candidates(String ref) {
    if (ref.isEmpty) return const [];
    if (ref.startsWith(localMediaRefPrefix)) {
      final rest = ref.substring(localMediaRefPrefix.length);
      final parts = rest
          .split(RegExp(r'[/\\]'))
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.isEmpty) return const [];
      return [File(_join(root.path, parts.join(Platform.pathSeparator)))];
    }
    final raw = File(ref);
    final at = ref.indexOf(_rootMarker);
    if (at < 0) return [raw];
    return [raw, File(_join(root.path, ref.substring(at + _rootMarker.length)))];
  }

  Future<Uint8List?> read(String ref) async {
    for (final file in _candidates(ref)) {
      if (await file.exists()) return file.readAsBytes();
    }
    return null;
  }

  Future<void> delete(String ref) async {
    for (final file in _candidates(ref)) {
      if (await file.exists()) await file.delete();
    }
  }

  Directory get _cloudRoot =>
      Directory('${root.path}${Platform.pathSeparator}cloud');

  File _cloudFile(String ref) => File(
    '${_cloudRoot.path}${Platform.pathSeparator}${cloudCacheName(ref)}.bin',
  );

  Future<void> saveCloudBytes(String ref, Uint8List bytes) async {
    if (ref.isEmpty) return;
    if (!await _cloudRoot.exists()) await _cloudRoot.create(recursive: true);
    final file = _cloudFile(ref);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<Uint8List?> readCloudBytes(String ref) async {
    if (ref.isEmpty) return null;
    final file = _cloudFile(ref);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> deleteCloudBytes(String ref) async {
    if (ref.isEmpty) return;
    final file = _cloudFile(ref);
    if (await file.exists()) await file.delete();
  }

  Future<int> usedBytes() async {
    var total = 0;
    if (!await root.exists()) return 0;
    await for (final entity in root.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }
}
