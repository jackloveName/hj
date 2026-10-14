import 'dart:typed_data';

/// 数据层与云端的桥接：由 CloudService 实现，Repository 只依赖这个抽象，
/// 这样单元测试可以注入假实现，不需要真的联网。
abstract class CloudBridge {
  /// 是否已登录（可以推写云端）
  bool get enabled;

  /// 数据变化后触发一次同步（内部做防抖）
  void schedulePush();

  /// 读取云端照片（只负责下载，缓存由数据层维护）
  Future<Uint8List?> readRemoteMedia(String ref);

  /// 上传照片，返回云端引用；失败时返回 null（数据层会退回本地引用）
  Future<String?> uploadMedia(Uint8List bytes, {required String name});

  /// 尽力删除云端照片（失败不抛错）
  Future<void> releaseRemoteMedia(List<String> refs);
}
