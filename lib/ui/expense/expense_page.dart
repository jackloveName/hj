import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';
import '../property/property_edit_page.dart';
import 'deposit_page.dart';
import 'utility_page.dart';

/// SCREEN 06 · 费用 · 租金日历
class ExpensePage extends StatefulWidget {
  const ExpensePage({super.key});

  @override
  State<ExpensePage> createState() => _ExpensePageState();
}

class _ExpensePageState extends State<ExpensePage> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();

    final property = repository.currentProperty;
    if (property == null) {
      return const ZScreen(child: _LedgerEmpty());
    }
    final contract = property.contract;
    final key = monthKey(_month);
    // 日历可翻月：标签跟着所选月份走，避免「本月」其实是别的月份
    final scope = key == monthKey(DateTime.now()) ? '本月' : monthShortLabel(key);
    final expense = repository.expenseOfMonth(property.id, key);
    final rentRecord = repository.rentOfMonth(property.id, key);
    final paidMonths = repository.paidMonthsOf(property.id);
    final hasDepositAmount = property.contract.deposit > 0;

    return ZScreen(
      child: Column(
        children: [
          // 底部 tab 已经说明「这是费用页」，不再摆 ZAppBar；
          // 多套房子时的「切换房源」挪到租金日历那一行的右上角
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                // 多套房子时才需要切换：放在最上面，点一下换一套
                if (repository.properties.length > 1)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _switch(context, repository),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                      label: Text(
                        '切换房源 · ${property.name}',
                        style: ZText.caption.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                _SummaryCard(
                  property: property,
                  paidMonths: paidMonths,
                  paidTotal: repository.totalPaidRent(property.id),
                  monthDue: rentRecord?.status == RentStatus.paid
                      ? 0
                      : (rentRecord?.amount ?? contract.monthlyRent),
                  yearTotal: repository.yearlyExpense(
                    property.id,
                    DateTime.now().year,
                  ),
                  monthScope: scope,
                  onDeposit: () =>
                      zPush(context, DepositPage(propertyId: property.id)),
                ),
                ZSectionTitle(
                  title: '租金日历',
                  icon: Icons.calendar_month_outlined,
                  // 右上角就写「更多」：月份本身在下面的日历卡里有（切换也点那里）
                  moreLabel: '更多',
                  onMore: () => _pickMonth(context, property, repository),
                ),
                _CalendarCard(
                  month: _month,
                  rentDueDay: contract.rentDueDay,
                  status: rentRecord?.status,
                  amount: rentRecord?.amount ?? contract.monthlyRent,
                  onPrev: () => setState(
                    () => _month = DateTime(_month.year, _month.month - 1, 1),
                  ),
                  onNext: () => setState(
                    () => _month = DateTime(_month.year, _month.month + 1, 1),
                  ),
                  onTapDue: rentRecord == null
                      ? null
                      : () => _editRent(context, repository, rentRecord),
                ),
                ZSectionTitle(
                  title: '$scope构成',
                  icon: Icons.donut_small_outlined,
                ),
                ZCard(
                  child: Row(
                    children: [
                      ZStat(label: '租金', value: fmtMoney(expense.rent)),
                      ZStat(
                        label: '水电燃气',
                        value: fmtMoney(expense.utility),
                        border: true,
                      ),
                      ZStat(
                        label: '物业网络',
                        value: fmtMoney(expense.other),
                        border: true,
                      ),
                    ],
                  ),
                ),
                // 押金：之前只在顶部那张深色卡的角上写了一行小字，很容易被漏看；
                // 这里单独摆一块，金额 + 状态 + 下一步都写清楚
                const ZSectionTitle(
                  title: '押金',
                  icon: Icons.lock_outline_rounded,
                ),
                ZCard(
                  onTap: () =>
                      zPush(context, DepositPage(propertyId: property.id)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '押金金额',
                                  style: ZText.small.copyWith(fontSize: 11),
                                ),
                                const SizedBox(width: 6),
                                ZTag(
                                  label: property.deposit.status.label,
                                  tone: property.deposit.status.tone,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              hasDepositAmount
                                  ? fmtMoney(property.contract.deposit)
                                  : '未填写',
                              style: ZText.title2.copyWith(fontSize: 20),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              hasDepositAmount
                                  ? property.deposit.status.hint
                                  : '还没填押金金额：去「编辑房源 → 押金金额」补上，'
                                        '退租时才有据可查',
                              style: ZText.small.copyWith(
                                fontSize: 11,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Z.ink4,
                      ),
                    ],
                  ),
                ),
                const ZSectionTitle(title: '水电燃气', icon: Icons.bolt_outlined),
                ZCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 4,
                  ),
                  onTap: () =>
                      zPush(context, UtilityPage(propertyId: property.id)),
                  child: ZListRow(
                    icon: Icons.speed_outlined,
                    title: '抄表与费用趋势',
                    // 整张卡可点，行内自己没有 onTap，箭头要显式打开
                    chevron: true,
                    subtitle:
                        repository.utilityOfMonth(property.id, key) == null
                        ? '本月尚未抄表'
                        : '本月已记录 ${fmtMoney(repository.utilityOfMonth(property.id, key)!.totalCost)}',
                    divider: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _switch(BuildContext context, Repository repository) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final item in repository.properties)
              ListTile(
                title: Text(item.name),
                subtitle: Text(item.address),
                trailing: item.id == repository.activeId
                    ? const Icon(Icons.check_rounded, color: Z.brand)
                    : null,
                onTap: () {
                  repository.setActive(item.id);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMonth(
    BuildContext context,
    Property property,
    Repository repository,
  ) async {
    final rents = repository.rentsOf(property.id);
    if (rents.isEmpty) return;
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final record in rents)
              ListTile(
                leading: ZDot(color: statusColor(record.status), size: 8),
                title: Text(monthLabel(record.month)),
                subtitle: Text(
                  '${fmtMoney(record.amount)} · ${record.status.label}',
                ),
                onTap: () => Navigator.of(ctx).pop(
                  DateTime(
                    int.parse(record.month.split('-')[0]),
                    int.parse(record.month.split('-')[1]),
                    1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _month = picked);
  }

  Color statusColor(RentStatus status) => switch (status) {
    RentStatus.paid => Z.ok,
    RentStatus.pending => Z.warn,
    RentStatus.overdue => Z.danger,
  };

  Future<void> _editRent(
    BuildContext context,
    Repository repository,
    RentRecord record,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _RentSheet(repository: repository, record: record),
    );
  }
}

/// 费用空状态：账本式引导，与首页/租住页的空状态在调性与构图上互不重复
final class _LedgerEmpty extends StatelessWidget {
  const _LedgerEmpty();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _LedgerHeader(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            // 保持非 const：const 组件的 build 不会因父级重建而重跑
            children: [
              const ZSectionTitle(
                title: '不记账会损失什么',
                icon: Icons.warning_amber_rounded,
                margin: EdgeInsets.zero,
              ),
              const SizedBox(height: 12),
              _LossItem(
                icon: Icons.receipt_long_outlined,
                tone: ZTone.danger,
                amount: '¥ 0',
                title: '说不清交了多久',
                desc: '房东一句「你还没交」就能让你补一笔已付过的租金。',
                caseStory: '小状退租时被房东查问 6 月租金是否已付。手机里那笔转账记录早已被清理，给不出凭证的他只能现场补了 3200 元。',
              ),
              _LossItem(
                icon: Icons.bolt_outlined,
                tone: ZTone.warn,
                amount: '¥ 0',
                title: '水电无对照',
                desc: '入住底数没抄，退租时只能接受房东报的数字。',
                caseStory: '退租时房东拿出一本账：电费 800 度、水费 30 吨。但小状入住时电表才 1234 度，退租时 1800 度，实际只用了 566 度。',
              ),
              _LossItem(
                icon: Icons.savings_outlined,
                tone: ZTone.danger,
                amount: '¥ 0',
                title: '押金说不清',
                desc: '退租要扣多少、什么时候退，没有记录就没有话语权。',
                caseStory: '合同写押金 3000，退租时房东扣下 2000 元说是清洁费与家具损耗。没有入住当天拍照取证，小状说不出“原本就是那个样”，只能吃哑巴亏。',
              ),
              SizedBox(height: 18),
              ZSectionTitle(
                title: '记账后你能看到',
                icon: Icons.insights_outlined,
                margin: EdgeInsets.zero,
              ),
              SizedBox(height: 12),
              _LedgerPreview(),
              SizedBox(height: 8),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: ZButton(
            label: '开始记账',
            icon: Icons.add_rounded,
            onTap: () => zPush(context, const PropertyEditPage()),
          ),
        ),
      ],
    );
  }
}

/// 费用头图：品牌渐变 + 账本式主标题，与首页/租住页头图区分
final class _LedgerHeader extends StatelessWidget {
  const _LedgerHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: Z.brandGradient),
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
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 19,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                '费用账本',
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
          const SizedBox(height: 18),
          const Text(
            '每笔钱',
            style: TextStyle(
              fontFamily: Z.font,
              fontFamilyFallback: Z.fallback,
              fontSize: 13,
              color: Z.onDarkMuted,
            ),
          ),
          const Text(
            '都要说得清',
            style: TextStyle(
              fontFamily: Z.font,
              fontFamilyFallback: Z.fallback,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              height: 1.25,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '租金、押金、水电燃气——退租时都要对账，从入住第一天就记。',
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

final class _LossItem extends StatelessWidget {
  const _LossItem({
    required this.icon,
    required this.tone,
    required this.amount,
    required this.title,
    required this.desc,
    required this.caseStory,
  });

  final IconData icon;
  final ZTone tone;
  final String amount;
  final String title;
  final String desc;
  final String caseStory;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = ZTag.paletteOf(tone);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ZCard(
        padding: const EdgeInsets.all(12),
        onTap: () => _showCase(context),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amount,
                  style: TextStyle(
                    fontFamily: Z.font,
                    fontFamilyFallback: Z.fallback,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 2),
                Icon(
                  Icons.expand_more_rounded,
                  size: 14,
                  color: Z.ink4,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showCase(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Z.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Z.rXl)),
      ),
      builder: (ctx) {
        final (bg, fg) = ZTag.paletteOf(tone);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Z.line2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 17, color: fg),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontFamily: Z.font,
                          fontFamilyFallback: Z.fallback,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Z.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Z.line3,
                    borderRadius: BorderRadius.circular(Z.rLg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.history_edu_outlined,
                            size: 13,
                            color: Z.ink3,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '真实场景',
                            style: ZText.caption.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        caseStory,
                        style: ZText.body.copyWith(
                          fontSize: 13,
                          height: 1.7,
                          color: Z.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ZButton(
                    label: '我懂了，开始记账',
                    onTap: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 预览账本：让用户提前看到记账后的样子，降低「记起来麻烦」的顾忌
final class _LedgerPreview extends StatelessWidget {
  const _LedgerPreview();

  @override
  Widget build(BuildContext context) {
    return ZCard(
      padding: const EdgeInsets.all(14),
      onTap: () => zToast(context, '添加房子后，这里会变成你真实的账单'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 14,
                color: Z.ink3,
              ),
              const SizedBox(width: 5),
              Text('本月账单示例', style: ZText.caption.copyWith(fontSize: 11.5)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: Z.brandTint,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '示例',
                  style: TextStyle(
                    fontFamily: Z.font,
                    fontFamilyFallback: Z.fallback,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Z.brand,
                  ),
                ),
              ),
              const Spacer(),
              const Tooltip(
                message: '退租时以这里的状态为准进行结算',
                child: ZTag(label: '待付', tone: ZTone.warn),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('租金', style: ZText.small.copyWith(fontSize: 11)),
                    const SizedBox(height: 3),
                    Tooltip(
                      message: '交租日是每月几号？添加房子后这里会自动跟进',
                      child: Text(
                        '¥ 3,200',
                        style: ZText.label.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 34, color: Z.line2),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('水电燃气', style: ZText.small.copyWith(fontSize: 11)),
                      const SizedBox(height: 3),
                      Tooltip(
                        message: '入住当天抄一次表，退租时才有对照依据',
                        child: Text(
                          '¥ 0',
                          style: ZText.label.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Z.ink4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Z.line2),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('累计已付', style: ZText.caption.copyWith(fontSize: 11.5)),
              const Spacer(),
              Tooltip(
                message: '添加房子并记录付租后这里会逐月增长',
                child: Text(
                  '¥ 0 · 0 个月',
                  style: ZText.label.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Z.ink3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.property,
    required this.paidMonths,
    required this.paidTotal,
    required this.monthDue,
    required this.yearTotal,
    required this.monthScope,
    required this.onDeposit,
  });

  final Property property;
  final int paidMonths;
  final double paidTotal;
  final double monthDue;
  final double yearTotal;
  final String monthScope;
  final VoidCallback onDeposit;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      gradient: Z.navyGradient,
      shadow: Z.e2,
      border: Border.all(color: Colors.transparent),
      onTap: onDeposit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 13,
                color: Z.onDarkMuted,
              ),
              const SizedBox(width: 5),
              Text(
                '押金 ${fmtMoney(property.contract.deposit)} · ${property.deposit.status.label}',
                style: const TextStyle(
                  fontFamily: Z.font,
                  fontFamilyFallback: Z.fallback,
                  fontSize: 11,
                  color: Z.onDarkMuted,
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Z.onDarkMuted,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '已缴 $paidMonths 个月',
                style: const TextStyle(
                  fontFamily: Z.font,
                  fontFamilyFallback: Z.fallback,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.9,
                  height: 1.1,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                fmtMoney(paidTotal),
                style: const TextStyle(
                  fontFamily: Z.font,
                  fontFamilyFallback: Z.fallback,
                  fontSize: 12,
                  color: Z.onDarkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _tile(
                '$monthScope待付',
                fmtMoney(monthDue),
                const Color(0xFFFFCB6B),
              ),
              const SizedBox(width: 8),
              _tile('年度累计支出', fmtMoney(yearTotal), Colors.white),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(String label, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: Z.font,
              fontFamilyFallback: Z.fallback,
              fontSize: 10,
              color: Z.onDarkMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontFamily: Z.font,
              fontFamilyFallback: Z.fallback,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.month,
    required this.rentDueDay,
    required this.status,
    required this.amount,
    required this.onPrev,
    required this.onNext,
    required this.onTapDue,
  });

  final DateTime month;
  final int rentDueDay;
  final RentStatus? status;
  final double amount;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onTapDue;

  @override
  Widget build(BuildContext context) {
    final days = daysInMonth(month.year, month.month);
    final offset = firstWeekdayOfMonth(month.year, month.month) - 1;
    final dueDay = rentDueDay.clamp(1, days);
    final now = DateTime.now();
    final dueColor = switch (status) {
      RentStatus.paid => Z.ok,
      RentStatus.overdue => Z.danger,
      RentStatus.pending => Z.warn,
      null => Z.line,
    };

    return ZCard(
      child: Column(
        children: [
          Row(
            children: [
              InkWell(
                onTap: onPrev,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: Z.ink3,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${month.year} 年 ${month.month} 月',
                    style: ZText.label.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: onNext,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: Z.ink3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 这张卡最该一眼看清的：几号交、交多少、交没交
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: Z.line3,
              borderRadius: Z.radiusField,
            ),
            child: Row(
              children: [
                Icon(Icons.event_available_outlined, size: 14, color: Z.ink3),
                const SizedBox(width: 6),
                Text('$dueDay 号交租', style: ZText.labelStrong),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    fmtMoney(amount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZText.labelStrong.copyWith(color: Z.brand),
                  ),
                ),
                const Spacer(),
                ZTag(
                  label: status?.label ?? '未生成账单',
                  tone: switch (status) {
                    RentStatus.paid => ZTone.ok,
                    RentStatus.overdue => ZTone.danger,
                    RentStatus.pending => ZTone.warn,
                    null => ZTone.neutral,
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 星期表头：周一起，与下面每格一一对齐
          Row(
            children: [
              for (final week in const ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                  child: Center(
                    child: Text(
                      week,
                      style: ZText.small.copyWith(fontSize: 11),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: 1.05,
            ),
            itemCount: offset + days,
            itemBuilder: (context, index) {
              if (index < offset) return const SizedBox.shrink();
              final day = index - offset + 1;
              final isDue = day == dueDay;
              // 「今天」之前是拿月份第一天是周几去比日期，标出来的是 1~7 号，纯属巧合
              final isToday =
                  month.year == now.year &&
                  month.month == now.month &&
                  day == now.day;
              return GestureDetector(
                onTap: isDue ? onTapDue : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: isDue ? dueColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: isToday && !isDue
                        ? Border.all(color: Z.brand, width: 1.3)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontFamily: Z.font,
                          fontFamilyFallback: Z.fallback,
                          fontSize: 11.5,
                          fontWeight: isDue || isToday
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isDue
                              ? Colors.white
                              : (isToday ? Z.brand : Z.ink3),
                        ),
                      ),
                      if (isDue)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Divider(height: 1, color: Z.line2),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legend(Z.ok, '已付'),
              const SizedBox(width: 14),
              _legend(Z.warn, '待付'),
              const SizedBox(width: 14),
              _legend(Z.danger, '逾期'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '点日历上 $dueDay 号那格，可以标记「已付」或改金额',
            style: ZText.small.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
    children: [
      ZDot(color: color, size: 6),
      const SizedBox(width: 4),
      Text(label, style: ZText.small.copyWith(fontSize: 11)),
    ],
  );
}

class _RentSheet extends StatelessWidget {
  const _RentSheet({required this.repository, required this.record});

  final Repository repository;
  final RentRecord record;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  monthLabel(record.month),
                  style: ZText.title3.copyWith(fontSize: 17),
                ),
                const SizedBox(width: 10),
                ZTag(
                  label: record.status.label,
                  tone: switch (record.status) {
                    RentStatus.paid => ZTone.ok,
                    RentStatus.pending => ZTone.warn,
                    RentStatus.overdue => ZTone.danger,
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            ZKv(label: '本期租金', value: fmtMoney(record.amount)),
            ZKv(label: '应付日期', value: fmtDate(record.dueDate), mono: true),
            ZKv(
              label: '实付日期',
              value: record.paidDate == null
                  ? '未支付'
                  : fmtDate(record.paidDate!),
              mono: true,
              divider: false,
            ),
            if (record.overdueDays > 0) ...[
              const SizedBox(height: 10),
              ZHintBar(
                text: '已逾期 ${record.overdueDays} 天，建议尽快支付并留存转账凭证。',
                tone: ZTone.danger,
                icon: Icons.error_outline_rounded,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                if (record.status == RentStatus.paid)
                  Expanded(
                    child: ZButton(
                      label: '取消已付',
                      style: ZButtonStyle.ghost,
                      onTap: () async {
                        await repository.markRentUnpaid(record);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                  )
                else
                  Expanded(
                    child: ZButton(
                      label: '标记已付',
                      onTap: () async {
                        await repository.markRentPaid(record);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
