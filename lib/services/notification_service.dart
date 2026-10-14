import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repository.dart';
import 'notification_channel.dart';
import 'notification_plan.dart';

export 'notification_channel.dart'
    show NotificationChannel, NotificationPermission;
export 'notification_plan.dart' show NotificationPlan, PlanSlot;

/// 系统级通知：把首页「待办提醒」排成系统通知栏里的提醒。
///
/// - Android / iOS / macOS / Linux / Windows：交给系统排期，App 没打开也会响
/// - Web：浏览器不支持「未来时刻的通知」，改成页面开着时到点即弹
///
/// 开关落在 `AppSettings.systemNotifications`；服务只负责在数据或设置变化时
/// 重新排期，不自己存状态。
class NotificationService extends ChangeNotifier {
  NotificationService({NotificationChannel? channel})
    : _channel = channel ?? LocalNotificationChannel();

  final NotificationChannel _channel;

  /// 点击通知后要跳去的槽位；AppShell 消费完会清掉
  PlanSlot? _pendingTapSlot;
  PlanSlot? get pendingTapSlot => _pendingTapSlot;

  /// 通知里带的 payload：`<房子 id>|<槽位>`
  void handleTapPayload(String? payload) {
    if (payload == null || !payload.contains('|')) return;
    final name = payload.split('|').last;
    for (final slot in PlanSlot.values) {
      if (slot.name == name) {
        _pendingTapSlot = slot;
        notifyListeners();
        return;
      }
    }
  }

  void clearPendingTap() {
    if (_pendingTapSlot == null) return;
    _pendingTapSlot = null;
    notifyListeners();
  }

  bool _ready = false;
  bool _available = true;
  bool _enabled = false;
  NotificationPermission _permission = NotificationPermission.unknown;
  List<NotificationPlan> _plans = const [];
  String? _lastError;
  Repository? _repository;
  Timer? _debounce;
  Timer? _inAppTimer;
  DateTime? _lastCheckedAt;

  /// 开关是否打开（取自设置）
  bool get enabled => _enabled;

  /// 当前环境能不能用系统通知（初始化失败时为 false）
  bool get available => _available;
  bool get isWeb => kIsWeb;

  /// 能不能「提前排好、App 关着也响」；Web 上为 false
  bool get supportsScheduling => _channel.supportsScheduling;

  NotificationPermission get permission => _permission;

  /// 已排期的通知（Web 上表示「本次页面会话会响的条数」）
  List<NotificationPlan> get plans => _plans;
  String? get lastError => _lastError;

  /// 初始化（幂等）
  Future<bool> ensureReady() async {
    if (_ready) return _available;
    _ready = true;
    try {
      _available = await _channel.init(onTap: handleTapPayload);
    } catch (error) {
      // 测试环境 / 浏览器不支持 / 平台没实现：安静降级成「只有应用内提醒」
      _available = false;
      _lastError = '$error';
    }
    if (!_available) _permission = NotificationPermission.unsupported;
    notifyListeners();
    return _available;
  }

  /// 用户手动打开开关时调用（Web 上授权必须由用户操作触发）
  Future<NotificationPermission> requestPermission() async {
    if (!await ensureReady()) return NotificationPermission.unsupported;
    try {
      return _setPermission(await _channel.requestPermission());
    } catch (error) {
      _lastError = '$error';
      return _setPermission(NotificationPermission.denied);
    }
  }

  /// 直接弹一条，用来验证「系统通知到底通不通」
  Future<void> showTest() async {
    if (!await ensureReady()) return;
    await _show(
      id: notificationId('test|${DateTime.now().millisecondsSinceEpoch}'),
      title: '租盾提醒已开启',
      body: '到交租、合同到期、抄表的日子，我会在这里提醒你。',
    );
  }

  /// 去系统设置里开通知（被拒绝后给用户一个直达入口）
  Future<void> openSystemSettings() async {
    try {
      await _channel.openSystemSettings();
    } catch (error) {
      _lastError = '$error';
      notifyListeners();
    }
  }

  /// 跟着某个 Repository 走：数据或设置一变就重新排期（防抖）
  ///
  /// [syncNow] 为 false 时只挂监听，不立刻排期（测试里用来精确控制时序）
  void attach(Repository repository, {bool syncNow = true}) {
    if (identical(_repository, repository)) return;
    _repository?.removeListener(_onRepositoryChanged);
    _repository = repository..addListener(_onRepositoryChanged);
    if (syncNow) unawaited(sync());
  }

  void detach() {
    _repository?.removeListener(_onRepositoryChanged);
    _repository = null;
    _debounce?.cancel();
    _stopInAppTimer();
  }

  /// 按当前设置与数据重排：开关关掉就清空
  Future<void> sync() async {
    final repository = _repository;
    if (repository == null) return;
    _enabled = repository.settings.systemNotifications;
    _plans = _enabled
        ? buildNotificationPlan(
            reminders: repository.reminders,
            config: repository.settings.reminders,
            now: DateTime.now(),
          )
        : const [];

    if (!_enabled) {
      await _cancelAll();
      _stopInAppTimer();
      notifyListeners();
      return;
    }

    if (!await ensureReady()) {
      notifyListeners();
      return;
    }

    if (!_channel.supportsScheduling) {
      // 浏览器排不了期，只能页面开着时到点弹
      _armInAppTimer();
      notifyListeners();
      return;
    }

    // 原生端：清掉上一轮的「待触发」排期再排一遍。
    // 这里不能用 cancelAll —— 那会把已经弹出、用户还没看的提醒一起撤掉。
    await _cancelPending();
    for (final plan in _plans) {
      await _schedule(plan);
    }
    notifyListeners();
  }

  void _onRepositoryChanged() {
    // 数据落盘、切页都可能连着通知好几次，攒一下再排
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 800),
      () => unawaited(sync()),
    );
  }

  Future<void> _schedule(NotificationPlan plan) async {
    try {
      await _channel.schedule(plan);
    } catch (error) {
      _lastError = '$error';
    }
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await _channel.show(id: id, title: title, body: body);
    } catch (error) {
      _lastError = '$error';
      notifyListeners();
    }
  }

  Future<void> _cancelPending() async {
    try {
      await _channel.cancelPending();
    } catch (error) {
      _lastError = '$error';
    }
  }

  Future<void> _cancelAll() async {
    try {
      await _channel.cancelAll();
    } catch (error) {
      _lastError = '$error';
    }
  }

  /// 不能排期的平台（Web）：页面开着时，到点就弹
  void _armInAppTimer() {
    _lastCheckedAt = DateTime.now();
    _inAppTimer?.cancel();
    _inAppTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_fireDue());
    });
  }

  void _stopInAppTimer() {
    _inAppTimer?.cancel();
    _inAppTimer = null;
    _lastCheckedAt = null;
  }

  Future<void> _fireDue() async {
    final from = _lastCheckedAt;
    final now = DateTime.now();
    _lastCheckedAt = now;
    if (from == null || _permission != NotificationPermission.granted) return;
    for (final plan in _plans) {
      if (plan.when.isAfter(from) && !plan.when.isAfter(now)) {
        await _show(id: plan.id, title: plan.title, body: plan.body);
      }
    }
  }

  NotificationPermission _setPermission(NotificationPermission value) {
    _permission = value;
    notifyListeners();
    return value;
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }
}
