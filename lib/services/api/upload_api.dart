import 'dart:typed_data';

import '../../data/cloud_ref.dart';
import 'api_client.dart';
import 'api_settings.dart';
import 'profile_api.dart';

/// 上传结果
class UploadedFile {
  const UploadedFile({required this.ref, required this.url});

  final String ref;
  final String url;
}

/// 图片直传：预签名 → 直传对象存储 → 登记附件
class UploadApi {
  UploadApi({required this.api, required this.settings, ProfileApi? profile})
    : profile = profile ?? ProfileApi(api);

  final ApiClient api;
  final ApiSettings settings;
  final ProfileApi profile;

  static const List<String> allowedExtensions = ['jpg', 'jpeg', 'png'];

  Future<UploadedFile> uploadBytes(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final extension = _extensionOf(fileName);
    if (!allowedExtensions.contains(extension)) {
      throw ApiException('图片仅支持 JPG、PNG 格式');
    }

    final signed = _firstSigned(
      await profile.preSignUrl(fileNames: [fileName]),
    );
    final preSignUrl =
        '${signed['preSignUrl'] ?? signed['preSignedUrl'] ?? ''}';
    if (preSignUrl.isEmpty) throw ApiException('获取上传地址失败');

    await api.putBytes(
      preSignUrl,
      bytes,
      contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
    );

    final storedName = '${signed['fileName'] ?? fileName}';
    final remotePath = normalizeRemotePath('${signed['dir'] ?? ''}$storedName');
    await profile.saveAttachToPlatform([
      {
        'type': 1,
        'fileType': extension,
        'fileName': storedName,
        'filePath': remotePath,
        'fileSize': bytes.length,
      },
    ]);

    // 记下这次用到的对象存储域名，之后离线也能拼出访问地址
    await settings.setOssBaseUrl(preSignUrl);
    return UploadedFile(
      ref: OssRef.of(remotePath),
      url: publicUrl(remotePath, width: 480),
    );
  }

  /// 删除云端图片（失败不抛错：清理失败不应阻塞用户操作）
  Future<bool> delete(List<String> refs) async {
    final paths = refs
        .where(OssRef.isRemote)
        .map(OssRef.pathOf)
        .toSet()
        .toList();
    if (paths.isEmpty) return false;
    try {
      await profile.deleteAttachFiles(paths);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 资源路径 → 可访问地址；`width` 非空时走 OSS 图片处理
  String publicUrl(String remotePath, {int? width}) {
    final value = remotePath.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http')) return value;
    final base = settings.ossBaseUrl;
    final url = '$base${value.startsWith('/') ? '' : '/'}$value';
    if (width == null) return url;
    return '$url?x-oss-process=image/resize,w_$width/quality,q_82';
  }

  String publicUrlOfRef(String ref) =>
      OssRef.isRemote(ref) ? publicUrl(OssRef.pathOf(ref)) : '';

  String _extensionOf(String fileName) {
    final name = fileName.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? 'jpg' : name.substring(dot + 1).toLowerCase();
  }

  Map<String, dynamic> _firstSigned(Object? raw) {
    var value = raw;
    for (var i = 0; i < 3; i++) {
      if (value is List) {
        value = value.isEmpty ? null : value.first;
        continue;
      }
      if (value is Map) {
        final map = value.map((k, v) => MapEntry(k.toString(), v));
        if (map['preSignUrl'] != null || map['preSignedUrl'] != null) {
          return map;
        }
        if (map['list'] is List) {
          value = map['list'];
          continue;
        }
        if (map['data'] is List) {
          value = map['data'];
          continue;
        }
        return map;
      }
      break;
    }
    return <String, dynamic>{};
  }
}
