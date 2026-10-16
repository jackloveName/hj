import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../expense/deposit_summary_card.dart';
import '../kit.dart';
import '../media.dart';
import '../reminder_actions.dart';
import 'history_page.dart';
import 'property_detail_page.dart';
import 'property_edit_page.dart';

/// 「我的租住」：以「当前租住」为主角，以前租过的房子收进历史记录。
///
/// 大部分租客同时只有一套房子在租，因此这里不再平铺所有房源：
/// - 当前在租的房子用一张大卡片呈现（拍照取证 / 合同 / 费用 / 维权都从这里进）；
/// - 已经退租或进入纠纷的房子放进「历史记录」，需要时再翻；
/// - 真的有多套在租时，才出现「切换当前租住」入口。
class TenancyPage extends StatelessWidget {
  const TenancyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();

    final all = repository.properties;
    final current = repository.currentProperty;
    final active = all
        .where((property) => property.status == PropertyStatus.active)
        .toList();
    final history = all
        .where((property) => property.status != PropertyStatus.active)
        .toList();

    return ZScreen(
      child: Column(
        children: [
          // 底部 tab 已经说明「这是租住页」，这里不再摆 ZAppBar；
          // 历史记录与新增都收进内容区
          const SizedBox(height: 6),
          Expanded(
            child: all.isEmpty
                ? _OnboardingEmpty(
                    onAdd: () => zPush(context, const PropertyEditPage()),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      // 左上角就是房源切换器（原来这里是「当前租住」四个字）
                      _PropertySwitcher(
                        // 没有在租的房子时别说「当前租住」，那是空话
                        name: current?.name ?? '没有在租的房子',
                        // 只有一套在租时没得换，不摆下拉箭头也不响应点击
                        canSwitch: active.length > 1,
                        onTap: () => _switchCurrent(context, repository),
                        historyLabel: history.isEmpty
                            ? null
                            : '历史 ${history.length} 套',
                        onHistory: () => zPush(context, const HistoryPage()),
                      ),
                      if (current != null)
                        _CurrentCard(property: current)
                      else
                        _NoCurrentSection(properties: history),
                      const SizedBox(height: 18),
                      _AddButton(
                        label: '新增一套租住',
                        onTap: () => zPush(context, const PropertyEditPage()),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _switchCurrent(
    BuildContext context,
    Repository repository,
  ) async {
    final active = repository.properties
        .where((property) => property.status == PropertyStatus.active)
        .toList();
    if (active.length < 2) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Z.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Z.rXl)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: Z.s3),
            Text('切换当前租住', style: ZText.title4),
            const SizedBox(height: Z.s2),
            for (final property in active)
              ListTile(
                leading: const Icon(Icons.home_outlined, color: Z.brand),
                title: Text(property.name),
                subtitle: Text(property.address),
                trailing: property.id == repository.activeId
                    ? const Icon(Icons.check_rounded, color: Z.brand)
                    : null,
                onTap: () => Navigator.of(ctx).pop(property.id),
              ),
            const SizedBox(height: Z.s2),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await repository.setActive(picked);
  }
}

/// 封面上的两个胶囊（状态 / 到期）：真照片与内置底图共用一套
Widget _coverOverlay(Property property, int daysLeft) => Stack(
  children: [
    Positioned(
      left: 10,
      top: 10,
      child: ZPill(
        label: property.status.label,
        background: statusPillColor(property.status),
        foreground: Colors.white,
      ),
    ),
    Positioned(
      right: 10,
      top: 10,
      child: ZPill(
        // 当天到期别写「还有 0 天到期」
        label: daysLeft < 0
            ? '已到期'
            : (daysLeft == 0 ? '今天到期' : '还有 $daysLeft 天到期'),
        background: Z.scrimNavy,
        foreground: Colors.white,
      ),
    ),
  ],
);

/// 左上角的房源切换器：显示当前在租这套的名字，点一下换房。
/// 只有一套在租时不摆下拉箭头（没得换），历史入口仍留在右侧。
class _PropertySwitcher extends StatelessWidget {
  const _PropertySwitcher({
    required this.name,
    required this.canSwitch,
    required this.onTap,
    this.historyLabel,
    this.onHistory,
  });

  final String name;
  final bool canSwitch;
  final VoidCallback onTap;
  final String? historyLabel;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        children: [
          Icon(Icons.home_outlined, size: ZIcon.m, color: Z.ink3),
          const SizedBox(width: 7),
          // 名字这格要「吃掉中间的全部空间」：以前用 Flexible + Spacer，
          // Flexible 是宽松的，它没占满的那份额度留在 Spacer 右边，
          // 把「历史 N 套」挤到离右边缘一小截的位置
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: canSwitch ? onTap : null,
                borderRadius: BorderRadius.circular(100),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZText.title4,
                      ),
                    ),
                    if (canSwitch) ...[
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: ZIcon.m,
                        color: Z.brand,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (historyLabel != null && onHistory != null) ...[
            const SizedBox(width: 10),
            InkWell(
              onTap: onHistory,
              child: Row(
                children: [
                  Text(historyLabel!, style: ZText.caption),
                  Icon(Icons.chevron_right_rounded, size: 15, color: Z.ink4),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 租住空状态：入住前准备清单，强调行动而非品牌认知
final class _OnboardingEmpty extends StatelessWidget {
  const _OnboardingEmpty({required this.onAdd});

  final VoidCallback onAdd;

  static const _items = <(IconData, String, String)>[
    (
      Icons.checklist_rounded,
      '入住当天拍全房间',
      '墙壁、地板、家电、门窗——每一个细节都可能成为证据。',
    ),
    (
      Icons.description_outlined,
      '合同与押金留存',
      '合同原件拍照、押金转账凭证一同归档，退租时不扯皮。',
    ),
    (
      Icons.bolt_outlined,
      '起表底数',
      '入住当天抄一次水电气，退租时才有对照依据。',
    ),
    (
      Icons.sticky_note_2_outlined,
      '与房东沟通留痕',
      '微信、电话重点内容截图保存，口头承诺不入账。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const _OnboardingHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              children: [
                const ZSectionTitle(
                  title: '入住前该准备什么',
                  icon: Icons.task_alt_rounded,
                  margin: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < _items.length; i++) ...[
                  _ChecklistTile(
                    icon: _items[i].$1,
                    title: _items[i].$2,
                    desc: _items[i].$3,
                    index: i + 1,
                  ),
                  if (i != _items.length - 1) const SizedBox(height: 10),
                ],
                const SizedBox(height: 16),
                const ZHintBar(
                  text: '这些动作只在入住当天做最有效。退租时再补取，可信度会大幅下降。',
                  tone: ZTone.warn,
                  icon: Icons.lightbulb_outline_rounded,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: ZButton(
              label: '开始第一套租住',
              icon: Icons.add_rounded,
              onTap: onAdd,
            ),
          ),
        ],
      ),
    );
  }
}

/// 入住引导头图：与首页头图同调但色调更深、文案更聚焦行动
final class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: Z.navyGradient),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
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
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.key_rounded,
                  size: 19,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                '入住准备',
                style: TextStyle(
                  fontFamily: Z.font,
                  fontFamilyFallback: Z.fallback,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '退租不扯皮的关键，',
            style: TextStyle(
              fontFamily: Z.font,
              fontFamilyFallback: Z.fallback,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              height: 1.3,
              color: Colors.white,
            ),
          ),
          const Text(
            '是入住当天就备好证据。',
            style: TextStyle(
              fontFamily: Z.font,
              fontFamilyFallback: Z.fallback,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              height: 1.3,
              color: Color(0xFFFFCB6B),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '没有添加租住时，先备好这 4 件事——退租维权时它们就是你的底气。',
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

final class _ChecklistTile extends StatelessWidget {
  const _ChecklistTile({
    required this.icon,
    required this.title,
    required this.desc,
    required this.index,
  });

  final IconData icon;
  final String title;
  final String desc;
  final int index;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Z.brandTint,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                fontFamily: Z.font,
                fontFamilyFallback: Z.fallback,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Z.brand,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 15, color: Z.ink2),
                    const SizedBox(width: 5),
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
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: ZText.caption.copyWith(fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
          Icon(
            Icons.radio_button_unchecked_rounded,
            size: 18,
            color: Z.ink4,
          ),
        ],
      ),
    );
  }
}

/// 当前租住的大卡片：封面 + 关键数字 + 状态标签
class _CurrentCard extends StatelessWidget {
  const _CurrentCard({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final photos = repository.photoCountOf(property.id);
    final pendingRepairs = repository
        .repairsOf(property.id)
        .where((repair) => repair.status != RepairStatus.completed)
        .length;
    final roomsWithPhotos = property.allRooms
        .where((room) => repository.photoCountOf(property.id, room: room) > 0)
        .length;
    final daysLeft = daysFromToday(property.contract.contractEnd);
    final daysIn = daysSince(property.contract.moveInDate);
    // 待办已按「逾期 → 待付 → 其他」排好序，第一条就是最该先做的那件事
    final mine = repository.reminders
        .where((item) => item.propertyId == property.id)
        .toList();
    final next = mine.isEmpty ? null : mine.first;

    return ZCard(
      padding: EdgeInsets.zero,
      onTap: () =>
          zPush(context, PropertyDetailPage(propertyId: property.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 108,
            // 封面固定用内置底图：有没有照片都显示这张，
            // 房源名与地址由底图上的水印负责（和 ZPhoto 的水印同一套样式）
            child: ZDefaultCover(
              watermark: [property.name, property.address],
              overlay: _coverOverlay(property, daysLeft),
            ),
          ),
          // 下一步：把最该先做的那件事摆出来，点一下就到对应的页面
          if (next != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 12, 15, 0),
              child: _NextStep(
                item: next,
                onTap: () => openReminder(context, next),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 0),
            child: Row(
              children: [
                ZStat(
                  label: '月租',
                  value: fmtMoney(property.contract.monthlyRent),
                  valueSize: 14,
                ),
                ZStat(
                  label: daysIn < 0 ? '距入住' : '已住',
                  value: '${daysIn.abs()} 天',
                  valueSize: 14,
                ),
                ZStat(label: '取证照片', value: '$photos 张', valueSize: 14),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 10, 15, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ZTag(
                  label: '$roomsWithPhotos 房间已取证',
                  tone: roomsWithPhotos == property.allRooms.length
                      ? ZTone.brand
                      : ZTone.warn,
                ),
                if (pendingRepairs > 0)
                  ZTag(label: '维修 $pendingRepairs 项待处理', tone: ZTone.warn),
              ],
            ),
          ),
          // 关键日期时间轴 + 押金进度：不用点进去就知道自己走到哪一步了
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Divider(height: 1, color: Z.line2),
                const SizedBox(height: 12),
                _ContractTimeline(contract: property.contract),
                const SizedBox(height: 16),
                _DepositFlow(
                  amount: property.contract.deposit,
                  status: property.deposit.status,
                  returned: property.deposit.returnedAmount,
                  deducted: property.deposit.deductedAmount,
                  deductReason: property.deposit.deductReason,
                  returnedDate: property.deposit.returnedDate,
                ),
              ],
            ),
          ),
          // 只留最常用的：房东是谁、怎么联系。
          // 合同要点与常用入口都收进房源详情页，这张卡片别再拉得太长
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Divider(height: 1, color: Z.line2),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _Fact(
                        label: '房东',
                        value: property.landlord.name.isEmpty
                            ? '未填'
                            : property.landlord.name,
                      ),
                    ),
                    Expanded(
                      child: _Fact(
                        label: '房东电话',
                        value: property.landlord.phone.isEmpty
                            ? '未填'
                            : property.landlord.phone,
                        mono: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 10, 15, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.folder_open_outlined,
                  size: ZIcon.xs,
                  color: Z.brand,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '入住取证 · 合同 · 费用 · 维权材料',
                    style: ZText.caption.copyWith(color: Z.brand),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Z.ink4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

/// 「下一步」：把最该先做的那件待办直接摆出来，点一下就到对应页面
class _NextStep extends StatelessWidget {
  const _NextStep({required this.item, required this.onTap});

  final ReminderItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = ZTag.paletteOf(item.tone);
    return InkWell(
      borderRadius: Z.radiusField,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: Z.radiusField),
        child: Row(
          children: [
            Icon(reminderIcon(item.kind), size: ZIcon.m, color: fg),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '下一步 · ${item.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZText.labelStrong.copyWith(color: fg),
                  ),
                  if (item.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZText.small.copyWith(fontSize: 11.5),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              item.actionLabel,
              style: ZText.label.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: ZIcon.s, color: fg),
          ],
        ),
      ),
    );
  }
}

/// 关键日期时间轴：入住 → 每月交租 → 到期
class _ContractTimeline extends StatelessWidget {
  const _ContractTimeline({required this.contract});

  final ContractInfo contract;

  @override
  Widget build(BuildContext context) {
    final ended = contract.contractEnd.isBefore(DateTime.now());
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _node('入住', fmtDate(contract.moveInDate), Z.ok, first: true),
        _node('每月交租', '${contract.rentDueDay} 号', Z.brand),
        _node('到期', fmtDate(contract.contractEnd), ended ? Z.danger : Z.warn, last: true),
      ],
    );
  }

  Widget _node(
    String label,
    String value,
    Color color, {
    bool first = false,
    bool last = false,
  }) => Expanded(
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 2,
                color: first ? Colors.transparent : Z.line,
              ),
            ),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            Expanded(
              child: Container(
                height: 2,
                color: last ? Colors.transparent : Z.line,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(label, style: ZText.small.copyWith(fontSize: 11)),
        const SizedBox(height: 1),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ZText.captionStrong.copyWith(fontSize: 12),
        ),
      ],
    ),
  );
}

/// 押金进度：已缴纳 → 退租结算 → 已退还，标出当前走到哪一步
class _DepositFlow extends StatelessWidget {
  const _DepositFlow({
    required this.amount,
    required this.status,
    required this.returned,
    required this.deducted,
    required this.deductReason,
    required this.returnedDate,
  });

  final double amount;
  final DepositStatus status;

  /// 押金的实际结果：在「押金追踪」里改了状态、填了金额，这里也要看得见
  /// （费用页操作完回租住页，一眼能看到退了多少、扣了多少）
  final double returned;
  final double deducted;
  final String deductReason;
  final DateTime? returnedDate;

  /// 当前第几步（0 起）；无需押金时整段步骤不画
  int? get _step => switch (status) {
    DepositStatus.none => null,
    DepositStatus.paid => 0,
    DepositStatus.toBeReturned ||
    DepositStatus.partiallyDeducted ||
    DepositStatus.inDispute => 1,
    DepositStatus.returned => 2,
  };

  @override
  Widget build(BuildContext context) {
    final step = _step;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('押金', style: ZText.small.copyWith(fontSize: 11.5)),
            const SizedBox(width: 6),
            Text(
              amount > 0 ? fmtMoney(amount) : '未填写',
              style: ZText.title3.copyWith(fontSize: 15),
            ),
            const Spacer(),
            ZTag(label: status.label, tone: status.tone),
          ],
        ),
        if (status == DepositStatus.partiallyDeducted) ...[
          const SizedBox(height: 4),
          Text(
            '已退 ${fmtMoney(returned)} · 被扣 ${fmtMoney(deducted)}'
            '${deductReason.isEmpty ? '' : '（$deductReason）'}',
            style: ZText.small.copyWith(fontSize: 11, height: 1.5),
          ),
        ] else if (status == DepositStatus.returned) ...[
          const SizedBox(height: 4),
          Text(
            '已退 ${fmtMoney(returned > 0 ? returned : amount)}'
            '${returnedDate == null ? '' : ' · ${fmtDate(returnedDate!)}'}',
            style: ZText.small.copyWith(fontSize: 11, height: 1.5),
          ),
        ] else if (status == DepositStatus.toBeReturned) ...[
          const SizedBox(height: 4),
          Text(
            '押金还在房东手里，退到手记得回来改成「已退还」',
            style: ZText.small.copyWith(fontSize: 11, height: 1.5),
          ),
        ],
        if (step != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              _stepNode('已缴纳', 0, step, first: true),
              _stepNode('退租结算', 1, step),
              _stepNode('已退还', 2, step, last: true),
            ],
          ),
        ],
        if (step == null && amount <= 0) ...[
          const SizedBox(height: 4),
          Text(
            '在「编辑房源 → 押金金额」里填上金额，这里就能追踪退还进度',
            style: ZText.small.copyWith(fontSize: 11, height: 1.5),
          ),
        ],
      ],
    );
  }

  Widget _stepNode(
    String label,
    int index,
    int current, {
    bool first = false,
    bool last = false,
  }) {
    final done = index < current;
    final active = index == current;
    final color = done ? Z.ok : (active ? Z.brand : Z.line);
    return Expanded(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 2,
                  color: first
                      ? Colors.transparent
                      : (index <= current ? Z.brand : Z.line),
                ),
              ),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Container(
                  height: 2,
                  color: last
                      ? Colors.transparent
                      : (index < current ? Z.brand : Z.line),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ZText.small.copyWith(
              fontSize: 11,
              color: active ? Z.ink : Z.ink4,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// 没有任何在租房子（都退租了）
/// 没有在租的房子：一段说明 + 押金摘要。
///
/// 不再在这里重复摆「添加新的租住」按钮 —— 页面下方本来就有「新增一套租住」，
/// 两个按钮挨着放只会让人犹豫点哪个。
class _NoCurrentSection extends StatelessWidget {
  const _NoCurrentSection({required this.properties});

  final List<Property> properties;

  @override
  Widget build(BuildContext context) {
    final toExpense = ZTabSwitch.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ZCard(
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Z.brandTint,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.key_off_outlined,
                  size: ZIcon.s,
                  color: Z.brand,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('现在没有在租的房子', style: ZText.bodyStrong),
                    const SizedBox(height: 3),
                    Text(
                      '需要维权时随时翻历史记录；开始新租约时再添加一套即可。',
                      style: ZText.caption.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        DepositSummaryCard(
          properties: properties,
          actionLabel: '看每套的情况',
          onTap: toExpense == null ? null : () => toExpense(2),
        ),
      ],
    );
  }
}


/// 当前租住卡片里的一个小指标
/// 一条「标签 + 值」的事实展示（合同要点 / 房东 / 押金用）
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: ZText.small.copyWith(fontSize: 11)),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (mono ? ZText.mono : ZText.label).copyWith(
            fontSize: mono ? 12.5 : 13,
            color: Z.ink,
          ),
        ),
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Z.rLg),
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Z.rLg),
          border: Border.all(color: Z.dashed, width: 1.4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded, size: 18, color: Z.brand),
            const SizedBox(width: 6),
            Text(
              label,
              style: ZText.body.copyWith(
                fontWeight: FontWeight.w600,
                color: Z.brand,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
