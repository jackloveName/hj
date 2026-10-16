import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api/api_client.dart';
import '../../services/cloud_service.dart';
import '../../services/protocol_service.dart';
import '../../theme/tokens.dart';
import '../kit.dart';
import '../legal_sheets.dart';

/// 登录 / 注册页
///
/// 深色欢迎页打头（品牌 + 三件能做的事），下面是悬浮的白色登录卡；
/// 游客模式不再单独占一个面板，只在卡片里放一个入口按钮。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _byPassword = false;
  bool _agreed = false;
  bool _submitting = false;
  bool _sending = false;
  bool _obscure = true;
  int _countdown = 0;
  Timer? _timer;

  /// 轻提示：还没填、格式不对之类的提醒（不打断操作，用小字提示）
  String? _hint;

  /// 服务端返回的错误（验证码错误 / 网络失败等），用醒目提示条
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  CloudService get _cloud => context.read<CloudService>();

  bool get _validPhone => RegExp(r'^1[3-9]\d{9}$').hasMatch(_phone.text.trim());

  void _clearPrompts() => setState(() {
    _hint = null;
    _error = null;
  });

  void _showHint(String hint) => setState(() {
    _hint = hint;
    _error = null;
  });

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown -= 1);
      }
    });
  }

  /// 离开本页：作为根页面（首启）时靠状态切换，作为二级页面时返回上一页
  void _leave() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _sendCode() async {
    if (_countdown > 0 || _sending) return;
    // 同意协议之前不向服务端提交手机号
    final problem = _phoneHint() ?? (_agreed ? null : _agreementHint);
    if (problem != null) {
      _showHint(problem);
      return;
    }
    setState(() {
      _sending = true;
      _hint = null;
      _error = null;
    });
    try {
      await _cloud.sendLoginCode(_phone.text.trim());
      _startCountdown();
      if (mounted) zToast(context, '验证码已发送');
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String? _validate() {
    // 按表单顺序提示，用户跟着从上往下填即可
    final phone = _phoneHint();
    if (phone != null) return phone;
    if (_byPassword) {
      if (_password.text.isEmpty) return '请先输入密码';
      if (_password.text.length < 6) return '密码至少 6 位';
    } else {
      final code = _code.text.trim();
      if (code.isEmpty) return '请先输入短信验证码';
      if (!RegExp(r'^\d{4,6}$').hasMatch(code)) return '验证码一般是 4~6 位数字';
    }
    return _agreed ? null : _agreementHint;
  }

  String? _phoneHint() {
    final phone = _phone.text.trim();
    if (phone.isEmpty) return '请先输入手机号';
    if (!_validPhone) return '手机号格式看起来不对，请检查一下';
    return null;
  }

  String get _agreementHint => '请先勾选下面的《隐私政策》和《平台注册协议》';

  Future<void> _submit() async {
    if (_submitting) return;
    final hint = _validate();
    if (hint != null) {
      _showHint(hint);
      return;
    }
    setState(() {
      _submitting = true;
      _hint = null;
      _error = null;
    });
    try {
      await _cloud.signIn(
        phone: _phone.text.trim(),
        validCode: _code.text.trim(),
        password: _password.text,
        byPassword: _byPassword,
      );
      if (!mounted) return;
      zToast(context, '登录成功，已开启云端同步');
      _leave();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '登录失败：$error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _enterGuestMode() async {
    await _cloud.session.enterGuestMode();
    if (!mounted) return;
    zToast(context, '已进入游客模式，数据只保存在这台设备');
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return ZScreen(
      backgroundColor: Z.navy,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: Z.heroGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (canPop)
                const Padding(
                  padding: EdgeInsets.only(left: 4, top: 2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ZBackButton(onDark: true),
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20, canPop ? 0 : 14, 20, 24),
                  children: [
                    const _BrandHeader(),
                    const SizedBox(height: 22),
                    _formCard(),
                    const SizedBox(height: 18),
                    Center(
                      child: Text(
                        '让每一次租房，都不被坑',
                        style: ZText.micro.copyWith(
                          color: Z.onDarkMuted,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formCard() => ZCard(
    radius: 22,
    shadow: Z.e3,
    border: Border.all(color: Colors.transparent),
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('登录 / 注册', style: ZText.title1),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                _byPassword = !_byPassword;
                _error = null;
              }),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _byPassword ? '验证码登录' : '密码登录',
                style: ZText.caption.copyWith(
                  color: Z.brand,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text('登录后房源、合同、照片自动同步，换手机也不丢', style: ZText.caption),
        const SizedBox(height: 16),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          maxLength: 11,
          onChanged: (_) => _clearPrompts(),
          decoration: const InputDecoration(
            labelText: '手机号',
            hintText: '请输入 11 位手机号',
            prefixIcon: Icon(Icons.smartphone_outlined, size: 18),
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        if (_byPassword)
          TextField(
            controller: _password,
            obscureText: _obscure,
            onChanged: (_) => _clearPrompts(),
            decoration: InputDecoration(
              labelText: '密码',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
              suffixIcon: IconButton(
                tooltip: _obscure ? '显示密码' : '隐藏密码',
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  onChanged: (_) => _clearPrompts(),
                  decoration: const InputDecoration(
                    labelText: '短信验证码',
                    prefixIcon: Icon(Icons.message_outlined, size: 18),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ZButton(
                label: _countdown > 0 ? '${_countdown}s' : '获取验证码',
                style: ZButtonStyle.ghost,
                height: 46,
                expand: false,
                width: 112,
                onTap: _countdown > 0 || _sending ? null : _sendCode,
              ),
            ],
          ),
        const SizedBox(height: 12),
        _AgreementRow(
          agreed: _agreed,
          onToggle: () => setState(() {
            _agreed = !_agreed;
            _hint = null;
            _error = null;
          }),
        ),
        if (_hint != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: ZIcon.xs,
                color: Z.warn,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _hint!,
                  style: ZText.caption.copyWith(color: Z.warnDeep),
                ),
              ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          ZHintBar(
            text: _error!,
            tone: ZTone.danger,
            icon: Icons.error_outline_rounded,
          ),
        ],
        const SizedBox(height: 14),
        ZButton(
          label: _submitting ? '登录中…' : '登录 / 注册',
          icon: Icons.login_rounded,
          onTap: _submitting ? null : _submit,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Divider(height: 1, color: Z.line2)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('或者', style: ZText.caption),
            ),
            Expanded(child: Divider(height: 1, color: Z.line2)),
          ],
        ),
        const SizedBox(height: 14),
        ZButton(
          label: '游客模式进入',
          icon: Icons.person_outline_rounded,
          style: ZButtonStyle.dark,
          onTap: _enterGuestMode,
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '不填手机号也能使用，数据只保存在这台设备；'
            '之后可在「我的 → 账号与同步」里登录同步。',
            textAlign: TextAlign.center,
            style: ZText.micro.copyWith(fontWeight: FontWeight.w400),
          ),
        ),
      ],
    ),
  );
}

/// 深色欢迎区：品牌 + 三件能做的事
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: Z.logoGradient,
                borderRadius: BorderRadius.circular(17),
                boxShadow: Z.brandGlow,
              ),
              child: const Icon(
                Icons.verified_user_outlined,
                size: 27,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '租盾',
                    style: ZText.display.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '从入住到退租，全程守护你的押金',
                    style: ZText.small.copyWith(color: Z.onDarkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _feature(Icons.photo_camera_outlined, '拍照取证'),
            const SizedBox(width: 8),
            _feature(Icons.receipt_long_outlined, '抄表记账'),
            const SizedBox(width: 8),
            _feature(Icons.balance_outlined, '维权文书'),
          ],
        ),
      ],
    );
  }

  Widget _feature(IconData icon, String label) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Z.onDarkChip,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Z.onDarkLine),
      ),
      child: Column(
        children: [
          Icon(icon, size: ZIcon.m, color: Colors.white),
          const SizedBox(height: 6),
          Text(
            label,
            style: ZText.micro.copyWith(
              color: Z.onDarkSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

/// 协议勾选行：隐私政策 + 平台注册协议
class _AgreementRow extends StatelessWidget {
  const _AgreementRow({required this.agreed, required this.onToggle});

  final bool agreed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.only(right: 8, top: 1, bottom: 1),
            child: Container(
              width: 17,
              height: 17,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: agreed ? Z.brand : Z.page,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: agreed ? Z.brand : Z.line),
              ),
              child: agreed
                  ? const Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: onToggle,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '我已阅读并同意', style: ZText.caption),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () => showProtocolSheet(context, ProtocolKind.privacy),
                      child: Text(
                        '《隐私政策》',
                        style: ZText.caption.copyWith(
                          color: Z.brand,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  TextSpan(text: '和', style: ZText.caption),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () => showProtocolSheet(context, ProtocolKind.agreement),
                      child: Text(
                        '《平台注册协议》',
                        style: ZText.caption.copyWith(
                          color: Z.brand,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  TextSpan(
                    text: '；登录后数据会同步到平台服务器，不登录则只保存在本机。',
                    style: ZText.caption,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
