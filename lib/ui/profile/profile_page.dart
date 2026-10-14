import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../services/cloud_service.dart';
import '../../services/session.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../auth/login_page.dart';
import '../kit.dart';
import '../media.dart';
import '../pickers.dart';
import 'about_page.dart';
import 'legal_guide_page.dart';
import 'privacy_page.dart';
import 'reminder_settings_page.dart';
import 'templates_page.dart';

/// SCREEN 08 · 我的 · 设置与维权
/// 头像：有图显示图，没有就是品牌渐变 + 人像图标
class _Avatar extends StatelessWidget {
  const _Avatar({required this.ref, required this.size});

  final String ref;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (ref.isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: Z.logoGradient,
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: Icon(
          Icons.person_rounded,
          size: size * 0.5,
          color: Colors.white,
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: ZPhoto(
        ref: ref,
        radius: size * 0.32,
        placeholderIcon: Icons.person_rounded,
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();

    final session = context.watch<Session>();
    final settings = repository.settings;

    return ZScreen(
      child: Column(
        children: [
          // 底部 tab 已经说明「这是我的页」，不再摆 ZAppBar；设置收进列表最后一行
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                ZCard(
                  // 编辑资料已经收进「设置」：点资料卡直接跳过去；
                  // 游客点了只说清原因（游客模式下的资料不能改）
                  onTap: session.loggedIn
                      ? () => zPush(context, const AboutPage())
                      : () => zToast(context, '游客模式不能修改资料，登录后即可编辑'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 第一行：头像（有图就显示图，没有就用品牌渐变占位）
                      _Avatar(
                        ref: _avatarRefOf(settings, session),
                        size: 64,
                      ),
                      const SizedBox(height: 10),
                      // 第二行：用户名
                      Text(
                        _displayNameOf(settings, session),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZText.title3.copyWith(fontSize: 17),
                      ),
                      const SizedBox(height: 4),
                      // 第三行：流浪天数
                      Text(
                        '你已流浪 ${session.daysSinceFirstSeen} 天',
                        style: ZText.small.copyWith(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            session.loggedIn
                                ? Icons.edit_outlined
                                : Icons.lock_outline_rounded,
                            size: 13,
                            color: Z.ink4,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            session.loggedIn
                                ? '资料在「设置」里编辑'
                                : '登录后可修改资料',
                            style: ZText.micro.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 游客模式：先把「数据只在本机」讲清楚，再给一个登录入口
                if (!session.loggedIn) ...[
                  ZHintBar(
                    text: '游客模式：数据只保存在这台设备，换机或清理浏览器数据就找不回来了。',
                    icon: Icons.phone_iphone_rounded,
                    trailing: TextButton(
                      onPressed: () => zPush(context, const LoginPage()),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        '去登录',
                        style: ZText.label.copyWith(
                          fontSize: 13,
                          color: Z.brand,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                ZCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 3,
                  ),
                  child: Column(
                    children: [
                      ZListRow(
                        icon: Icons.dark_mode_outlined,
                        title: '深色模式',
                        subtitle: _appearanceHint(settings.appearance),
                        // 开关反映的是「当前实际是不是深色」，
                        // 切换后会把外观固定成浅色或深色（想跟随系统去「设置」里改）
                        trailing: Switch(
                          value: Theme.of(context).brightness == Brightness.dark,
                          onChanged: (_) => _toggleDark(context, repository),
                        ),
                        onTap: () => _toggleDark(context, repository),
                      ),
                      ZListRow(
                        icon: Icons.notifications_none_rounded,
                        title: '提醒设置',
                        subtitle:
                            '交租提前 ${settings.reminders.rentDaysAhead} 天 · '
                            '到期提前 ${settings.reminders.contractDaysAhead.join('/')} 天',
                        onTap: () =>
                            zPush(context, const ReminderSettingsPage()),
                      ),
                      ZListRow(
                        icon: Icons.balance_outlined,
                        title: '租房法规指南',
                        subtitle: '押金退还 · 房东义务 · 纠纷流程',
                        onTap: () => zPush(context, const LegalGuidePage()),
                      ),
                      ZListRow(
                        icon: Icons.description_outlined,
                        title: '维权文书模板',
                        subtitle: '催告函 · 投诉信 · 起诉状',
                        onTap: () => zPush(context, const TemplatesPage()),
                        divider: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ZCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 3,
                  ),
                  child: Column(
                    children: [
                      ZListRow(
                        icon: Icons.lock_outline_rounded,
                        title: '隐私政策和平台注册协议',
                        onTap: () => zPush(context, const PrivacyPage()),
                      ),
                      ZListRow(
                        icon: Icons.tune_rounded,
                        title: '设置',
                        subtitle: '外观、昵称、账号与同步',
                        divider: false,
                        onTap: () => zPush(context, const AboutPage()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    session.loggedIn
                        ? '已开启云端同步 · 换机后登录同一账号即可恢复\n本机同时保留一份'
                        : '所有照片与合同数据仅存于本机\n不上传服务器 · 无需登录即可使用',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: Z.font,
                      fontFamilyFallback: Z.fallback,
                      fontSize: 11,
                      height: 1.7,
                      color: Z.ink4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 开关下面的那行说明：说清当前是跟随系统还是已固定
  static String _appearanceHint(AppAppearance appearance) => switch (appearance) {
    AppAppearance.system => '当前跟随系统 · 想固定在「设置」里改',
    AppAppearance.light => '已固定浅色',
    AppAppearance.dark => '已固定深色',
  };

  /// 明暗切换：以「现在实际显示的是不是深色」为基准反过来
  static Future<void> _toggleDark(
    BuildContext context,
    Repository repository,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await repository.updateSettings(
      repository.settings.copyWith(
        appearance: isDark ? AppAppearance.light : AppAppearance.dark,
      ),
    );
  }

  /// 界面上显示的昵称：云端昵称 > 本机昵称 > 提示
  static String _displayNameOf(AppSettings settings, Session session) {
    if (session.nickName.isNotEmpty) return session.nickName;
    if (settings.userName.isNotEmpty) return settings.userName;
    return session.loggedIn ? session.displayName : '未设置昵称';
  }

  /// 头像：云端头像优先，其次本机存的那张
  static String _avatarRefOf(AppSettings settings, Session session) =>
      session.avatarPath.isNotEmpty ? session.avatarPath : settings.avatarRef;

  /// 打开「编辑资料」弹层：头像 / 用户名 / 生日。本机立即生效；登录后再同步到云端。
  ///
  /// 入口有两处：我的页的资料卡（跳到设置）、设置页的「编辑资料」行。
  /// 游客哪儿都改不了 —— 入口拦一次，这里再兜一次。
  static Future<void> showEditProfileSheet(
    BuildContext context, {
    required Repository repository,
    required Session session,
    required CloudService cloud,
  }) async {
    if (!session.loggedIn) {
      zToast(context, '游客模式不能修改资料，登录后即可编辑');
      return;
    }
    final settings = repository.settings;
    final draft = await showModalBottomSheet<_ProfileDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProfileEditSheet(
        repository: repository,
        session: session,
        cloud: cloud,
        initialName: _displayNameOf(settings, session),
        initialAvatar: _avatarRefOf(settings, session),
        initialBirthday: _birthdayOf(settings, session),
      ),
    );
    if (draft == null) return;

    await repository.updateSettings(
      settings.copyWith(
        userName: draft.name,
        avatarRef: draft.avatarRef,
        birthday: draft.birthday,
      ),
    );
    if (!cloud.loggedIn) {
      if (context.mounted) zToast(context, '资料已保存');
      return;
    }
    final payload = <String, Object?>{
      'nickName': draft.name,
      'pic': draft.avatarRef,
      if (draft.birthday.isNotEmpty) 'birthday': draft.birthday,
    };
    try {
      await cloud.profile.updateUserInfo(payload);
      await session.updateUser({...session.user, ...payload});
    } catch (error) {
      if (context.mounted) zToast(context, '资料已存本机，云端同步失败：$error');
      return;
    }
    if (context.mounted) zToast(context, '资料已保存');
  }

  /// 生日：本机设置优先，其次云端资料
  static String _birthdayOf(AppSettings settings, Session session) =>
      settings.birthday.isNotEmpty
      ? settings.birthday
      : '${session.user['birthday'] ?? ''}'.trim();
}

/// 编辑资料弹层：自己管控制器，退出动画跑完再销毁
class _ProfileEditSheet extends StatefulWidget {
  const _ProfileEditSheet({
    required this.repository,
    required this.session,
    required this.cloud,
    required this.initialName,
    required this.initialAvatar,
    required this.initialBirthday,
  });

  final Repository repository;
  final Session session;
  final CloudService cloud;
  final String initialName;
  final String initialAvatar;
  final String initialBirthday;

  @override
  State<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends State<_ProfileEditSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late String _avatarRef = widget.initialAvatar;
  late String _birthday = widget.initialBirthday;
  late DateTime? _birthdayDate = DateTime.tryParse(_birthday);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final bytes = await pickImage(context);
    if (bytes == null || !mounted) return;
    final local = await widget.repository.saveMedia(
      bytes,
      folder: 'avatar',
      name: 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    var remote = '';
    if (widget.cloud.loggedIn) {
      remote = await widget.cloud.uploadMedia(bytes, name: 'avatar.jpg') ?? '';
    }
    if (!mounted) return;
    setState(() => _avatarRef = remote.isNotEmpty ? remote : local);
    if (remote.isNotEmpty) {
      try {
        await widget.cloud.profile.updateUserInfo({'pic': remote});
      } catch (error) {
        if (mounted) zToast(context, '头像已换本机这张，云端稍后再试（$error）');
      }
    }
  }

  Future<void> _pickBirthday() async {
    final picked = await pickDate(
      context,
      initial: _birthdayDate,
      helpText: '选择生日',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _birthdayDate = picked;
      _birthday = fmtDate(picked);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        0,
        18,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ZSheetHeader(
              title: '编辑资料',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 14),
            Center(
              child: Column(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        _Avatar(ref: _avatarRef, size: 76),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: const BoxDecoration(
                              color: Z.brand,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.photo_camera_outlined,
                              size: 13,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('点击换头像', style: ZText.small.copyWith(fontSize: 11.5)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ZField(
              label: '用户名',
              child: TextField(
                controller: _name,
                decoration: const InputDecoration(hintText: '如：小王'),
              ),
            ),
            ZField(
              label: '生日',
              child: InkWell(
                borderRadius: Z.radiusField,
                onTap: _pickBirthday,
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  decoration: BoxDecoration(
                    color: Z.card,
                    borderRadius: Z.radiusField,
                    border: Border.all(color: Z.line),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _birthday.isEmpty ? '未设置' : _birthday,
                        style: ZText.body.copyWith(
                          fontSize: 13.5,
                          color: _birthday.isEmpty ? Z.ink4 : Z.ink,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 15,
                        color: Z.ink4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ZButton(
              label: '保存',
              onTap: () => Navigator.of(context).pop(
                _ProfileDraft(
                  name: _name.text.trim(),
                  avatarRef: _avatarRef,
                  birthday: _birthday,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 编辑资料的结果
class _ProfileDraft {
  const _ProfileDraft({
    required this.name,
    required this.avatarRef,
    required this.birthday,
  });

  final String name;
  final String avatarRef;
  final String birthday;
}
