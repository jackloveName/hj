import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'media_cache_name.dart';

class MediaStore {
  MediaStore._(this.root);

  final Directory root;

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
    return file.path;
  }

  Future<Uint8List?> read(String ref) async {
    if (ref.isEmpty) return null;
    final file = File(ref);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> delete(String ref) async {
    if (ref.isEmpty) return;
    final file = File(ref);
    if (await file.exists()) await file.delete();
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
