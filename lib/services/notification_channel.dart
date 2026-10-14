import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'notification_plan.dart';

/// 通知授权状态
enum NotificationPermission { unknown, granted, denied, unsupported }

/// 通知通道：把插件调用收在一个接口后面，测试可以整体换掉
abstract class NotificationChannel {
  /// 能不能「提前排好、App 关着也响」；Web 不行
  bool get supportsScheduling;

  /// 初始化；返回 false 表示当前环境不支持
  Future<bool> init({required void Function(String? payload) onTap});

  /// 请求授权（必须由用户操作触发）
  Future<NotificationPermission> requestPermission();

  Future<void> schedule(NotificationPlan plan);

  Future<void> show({
    required int id,
    required String title,
    required String body,
  });

  /// 只清「待触发」的排期，不动通知栏里已经弹出的提醒
  Future<void> cancelPending();

  /// 清掉全部：排期 + 通知栏里已展示的（关闭开关时用）
  Future<void> cancelAll();

  /// 打开系统的通知设置页（被拒绝后让用户能一键去开）
  Future<bool> openSystemSettings();
}

/// 真机实现：flutter_local_notifications
/// （Android / iOS / macOS / Linux / Windows / Web）
class LocalNotificationChannel implements NotificationChannel {
  LocalNotificationChannel({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const String _channelId = 'zudun_reminders';
  static const String _channelName = '租盾提醒';
  static const String _channelDescription = '交租、合同到期、抄表与押金退还提醒';

  @override
  bool get supportsScheduling => !kIsWeb;

  @override
  Future<bool> init({required void Function(String? payload) onTap}) async {
    tz_data.initializeTimeZones();
    await _setupLocalTimeZone();
    final initialized = await _plugin.initialize(
      settings: const InitializationSettings(
        // 通知栏小图标直接用 App 图标
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // 权限一律等用户点开关时再要，不在启动时打扰
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        linux: LinuxInitializationSettings(defaultActionName: '打开租盾'),
        windows: WindowsInitializationSettings(
          appName: '租盾',
          appUserModelId: 'ZuDun.RentGuard',
          guid: '7d3f2a54-1b6c-4f8e-9a2d-5c4b8e1f0a93',
        ),
      ),
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
    // Web 上返回 false 表示浏览器不支持；原生平台有的不返回值，按支持处理
    return initialized ?? !kIsWeb;
  }

  @override
  Future<NotificationPermission> requestPermission() async {
    try {
      if (kIsWeb) {
        final web = _plugin
            .resolvePlatformSpecificImplementation<
              WebFlutterLocalNotificationsPlugin
            >();
        if (web == null) return NotificationPermission.unsupported;
        if (web.permissionStatus == WebNotificationPermission.granted) {
          return NotificationPermission.granted;
        }
        final granted = await web.requestNotificationsPermission();
        return granted == true
            ? NotificationPermission.granted
            : NotificationPermission.denied;
      }

      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final android = _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
          if (android == null) return NotificationPermission.unsupported;
          await android.requestNotificationsPermission();
          final on = await android.areNotificationsEnabled();
          return on == false
              ? NotificationPermission.denied
              : NotificationPermission.granted;
        case TargetPlatform.iOS:
          final granted = await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true);
          return granted == false
              ? NotificationPermission.denied
              : NotificationPermission.granted;
        case TargetPlatform.macOS:
          final granted = await _plugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true);
          return granted == false
              ? NotificationPermission.denied
              : NotificationPermission.granted;
        case TargetPlatform.linux:
        case TargetPlatform.windows:
        case TargetPlatform.fuchsia:
          // 桌面端没有授权弹窗，能初始化就能发
          return NotificationPermission.granted;
      }
    } catch (error) {
      debugPrint('请求通知权限失败：$error');
      return NotificationPermission.denied;
    }
  }

  @override
  Future<void> schedule(NotificationPlan plan) => _plugin.zonedSchedule(
    id: plan.id,
    title: plan.title,
    body: plan.body,
    payload: plan.payload,
    scheduledDate: tz.TZDateTime.from(plan.when, tz.local),
    // 精确闹钟要额外授权（Android 12+），提醒差几分钟无所谓，用非精确
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    notificationDetails: _details(),
  );

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) => _plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: _details(),
  );

  @override
  Future<void> cancelPending() => _plugin.cancelAllPendingNotifications();

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<bool> openSystemSettings() async {
    if (kIsWeb) return false;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return await _plugin
                  .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin
                  >()
                  ?.openAppNotificationSettings() ??
              false;
        case TargetPlatform.iOS:
          return await _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.openAppNotificationSettings() ??
              false;
        case TargetPlatform.macOS:
          return await _plugin
                  .resolvePlatformSpecificImplementation<
                    MacOSFlutterLocalNotificationsPlugin
                  >()
                  ?.openAppNotificationSettings() ??
              false;
        case TargetPlatform.linux:
        case TargetPlatform.windows:
        case TargetPlatform.fuchsia:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  NotificationDetails _details() => const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    web: WebNotificationDetails(),
  );

  /// 时区必须显式设置，否则 timezone 包默认 UTC，提醒会差 8 小时
  Future<void> _setupLocalTimeZone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // 拿不到名字就按当前系统偏移挑一个同偏移的时区
      final offset = DateTime.now().timeZoneOffset;
      for (final location in tz.timeZoneDatabase.locations.values) {
        if (location.currentTimeZone.offset == offset) {
          tz.setLocalLocation(location);
          return;
        }
      }
    }
  }
}
