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

/// 全部房源的租房账本：总租金、总租住天数，以及由此算出的平均租金/天
class _RentSummaryCard extends StatelessWidget {
  const _RentSummaryCard({required this.totalRent, required this.totalDays});

  final double totalRent;
  final int totalDays;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ZStat(label: '总租金', value: fmtMoney(totalRent)),
          ZStat(label: '总租住天数', value: '$totalDays 天', border: true),
          ZStat(
            label: '平均租金/天',
            value: totalDays > 0 ? fmtMoney(totalRent / totalDays) : '—',
            border: true,
          ),
        ],
      ),
    );
  }
}

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
    // 全部房源的租房账本：总租金 / 总租住天数（平均租金由这两个算出来）
    final summary = _allPropertiesSummary(repository);

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
                  // 资料卡只做展示，不再跳设置（设置走列表里那一行）
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
                      const SizedBox(height: 6),
                      // 第三行：流浪天数（图标与首页那一行保持一致）
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.explore_outlined,
                            size: 13,
                            color: Z.ink4,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '你已流浪 ${session.daysSinceFirstSeen} 天',
                            style: ZText.small.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 全部房源的租房账本（一套都没有时不摆，免得全是 0）
                if (repository.properties.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _RentSummaryCard(
                    totalRent: summary.rent,
                    totalDays: summary.days,
                  ),
                ],
                const SizedBox(height: 10),
                // 游客模式：先把「数据只在本机」讲清楚，再给一个登录入口
                if (!session.loggedIn) ...[
                  ZHintBar(
                    text: '游客模式：数据只保留在本次使用中，退出 App 就清空；'
                        '登录后才会保存到账号。',
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
                        divider: false,
                        onTap: () =>
                            zPush(context, const ReminderSettingsPage()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 维权相关的两页单独一张卡：和上面的「常用开关」分开，别混在一起
                ZCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 3,
                  ),
                  child: Column(
                    children: [
                      ZListRow(
                        icon: Icons.balance_outlined,
                        title: '租房法规指南',
                        onTap: () => zPush(context, const LegalGuidePage()),
                      ),
                      ZListRow(
                        icon: Icons.description_outlined,
                        title: '维权文书模板',
                        divider: false,
                        onTap: () => zPush(context, const TemplatesPage()),
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
                        divider: false,
                        onTap: () => zPush(context, const AboutPage()),
                      ),
                    ],
                  ),
                ),
                // 登录后不再摆云同步那行说明（默认行为，不用天天讲）；
                // 游客这行要留着：数据退出即清，得先讲清楚
                if (!session.loggedIn) ...[
                  const SizedBox(height: 18),
                  Center(
                    child: Text(
                      '游客模式的数据不保存在本机\n登录账号后才会保存到账号里',
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
              ],
            ),
          ),
        ],
      ),
    );
  }

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
  /// 所有房源的合计：已付租金 + 租住天数。
  /// 在租的算到今天，已退租 / 纠纷的算到合同到期日（更接近「租住结束」）；
  /// 天数按自然日算，负数（还没入住）不算进去。
  static ({double rent, int days}) _allPropertiesSummary(
    Repository repository,
  ) {
    var rent = 0.0;
    var days = 0;
    final today = DateTime.now();
    for (final property in repository.properties) {
      rent += repository.totalPaidRent(property.id);
      final end = property.status == PropertyStatus.active
          ? today
          : property.contract.contractEnd;
      final lived = daysBetween(property.contract.moveInDate, end);
      if (lived > 0) days += lived;
    }
    return (rent: rent, days: days);
  }

  static String _avatarRefOf(AppSettings settings, Session session) =>
      session.avatarPath.isNotEmpty ? session.avatarPath : settings.avatarRef;

  /// 打开「编辑资料」弹层：头像 / 用户名 / 生日。本机立即生效；登录后再同步到云端。
  ///
  /// 入口有两处：我的页的资料卡（跳到设置）、设置页的「编辑资料」行。
  /// 游客也能编辑，只是资料只落在本机、不推云端。
  static Future<void> showEditProfileSheet(
    BuildContext context, {
    required Repository repository,
    required Session session,
    required CloudService cloud,
  }) async {
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
