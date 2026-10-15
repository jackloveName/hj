import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../evidence/evidence_rooms_page.dart';
import '../expense/utility_page.dart';
import '../kit.dart';
import '../media.dart';
import '../property/history_page.dart';
import '../property/property_edit_page.dart';
import '../property/timeline_page.dart';
import '../reminder_actions.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();

    final property = repository.currentProperty;

    if (property == null) {
      final history = repository.historyProperties;
      return SafeArea(
        child: history.isEmpty
            ? _WelcomeEmpty(
                onAdd: () => zPush(context, const PropertyEditPage()),
              )
            : _AllEndedEmpty(historyCount: history.length),
      );
    }

    final reminders = repository.reminders;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _HeroHeader(property: property, reminderCount: reminders.length),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ZSectionTitle(
                      title: '待办提醒',
                      icon: Icons.notifications_none_rounded,
                      moreLabel: reminders.isEmpty
                          ? null
                          : '${reminders.length} 项',
                      onMore: () => zPush(context, const ReminderListPage()),
                    ),
                    _ReminderCard(
                      reminders: reminders.take(3).toList(),
                      onTap: (item) => openReminder(context, item),
                    ),
                    const ZSectionTitle(
                      title: '快捷操作',
                      icon: Icons.bolt_outlined,
                    ),
                    _QuickActions(property: property),
                    ZSectionTitle(
                      title: '最近取证',
                      icon: Icons.photo_camera_back_outlined,
                      moreLabel: _recentPhotos(repository, property.id).isEmpty
                          ? null
                          : '共 ${repository.photoCountOf(property.id)} 张',
                      onMore: () => zPush(
                        context,
                        EvidenceRoomsPage(propertyId: property.id),
                      ),
                    ),
                    _RecentPhotos(
                      propertyId: property.id,
                      photos: _recentPhotos(repository, property.id),
                    ),
                    const ZSectionTitle(
                      title: '本月概览',
                      icon: Icons.insights_outlined,
                    ),
                    _MonthOverview(property: property),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
      ),
    );
  }

  /// 最近拍的照片（按时间倒序，最多取 6 张给首页展示）
  List<EvidencePhoto> _recentPhotos(Repository repository, String propertyId) {
    final photos = repository.photosOf(propertyId)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return photos.take(6).toList();
  }

}

/// 房子都退租了：提示开始新租约，同时保留历史记录入口
class _AllEndedEmpty extends StatelessWidget {
  const _AllEndedEmpty({required this.historyCount});

  final int historyCount;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final days = session.daysSinceFirstSeen;
    return Column(
      children: [
        Expanded(
          child: ZEmpty(
            icon: Icons.key_off_outlined,
            title: '现在的房子已经退租',
            message: '押金还在等退还、或正在维权时，随时可以回看历史里的照片与报告。',
            actionLabel: '新增一套租住',
            onAction: () => zPush(context, const PropertyEditPage()),
          ),
        ),
        // 房子都退租了也把流浪天数摆出来，别只有「我的」页能看到
        _WanderingLine(days: days),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: TextButton.icon(
            onPressed: () => zPush(context, const HistoryPage()),
            icon: const Icon(Icons.history_rounded, size: 16, color: Z.brand),
            label: Text(
              '查看历史租住 $historyCount 套',
              style: ZText.label.copyWith(color: Z.brand),
            ),
          ),
        ),
      ],
    );
  }
}

/// 新用户首登空状态：品牌头图 + 核心能力卡片，避免单图标空状态过于单薄
class _WelcomeEmpty extends StatelessWidget {
  const _WelcomeEmpty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final days = session.daysSinceFirstSeen;
    return ColoredBox(
      color: Z.page,
      child: Column(
        children: [
          const _WelcomeHero(),
          // 不管第几天都显示：与「我的」页那行「你已流浪 N 天」保持一致
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _WanderingBanner(days: days),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              // 保持非 const：const 组件在父级重建时会被直接复用、不重跑 build，
              // 明暗切换的兜底在 lib/app.dart 的 _AppearanceWatcher（整树标脏）。
              children: [
                const ZSectionTitle(
                  title: '租盾能帮你做什么',
                  icon: Icons.shield_outlined,
                  margin: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),
                const _FeatureItem(
                  icon: Icons.photo_camera_back_outlined,
                  tone: ZTone.brand,
                  title: '入住取证',
                  desc: '搬进当天拍摄房屋状况与设施，押金纠纷有据可依。',
                ),
                const _FeatureItem(
                  icon: Icons.bolt_outlined,
                  tone: ZTone.warn,
                  title: '水电燃气追踪',
                  desc: '按月抄表记录，自动累计费用，退租结算一目了然。',
                ),
                const _FeatureItem(
                  icon: Icons.savings_outlined,
                  tone: ZTone.ok,
                  title: '押金守护',
                  desc: '合同到期、押金退还自动提醒，退租对比报告帮你拿回应得。',
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: ZButton(
              label: '添加我的房子',
              icon: Icons.add_rounded,
              onTap: onAdd,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一行式「你已流浪 N 天」：首页有房源 / 房子都退租时用这个，
/// 横幅那一版留给「还没有房子」的空状态（那里还要多劝两句落地）
class _WanderingLine extends StatelessWidget {
  const _WanderingLine({required this.days, this.onDark = false});

  final int days;

  /// 摆在深色头图上时，文字用深色底上的浅色
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final color = onDark ? Z.onDarkMuted : Z.ink3;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.explore_outlined, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          '你已流浪 $days 天',
          style: ZText.small.copyWith(fontSize: 11.5, color: color),
        ),
      ],
    );
  }
}

/// 「你已流浪 N 天」横幅：在空状态下提醒用户尽快落地
/// 超过 30 天则催促感更强，用「多久没安顿下来了」反问语气
final class _WanderingBanner extends StatelessWidget {
  const _WanderingBanner({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = ZTag.paletteOf(ZTone.warn);
    final headline = days >= 30
        ? '你已流浪 $days 天了'
        : '你已流浪 $days 天';
    final sub = days >= 30
        ? '多久没安顿下来了？是时候添个安心的居所'
        : '还差一步就能落地为家';
    return ZCard(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      shadow: const [],
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.explore_outlined, size: 17, color: fg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    fontFamily: Z.font,
                    fontFamilyFallback: Z.fallback,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: ZText.caption.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 品牌渐变头图：与已登录用户的 _HeroHeader 视觉语言保持一致
class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: Z.heroGradient),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: Z.logoGradient,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                '租盾',
                style: TextStyle(
                  fontFamily: Z.font,
                  fontFamilyFallback: Z.fallback,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            '从入住到退租',
            style: TextStyle(
              fontFamily: Z.font,
              fontFamilyFallback: Z.fallback,
              fontSize: 13,
              color: Z.onDarkMuted,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '全程守护你的押金',
            style: TextStyle(
              fontFamily: Z.font,
              fontFamilyFallback: Z.fallback,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              height: 1.2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '搬进来、住着、退出去——每一个关键动作都帮你留好证据。',
            style: TextStyle(
              fontFamily: Z.font,
              fontFamilyFallback: Z.fallback,
              fontSize: 12,
              height: 1.5,
              color: Z.onDarkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({
    required this.icon,
    required this.tone,
    required this.title,
    required this.desc,
  });

  final IconData icon;
  final ZTone tone;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = ZTag.paletteOf(tone);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ZCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: Z.font,
                      fontFamilyFallback: Z.fallback,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Z.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: ZText.caption.copyWith(fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 深色渐变头图 —— 对应设计稿首页顶部
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.property, required this.reminderCount});

  final Property property;
  final int reminderCount;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final contract = property.contract;
    final daysToRent = daysFromToday(nextRentDue(contract.rentDueDay));
    final daysToEnd = daysFromToday(contract.contractEnd);
    final daysIn = daysSince(contract.moveInDate);

    return Container(
      decoration: const BoxDecoration(gradient: Z.heroGradient),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: Z.logoGradient,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  size: 17,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '租盾',
                style: TextStyle(
                  fontFamily: Z.font,
                  fontFamilyFallback: Z.fallback,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => zPush(context, const ReminderListPage()),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.notifications_none_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    if (reminderCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Z.danger,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$reminderCount',
                            style: const TextStyle(
                              fontFamily: Z.font,
                              fontFamilyFallback: Z.fallback,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '当前租住',
            style: TextStyle(
              fontFamily: Z.font,
              fontFamilyFallback: Z.fallback,
              fontSize: 11.5,
              color: Z.onDarkMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            property.name,
            style: const TextStyle(
              fontFamily: Z.font,
              fontFamilyFallback: Z.fallback,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '合同 ${fmtDate(contract.contractEnd)} 到期 · '
            '${daysToEnd >= 0 ? '还剩 $daysToEnd 天' : '已到期'}',
            style: ZText.small.copyWith(color: Z.onDarkMuted),
          ),
          const SizedBox(height: 6),
          // 与「我的」页那行同一句文案：首页有房源时也看得到流浪天数
          _WanderingLine(days: session.daysSinceFirstSeen, onDark: true),
          const SizedBox(height: 14),
          Row(
            children: [
              // 已入住时长放在第一位：这是租客最关心的「住了多久」
              _stat(
                daysIn < 0 ? '距入住' : '已入住',
                '${daysIn.abs()}',
                '天',
              ),
              const SizedBox(width: 8),
              _stat(
                '距交租',
                daysToRent >= 0 ? '$daysToRent' : '${-daysToRent}',
                '天',
              ),
              const SizedBox(width: 8),
              _stat('押金', fmtMoney(contract.deposit, symbol: true), ''),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, String unit) => Expanded(
    child: Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: Z.font,
              fontFamilyFallback: Z.fallback,
              fontSize: 11,
              color: Z.onDarkMuted,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: Z.font,
                    fontFamilyFallback: Z.fallback,
                    fontSize: value.startsWith('¥') && value.length > 5
                        ? 16
                        : 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    height: 1.2,
                    color: Colors.white,
                  ),
                ),
              ),
              if (unit.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Text(
                    unit,
                    style: const TextStyle(
                      fontFamily: Z.font,
                      fontFamilyFallback: Z.fallback,
                      fontSize: 11,
                      color: Z.onDarkMuted,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.reminders, required this.onTap});

  final List<ReminderItem> reminders;
  final ValueChanged<ReminderItem> onTap;

  @override
  Widget build(BuildContext context) {
    if (reminders.isEmpty) {
      return const ZCard(
        child: ZListRow(
          icon: Icons.check_circle_outline_rounded,
          title: '暂时没有需要处理的事项',
          subtitle: '照片、费用与日期都已安排妥当',
          divider: false,
        ),
      );
    }
    return ZCard(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < reminders.length; i++)
            ZListRow(
              title: reminders[i].title,
              subtitle: reminders[i].subtitle,
              iconTile: _ReminderIcon(
                kind: reminders[i].kind,
                tone: reminders[i].tone,
              ),
              trailing: ZPill(
                label: reminders[i].actionLabel,
                background: ZTag.paletteOf(reminders[i].tone).$1,
                foreground: ZTag.paletteOf(reminders[i].tone).$2,
              ),
              onTap: () => onTap(reminders[i]),
              divider: i != reminders.length - 1,
            ),
        ],
      ),
    );
  }
}

class _ReminderIcon extends StatelessWidget {
  const _ReminderIcon({required this.kind, required this.tone});

  final ReminderKind kind;
  final ZTone tone;

  @override
  Widget build(BuildContext context) {
    final icon = reminderIcon(kind);
    final (bg, fg) = ZTag.paletteOf(tone);
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 16, color: fg),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, VoidCallback)>[
      (
        Icons.photo_camera_outlined,
        '拍照取证',
        () => zPush(context, EvidenceRoomsPage(propertyId: property.id)),
      ),
      (
        Icons.water_drop_outlined,
        '记录水电',
        () => zPush(context, UtilityPage(propertyId: property.id)),
      ),
      (
        Icons.build_outlined,
        '添加维修',
        () => zPush(
          context,
          TimelinePage(propertyId: property.id, initialTab: 0),
        ),
      ),
      (
        Icons.forum_outlined,
        '沟通记录',
        () => zPush(
          context,
          TimelinePage(propertyId: property.id, initialTab: 1),
        ),
      ),
    ];

    return ZCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i == 2)
              SizedBox(
                width: 1,
                height: 34,
                child: VerticalDivider(width: 1, color: Z.line2),
              ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: actions[i].$3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Icon(actions[i].$1, size: 19, color: Z.brand),
                      const SizedBox(height: 6),
                      Text(
                        actions[i].$2,
                        style: TextStyle(
                          fontFamily: Z.font,
                          fontFamilyFallback: Z.fallback,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Z.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 首页的取证照片条：让用户拍完就能在首页看到照片，而不是只看到一个数字
class _RecentPhotos extends StatelessWidget {
  const _RecentPhotos({required this.propertyId, required this.photos});

  final String propertyId;
  final List<EvidencePhoto> photos;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return ZCard(
        onTap: () => zPush(context, EvidenceRoomsPage(propertyId: propertyId)),
        child: const ZListRow(
          icon: Icons.add_a_photo_outlined,
          title: '还没有取证照片',
          subtitle: '入住时逐间拍一遍，退租时照片会按房间左右对照',
          divider: false,
          chevron: true,
        ),
      );
    }

    final total = photos.length;
    return ZCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 72,
            child: Row(
              children: [
                for (final photo in photos.take(total > 4 ? 4 : total)) ...[
                  Expanded(
                    child: InkWell(
                      onTap: () => showPhoto(
                        context,
                        photo.imageRef,
                        title: '${photo.room} · ${photo.phase.label}',
                        caption: fmtDateTime(photo.timestamp),
                      ),
                      child: ZPhoto(ref: photo.thumbRef, height: 72),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (total > 4)
                  Expanded(
                    child: InkWell(
                      onTap: () => zPush(
                        context,
                        EvidenceRoomsPage(propertyId: propertyId),
                      ),
                      child: Container(
                        height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Z.line3,
                          borderRadius: BorderRadius.circular(Z.rSm),
                        ),
                        child: Text(
                          '+${total - 4}',
                          style: ZText.label.copyWith(
                            fontSize: 14,
                            color: Z.ink2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            photos.length == 1
                ? '最近一张：${photos.first.room} · ${fmtMonthDay(photos.first.timestamp)}'
                : '最近 ${photos.length} 张 · 最新 ${fmtMonthDay(photos.first.timestamp)}',
            style: ZText.small.copyWith(fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _MonthOverview extends StatelessWidget {
  const _MonthOverview({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final paid = repository.totalPaidRent(property.id);
    final rents = repository.rentsOf(property.id);
    final unpaid = rents
        .where((r) => r.status != RentStatus.paid)
        .fold<double>(0, (sum, r) => sum + r.amount);
    final utilityTotal = repository.totalUtilityCost(property.id);
    final photos = repository.photoCountOf(property.id);

    return ZCard(
      child: Column(
        children: [
          Row(
            children: [
              _stat('累计已付租金', fmtMoney(paid), Z.ink),
              _stat('待付租金', fmtMoney(unpaid), Z.warnDeep),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Z.line2),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('累计水电燃气', fmtMoney(utilityTotal), Z.ink),
              _stat('取证照片', '$photos 张', Z.ink),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ZText.caption.copyWith(fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: ZText.title3.copyWith(fontSize: 16, color: color)),
      ],
    ),
  );
}

/// 全部提醒列表
class ReminderListPage extends StatelessWidget {
  const ReminderListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final reminders = repository.reminders;

    return ZScreen(
      child: Column(
        children: [
          const ZAppBar(title: '待办提醒', leading: ZBackButton()),
          Expanded(
            child: reminders.isEmpty
                ? const ZEmpty(
                    icon: Icons.check_circle_outline_rounded,
                    title: '今天没有需要处理的事',
                    message: '交租、抄表、合同到期都会在这里提醒你。',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      ZCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 4,
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < reminders.length; i++)
                              ZListRow(
                                title: reminders[i].title,
                                subtitle:
                                    '${reminders[i].propertyName} · ${reminders[i].subtitle}',
                                iconTile: _ReminderIcon(
                                  kind: reminders[i].kind,
                                  tone: reminders[i].tone,
                                ),
                                trailing: ZPill(
                                  label: reminders[i].actionLabel,
                                  background: ZTag.paletteOf(reminders[i].tone)
                                      .$1,
                                  foreground: ZTag.paletteOf(reminders[i].tone)
                                      .$2,
                                ),
                                divider: i != reminders.length - 1,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
