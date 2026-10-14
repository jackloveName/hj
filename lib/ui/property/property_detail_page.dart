import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../compare/compare_page.dart';
import '../evidence/evidence_rooms_page.dart';
import '../kit.dart';
import '../media.dart';
import 'contract_page.dart';
import 'property_edit_page.dart';
import 'rules_page.dart';
import 'timeline_page.dart';

class PropertyDetailPage extends StatelessWidget {
  const PropertyDetailPage({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final property = repository.propertyById(propertyId);
    if (property == null) {
      return const ZScreen(
        child: ZEmpty(icon: Icons.search_off_rounded, title: '房源不存在'),
      );
    }

    final health = repository.healthOf(property.id);
    final photos = repository.photoCountOf(property.id);
    final coveredRooms = property.allRooms
        .where((room) => repository.photoCountOf(property.id, room: room) > 0)
        .length;

    return ZScreen(
      bottomBar: _BottomBar(property: property),
      child: Column(
        children: [
          _Header(property: property),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _ModuleGrid(
                  property: property,
                  photoCount: photos,
                  roomCount: coveredRooms,
                ),
                const ZSectionTitle(
                  title: '存证健康度',
                  icon: Icons.shield_outlined,
                ),
                _HealthCard(health: health),
                const ZSectionTitle(title: '维权材料', icon: Icons.gavel_outlined),
                ZCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      ZListRow(
                        icon: Icons.compare_arrows_rounded,
                        title: '退租对比报告',
                        subtitle: '入住 / 退租左右对照，一键导出 PDF',
                        onTap: () => zPush(
                          context,
                          ComparePage(propertyId: property.id),
                        ),
                      ),
                      ZListRow(
                        icon: Icons.rule_folder_outlined,
                        title: '房东要求',
                        subtitle:
                            '${repository.rulesOf(property.id).length} 条约定 · 退租时的重要依据',
                        onTap: () =>
                            zPush(context, RulesPage(propertyId: property.id)),
                        divider: false,
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

class _Header extends StatelessWidget {
  const _Header({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: ZPhoto(
        ref: property.coverRef,
        radius: 0,
        overlay: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xBD08142C),
                const Color(0x0D08142C),
                const Color(0xA808142C).withValues(alpha: 0.66),
              ],
              stops: const [0, 0.46, 1],
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 头图上的返回键用统一组件，别各页自己拼
                  const ZBackButton(onDark: true),
                  const SizedBox(width: 6),
                  const Text(
                    '返回房源',
                    style: TextStyle(
                      fontFamily: Z.font,
                      fontFamilyFallback: Z.fallback,
                      fontSize: 12,
                      color: Color(0xCCFFFFFF),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => zPush(
                      context,
                      PropertyEditPage(propertyId: property.id),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        Icons.settings_outlined,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                property.name,
                style: const TextStyle(
                  fontFamily: Z.font,
                  fontFamilyFallback: Z.fallback,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${property.address}${property.subtitle.isEmpty ? '' : ' · ${property.subtitle}'}',
                style: const TextStyle(
                  fontFamily: Z.font,
                  fontFamilyFallback: Z.fallback,
                  fontSize: 12,
                  color: Color(0xC7FFFFFF),
                ),
              ),
              const SizedBox(height: 10),
              // 三枚胶囊在窄屏上放不下，用 Wrap 让它自然换行，不再横向溢出
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  ZPill(
                    label: property.status.label,
                    background: statusPillColor(property.status),
                    foreground: Colors.white,
                  ),
                  ZPill(
                    label: stayDurationLabel(property.contract.moveInDate),
                    background: const Color(0x2EFFFFFF),
                    foreground: Colors.white,
                  ),
                  ZPill(
                    label: '${fmtDate(property.contract.contractEnd)} 到期',
                    background: const Color(0x2EFFFFFF),
                    foreground: Colors.white,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleGrid extends StatelessWidget {
  const _ModuleGrid({
    required this.property,
    required this.photoCount,
    required this.roomCount,
  });

  final Property property;
  final int photoCount;
  final int roomCount;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final repairs = repository.repairsOf(property.id);
    final pendingRepairs = repairs
        .where((r) => r.status != RepairStatus.completed)
        .length;
    final moveOutCount = repository.photoCountOf(
      property.id,
      phase: PhotoPhase.moveOut,
    );

    final modules = <_Module>[
      _Module(
        icon: Icons.photo_camera_outlined,
        label: '入住取证',
        hint: '$photoCount 张 / ${property.allRooms.length} 房间',
        badge: '核心',
        onTap: () => zPush(context, EvidenceRoomsPage(propertyId: property.id)),
      ),
      _Module(
        icon: Icons.description_outlined,
        label: '合同信息',
        hint: '13 个字段',
        onTap: () => zPush(context, ContractPage(propertyId: property.id)),
      ),
      _Module(
        icon: Icons.warning_amber_rounded,
        label: '房东要求',
        hint: '${repository.rulesOf(property.id).length} 条约定',
        tone: ZTone.warn,
        onTap: () => zPush(context, RulesPage(propertyId: property.id)),
      ),
      _Module(
        icon: Icons.build_outlined,
        label: '维修记录',
        hint:
            '${repairs.length} 单'
            '${pendingRepairs > 0 ? ' · $pendingRepairs 待处理' : ''}',
        onTap: () => zPush(
          context,
          TimelinePage(propertyId: property.id, initialTab: 0),
        ),
      ),
      _Module(
        icon: Icons.chat_bubble_outline_rounded,
        label: '沟通记录',
        hint: '${repository.commsOf(property.id).length} 条留痕',
        onTap: () => zPush(
          context,
          TimelinePage(propertyId: property.id, initialTab: 1),
        ),
      ),
      _Module(
        icon: Icons.compare_arrows_rounded,
        label: '退租对比',
        hint: moveOutCount > 0 ? '$moveOutCount 张已拍' : '未开始',
        tone: ZTone.violet,
        emphasize: true,
        onTap: () => zPush(context, ComparePage(propertyId: property.id)),
      ),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 9,
      crossAxisSpacing: 9,
      childAspectRatio: 1.06,
      children: [for (final module in modules) _ModuleTile(module: module)],
    );
  }
}

class _Module {
  const _Module({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
    this.badge,
    this.tone = ZTone.brand,
    this.emphasize = false,
  });

  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;
  final String? badge;
  final ZTone tone;
  final bool emphasize;
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module});

  final _Module module;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = ZTag.paletteOf(module.tone);
    return ZCard(
      padding: const EdgeInsets.fromLTRB(8, 13, 8, 12),
      border: module.emphasize
          ? Border.all(color: Z.violet.withValues(alpha: 0.3), width: 1.4)
          : null,
      gradient: module.emphasize
          ? LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Z.card, const Color(0x0D6C4BD8)],
            )
          : null,
      onTap: module.onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(module.icon, size: 17, color: fg),
              ),
              const SizedBox(height: 7),
              Text(
                module.label,
                style: ZText.label.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                module.hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZText.small.copyWith(fontSize: 11),
              ),
            ],
          ),
          if (module.badge != null)
            Positioned(
              right: -4,
              top: -6,
              child: ZPill(
                label: module.badge!,
                background: Z.brand,
                foreground: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.health});

  final EvidenceHealth health;

  @override
  Widget build(BuildContext context) {
    final percent = (health.ratio * 100).round();
    final color = percent >= 80 ? Z.ok : (percent >= 50 ? Z.warn : Z.danger);
    return ZCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      Container(height: 7, color: Z.line2),
                      FractionallySizedBox(
                        widthFactor: health.ratio.clamp(0.02, 1.0),
                        child: Container(
                          height: 7,
                          decoration: const BoxDecoration(
                            gradient: Z.healthGradient,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$percent%',
                style: ZText.label.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < health.items.length; i++)
            ZKv(
              label: health.items[i].label,
              value: health.items[i].hint,
              valueColor: health.items[i].ok ? Z.ok : Z.warnDeep,
              divider: i != health.items.length - 1,
            ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    return ZBottomBar(
      child: Row(
        children: [
          SizedBox(
            // 图标 + 「补充取证」四个字需要的宽度，108 会差几个像素
            width: 122,
            child: ZButton(
              label: '补充取证',
              style: ZButtonStyle.ghost,
              icon: Icons.photo_camera_outlined,
              onTap: () =>
                  zPush(context, EvidenceRoomsPage(propertyId: property.id)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ZButton(
              label: '开始退租对比',
              style: ZButtonStyle.dark,
              icon: Icons.compare_arrows_rounded,
              onTap: () => zPush(context, ComparePage(propertyId: property.id)),
            ),
          ),
        ],
      ),
    );
  }
}
