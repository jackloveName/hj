import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/repository.dart';
import 'services/api/api_settings.dart';
import 'services/cloud_service.dart';
import 'services/notification_service.dart';
import 'services/session.dart';
import 'services/token_store.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadStartupFonts();
  final repository = await Repository.open();
  // 会话、接口配置与云端同步都与 Repository 共用一个本机存储实例，
  // 避免两个写入方互相覆盖
  final settings = ApiSettings(repository.store);
  final session = Session(
    repository.store,
    // 移动端把访问凭证放进 Keychain / Keystore，其它平台沿用本机存储
    tokenStore: createTokenStore(repository.store, key: 'App-Token'),
  );
  final cloud = CloudService(
    repository: repository,
    session: session,
    settings: settings,
  );
  await cloud.restore();
  // 系统通知：跟着数据走，开关与授权都在设置里
  final notifications = NotificationService()..attach(repository);
  runApp(
    ZudunApp(
      repository: repository,
      session: session,
      cloud: cloud,
      notifications: notifications,
    ),
  );
}

/// 把**界面**中文字体显式交给渲染引擎：水印绘制用的是 dart:ui 画布，
/// 需要保证这套字体在所有平台（含 Web）都已注册。
///
/// ⚠️ 这里**只**加载 assets/fonts/ 下的子集字体（各 0.21MB）。
/// PDF 用的全量字体（assets/fonts/pdf/，两个共 4.22MB）绝不能在这里碰：
/// 它由 PdfService.ensureFont() 在真正导出 PDF 时才现取 —— 放在启动路径上
/// 等于每个用户首屏白白多下 4MB，之前「界面/PDF 字体分工」省的体积就白省了。
Future<void> loadStartupFonts() async {
  final loader = FontLoader(Z.cjk)
    ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Bold.ttf'));
  await loader.load();
}
