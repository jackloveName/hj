// 生成 4 张项目预览图（首页 / 租住 / 费用 / 我的），产物在 build/preview/。
//
// 跑法：flutter test test/preview_screens.dart
//
// 文件名故意不以 `_test.dart` 结尾：`flutter test` 默认不会跑它，
// 只有显式指定路径时才执行，免得预览图影响 CI 的测试基线。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zudun/app.dart';
import 'package:zudun/services/api/api_settings.dart';
import 'package:zudun/services/cloud_service.dart';
import 'package:zudun/services/notification_service.dart';
import 'package:zudun/services/session.dart';

import 'zudun_test.dart' as shared;

const Key _shotKey = Key('preview-shot');

http.Response _jsonResponse(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// 中文与数字字体：不加载的话预览图里全是方块
Future<void> _loadFonts() async {
  for (final entry in <String, String>{
    'Outfit': 'assets/fonts/Outfit-400.ttf',
    'NotoSansSC': 'assets/fonts/NotoSansSC-Regular.ttf',
    'JetBrainsMono': 'assets/fonts/JB-Mono-400.ttf',
  }.entries) {
    final loader = FontLoader(entry.key)
      ..addFont(
        Future.value(File(entry.value).readAsBytesSync().buffer.asByteData()),
      );
    await loader.load();
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_shotKey),
  );
  // 真实文件 IO + 图片编码：必须放 runAsync，否则 FakeAsync 下会一直挂着
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/preview/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    stdout.writeln('已生成 ${file.path}');
  });
}

void main() {
  testWidgets('生成 4 张预览图', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _loadFonts();

    final repository = await shared.openTestRepository(tester);
    final session = Session(repository.store);
    await tester.runAsync(() async {
      await shared.seedSmokeData(repository);
      await session.enterGuestMode();
    });
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);

    await tester.pumpWidget(
      RepaintBoundary(
        key: _shotKey,
        child: ZudunApp(
          repository: repository,
          session: session,
          cloud: cloud,
          notifications: NotificationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _shot(tester, 'home');

    // 底栏在页面之后，取最后一个同图标的就是那个 tab
    await tester.tap(find.byIcon(Icons.home_work_outlined).last);
    await tester.pumpAndSettle();
    await _shot(tester, 'tenancy');

    await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined).last);
    await tester.pumpAndSettle();
    await _shot(tester, 'expense');

    await tester.tap(find.byIcon(Icons.person_outline_rounded).last);
    await tester.pumpAndSettle();
    await _shot(tester, 'profile');

    expect(tester.takeException(), isNull);
  });
}
