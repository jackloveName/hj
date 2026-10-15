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

  /// 查系统里**当前**的授权状态（不弹窗）。
  /// 拿不到结论时返回 [NotificationPermission.unknown]，别把「查不到」当成「没授权」。
  Future<NotificationPermission> checkPermission();

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

  /// 自检：返回「为什么发不出来」的人话说明；一切正常返回 null。
  /// 「测试通知」用它给出可执行的提示，而不是静默失败。
  Future<String?> diagnose();

  /// 发送后的复核：正常返回 null，否则返回原因（查不到就不下结论）
  Future<String?> verify(int id);

  /// 系统里现在挂着几条**待触发**的排期；查不到返回 null。
  /// iOS 上没授权时排期会被静默丢弃，靠它才能发现「页面说已开启、其实一条都没挂上」。
  Future<int?> pendingCount();
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
    // 时区只是为了让「早上 9 点」这类时刻落在本机时间上；拿不到也不能因此
    // 把整个通知功能判死，所以这里单独兜住
    try {
      await _setupLocalTimeZone();
    } catch (error) {
      debugPrint('设置本机时区失败，按系统默认时区排期：$error');
    }
    // 自检：苹果平台上连平台实现都解析不到，说明 Dart 侧的插件注册没跑到。
    // 这时候 initialize 会抛得很含糊，不如直接说清楚该怎么办
    if (!kIsWeb && !_darwinRegistered) {
      throw StateError(
        'iOS / macOS 原生插件没注册上（flutter_local_notifications）：'
        '在 Mac 上执行 flutter clean && flutter pub get 后重新 flutter run',
      );
    }
    Future<bool?> tryInit() => _plugin.initialize(
      settings: const InitializationSettings(
        // 通知栏小图标直接用 App 图标
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // 权限一律等用户点开关时再要，不在启动时打扰
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          // 前台展示相关的默认值显式写出来：iOS 14+ 只认 banner / list，
          // 这几个值会被落到 NSUserDefaults 里当默认值，留空就会变成「静默不弹」
          defaultPresentAlert: true,
          defaultPresentBanner: true,
          defaultPresentList: true,
          defaultPresentBadge: true,
          defaultPresentSound: true,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          defaultPresentAlert: true,
          defaultPresentBanner: true,
          defaultPresentList: true,
          defaultPresentBadge: true,
          defaultPresentSound: true,
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

    bool? initialized;
    try {
      initialized = await tryInit();
    } catch (error) {
      // 冷启动那一刻插件注册偶尔还没完成（iOS 上尤其容易），
      // 隔一下再试一次；真没接上就让它抛，设置页会把原因显示出来
      debugPrint('系统通知初始化失败，稍后重试：$error');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      initialized = await tryInit();
    }
    // Web 上返回 false 表示浏览器不支持；原生平台有的不返回值，按支持处理
    return initialized ?? !kIsWeb;
  }

  /// iOS / macOS 的平台实现能不能解析到（解析不到 = Dart 插件注册没执行）
  bool get _darwinRegistered {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >() !=
            null;
      case TargetPlatform.macOS:
        return _plugin
                .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin
                >() !=
            null;
      default:
        return true;
    }
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
  Future<NotificationPermission> checkPermission() async {
    if (kIsWeb) {
      final web = _plugin
          .resolvePlatformSpecificImplementation<
            WebFlutterLocalNotificationsPlugin
          >();
      if (web == null) return NotificationPermission.unsupported;
      return web.permissionStatus == WebNotificationPermission.granted
          ? NotificationPermission.granted
          : NotificationPermission.denied;
    }
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final android = _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
          if (android == null) return NotificationPermission.unsupported;
          final on = await android.areNotificationsEnabled();
          return on == false
              ? NotificationPermission.denied
              : NotificationPermission.granted;
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
          final options = await _darwinOptions();
          if (options == null) return NotificationPermission.unknown;
          final on = options.isEnabled || options.isProvisionalEnabled;
          return on
              ? NotificationPermission.granted
              : NotificationPermission.denied;
        case TargetPlatform.linux:
        case TargetPlatform.windows:
        case TargetPlatform.fuchsia:
          return NotificationPermission.granted;
      }
    } catch (error) {
      debugPrint('查询通知授权状态失败：$error');
      return NotificationPermission.unknown;
    }
  }

  /// iOS / macOS 授权详情（含「提醒样式有没有被关」），查不到返回 null
  Future<NotificationsEnabledOptions?> _darwinOptions() async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions();
      case TargetPlatform.macOS:
        return _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions();
      default:
        return null;
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

  @override
  Future<String?> diagnose() async {
    if (kIsWeb) {
      final web = _plugin
          .resolvePlatformSpecificImplementation<
            WebFlutterLocalNotificationsPlugin
          >();
      if (web == null) return '当前浏览器不支持系统通知';
      return switch (web.permissionStatus) {
        WebNotificationPermission.granted => null,
        WebNotificationPermission.denied =>
          '浏览器已拒绝通知：点地址栏左侧的站点设置，把「通知」改成允许',
        _ => '浏览器还没允许通知：先打开上面的开关授权',
      };
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (android == null) return null;
        if (await android.areNotificationsEnabled() == false) {
          return '系统里把「租盾」的通知关掉了：去系统设置 → 应用 → 租盾 → 通知，打开它';
        }
        return null;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        // 苹果这边「没授权」和「授权但把提醒样式关了」都会让通知悄无声息，
        // 只有查一次系统设置才知道，所以这里必须真的查
        final options = await _darwinOptions();
        if (options == null) return null;
        if (!options.isEnabled && !options.isProvisionalEnabled) {
          return '系统里还没允许「租盾」发通知：点「授权系统通知」拉一次授权框，'
              '或去 设置 → 通知 → 租盾 打开「允许通知」';
        }
        if (!options.isAlertEnabled) {
          return '系统里把「租盾」的提醒样式关掉了：去 设置 → 通知 → 租盾 → 提醒，'
              '改成「横幅」或「提醒」';
        }
        return null;
      default:
        return null;
    }
  }

  @override
  Future<int?> pendingCount() async {
    if (kIsWeb) return null;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return pending.length;
    } catch (_) {
      return null; // 平台查不到就不下结论
    }
  }

  @override
  Future<String?> verify(int id) async {
    // 浏览器没有「查已发通知」的接口，只能靠用户看
    if (kIsWeb) return null;
    try {
      final active = await _plugin.getActiveNotifications();
      if (active.isEmpty) return null; // 查不到就不乱下结论
      if (active.any((item) => item.id == id)) return null;
      return '系统没接收这条通知：检查系统的「请勿打扰」，'
          '或把「$_channelName」这个通知类别改成「允许打扰」';
    } catch (_) {
      return null;
    }
  }

  /// iOS 14+ 前台要不要弹，只看 banner / list 这两个开关。
  /// 显式写死，不依赖初始化时落到 NSUserDefaults 的默认值
  /// —— 那条链一旦取不到，通知就是「发出去了但看不见」。
  static const DarwinNotificationDetails _darwinDetails =
      DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: true,
        presentBadge: true,
      );

  NotificationDetails _details() => const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: _darwinDetails,
    macOS: _darwinDetails,
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
