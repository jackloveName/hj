import 'api_client.dart';

/// 对象存储直传、附件登记与用户资料
class ProfileApi {
  ProfileApi(this._api);

  final ApiClient _api;

  /// 批量获取 OSS 预签名上传地址
  Future<Object?> preSignUrl({required List<String> fileNames}) => _api.get(
    '/mall_biz/ua/oss/get_batch_pre_sign_url',
    params: {'fileNames': fileNames.join(',')},
  );

  /// 把已上传的资源登记到平台资源管理
  Future<void> saveAttachToPlatform(List<Map<String, Object?>> files) =>
      _api.post('/mall_biz/attach_file/save_to_platform', data: files);

  /// 删除云端附件（失败不影响用户操作，因此 silent）
  Future<void> deleteAttachFiles(List<String> filePaths) => _api.post(
    '/mall_biz/attach_file/delete',
    data: {'filePaths': filePaths},
    silent: true,
  );

  Future<void> updateUserInfo(Map<String, Object?> data) =>
      _api.put('/mall_user/user/set_user_info', data: data);

  Future<void> logout() => _api.post('/mall_auth/ma/login_out');

  Future<void> destroyUser({bool forceDestroy = false}) => _api.get(
    '/mall_user/user/destroy_user',
    params: {'forceDestroy': forceDestroy},
  );
}
