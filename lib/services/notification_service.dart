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

  /// 系统里现在挂着几条待触发的排期；查不到是 null。
  /// 「页面上说已开启，实际一条都没排上」这种情况靠它露出来。
  int? get queuedCount => _queuedCount;
  int? _queuedCount;

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

  /// 查系统里当前的授权状态（不弹窗）。
  /// 每次进设置页、每次排期前都核对一次：开关是历史设置，授权却可能被系统收回去。
  Future<NotificationPermission> refreshPermission() async {
    if (!await ensureReady()) return NotificationPermission.unsupported;
    try {
      final value = await _channel.checkPermission();
      // 查不到就维持原判，别把 unknown 当成「被拒了」
      if (value == NotificationPermission.unknown) return _permission;
      return _setPermission(value);
    } catch (error) {
      _lastError = '$error';
      notifyListeners();
      return _permission;
    }
  }

  /// 系统里挂着几条待触发排期（null 表示平台查不到）
  Future<int?> pendingCount() async {
    if (!await ensureReady()) return null;
    try {
      return await _channel.pendingCount();
    } catch (_) {
      return null;
    }
  }

  /// 直接弹一条，用来验证「系统通知到底通不通」。
  ///
  /// 返回给界面提示的文案：成功了说去哪儿看，没成功说明为什么
  /// —— 以前这里失败是静默 return，用户按了以为按钮坏了。
  Future<String> showTest() async {
    if (!await ensureReady()) {
      return isWeb
          ? '当前浏览器不支持系统通知（需要 HTTPS 且浏览器允许通知）；'
                '到点仍会在应用内提醒你'
          : '当前平台不支持系统通知；到点仍会在应用内提醒你'
                '${_lastError == null ? '' : '（$_lastError）'}';
    }
    // 先自检：没授权、系统把通知关了、通知类别被静音，这里都会给出具体原因
    final blocked = await _channel.diagnose();
    if (blocked != null) return blocked;
    final id = notificationId('test|${DateTime.now().millisecondsSinceEpoch}');
    try {
      await _show(
        id: id,
        title: '租盾提醒已开启',
        body: '到交租、合同到期、抄表的日子，我会在这里提醒你。',
      );
    } catch (error) {
      _lastError = '$error';
      notifyListeners();
      return '发送失败：$error';
    }
    // 复核一下系统到底收没收到（安卓能查「当前展示中的通知」）
    return await _channel.verify(id) ?? '已发一条测试通知：下拉通知栏看看';
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
      _queuedCount = 0;
      notifyListeners();
      return;
    }

    if (!await ensureReady()) {
      notifyListeners();
      return;
    }

    if (!_channel.supportsScheduling) {
      // 浏览器排不了期，只能页面开着时到点弹
      _queuedCount = null;
      _armInAppTimer();
      notifyListeners();
      return;
    }

    // 排期前先核对系统授权：苹果这边没授权时排期会被静默丢弃，
    // 不核对就会出现「页面说已开启、实际一条都不会响」
    await refreshPermission();
    _syncBlockedHint();

    // 原生端：清掉上一轮的「待触发」排期再排一遍。
    // 这里不能用 cancelAll —— 那会把已经弹出、用户还没看的提醒一起撤掉。
    await _cancelPending();
    for (final plan in _plans) {
      await _schedule(plan);
    }
    await _verifyQueued();
    notifyListeners();
  }

  /// 授权没通过时，把「为什么不会响」记成一句人话，让设置页能直接摆出来
  void _syncBlockedHint() {
    if (_permission == NotificationPermission.denied) {
      final hint = isWeb
          ? '浏览器还没允许通知：先点上面的开关授权，或到站点设置里把「通知」改成允许'
          : '系统还没允许「租盾」发通知：点下面的「授权系统通知」，'
                '或到系统设置里打开通知后回来重开一次开关';
      if (_lastError != hint) _lastError = hint;
      return;
    }
    if (_lastError?.startsWith('系统还没允许') == true ||
        _lastError?.startsWith('浏览器还没允许') == true) {
      _lastError = null;
    }
  }

  /// 排完期回查一次：系统一条都没接，说明这次排期白排了
  Future<void> _verifyQueued() async {
    if (_plans.isEmpty) {
      _queuedCount = 0;
      return;
    }
    int? pending;
    try {
      pending = await _channel.pendingCount();
    } catch (error) {
      _lastError = '$error';
      return;
    }
    _queuedCount = pending;
    if (pending == null) return; // 查不到就不下结论
    if (pending == 0) {
      _lastError = '系统没有接下这次排期：检查「设置 → 通知 → 租盾」是否允许通知，'
          '再回来重开一次开关';
    } else if (_lastError?.startsWith('系统没有接下') == true) {
      _lastError = null;
    }
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
