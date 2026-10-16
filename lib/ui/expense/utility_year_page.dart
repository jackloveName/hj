import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';
import 'utility_edit_page.dart';

/// 某一年份的抄表记录：12 个月一条一条列出来。
///
/// - 有记录的月份：点进去是编辑，月份锁定（不能改到别的月份上）
/// - 今年内未记录的月份：给「去记录」入口，补录那个月
/// - 往年未记录的月份：只显示未记录（不允许补录历史年份）
class UtilityYearPage extends StatelessWidget {
  const UtilityYearPage({
    super.key,
    required this.propertyId,
    required this.year,
  });

  final String propertyId;
  final String year;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final records = repository.utilitiesOf(propertyId);
    final summary = summarizeUtilityYear(records, propertyId, year);
    final byMonth = <String, UtilityRecord>{
      for (final record in records)
        if (record.month.startsWith(year)) record.month: record,
    };
    final thisYear = '${DateTime.now().year}';
    final currentMonth = monthKey(DateTime.now());
    // 只列「开始租住」之后的月份：租住之前的月份不属于我的记录，
    // 也不该给我一个「去补录」的入口
    final moveInMonth = monthKey(
      repository.propertyById(propertyId)?.contract.moveInDate ?? DateTime.now(),
    );
    // 这一年实际要列哪些月（倒序）。分不分隔线看「是不是最后一行」，
    // 不能写死 month != 1 —— 从 5 月入住时最后一行是 5 月，写死的话
    // 卡片底部会多出一条横线
    final months = [
      for (var month = 12; month >= 1; month--)
        if ('$year-${month.toString().padLeft(2, '0')}'.compareTo(moveInMonth) >=
            0)
          month,
    ];

    return ZScreen(
      child: Column(
        children: [
          ZAppBar(
            leading: const ZBackButton(),
            title: '$year 年抄表',
            subtitle: '${summary.months} 个月有记录 · 合计 ${fmtMoney(summary.cost)}',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                _YearSummaryCard(summary: summary),
                const ZSectionTitle(
                  title: '12 个月明细',
                  icon: Icons.calendar_month_outlined,
                ),
                ZCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 3,
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < months.length; i++)
                        _MonthRow(
                          monthKeyOf:
                              '$year-${months[i].toString().padLeft(2, '0')}',
                          record:
                              byMonth['$year-${months[i].toString().padLeft(2, '0')}'],
                          canAdd:
                              year == thisYear &&
                              '$year-${months[i].toString().padLeft(2, '0')}'
                                  .compareTo(currentMonth) <=
                              0,
                          // 最后一行不画底线：别让卡片底部多出一横
                          divider: i != months.length - 1,
                          propertyId: propertyId,
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

class _YearSummaryCard extends StatelessWidget {
  const _YearSummaryCard({required this.summary});

  final UtilityYearSummary summary;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String, Color)>[
      ('电费', '${fmtAmount(summary.electricity)} kWh', Z.warnDeep),
      ('水费', '${fmtAmount(summary.water)} m³', Z.brand),
      ('燃气费', '${fmtAmount(summary.gas)} m³', Z.violet),
    ];

    return ZCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('年度合计', style: ZText.small),
              const Spacer(),
              Text(
                fmtMoney(summary.cost),
                style: ZText.title2.copyWith(color: Z.brand, fontSize: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              for (final (label, value, color) in rows)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ZDot(color: color, size: 6),
                    const SizedBox(width: 6),
                    Text(
                      '$label $value',
                      style: ZText.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
            ],
          ),
          if (summary.propertyFee > 0 || summary.networkFee > 0) ...[
            const SizedBox(height: 8),
            Text(
              '物业 ${fmtMoney(summary.propertyFee)} · '
              '网络 ${fmtMoney(summary.networkFee)}',
              style: ZText.small.copyWith(fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthRow extends StatelessWidget {
  const _MonthRow({
    required this.monthKeyOf,
    required this.record,
    required this.canAdd,
    required this.divider,
    required this.propertyId,
  });

  final String monthKeyOf;
  final UtilityRecord? record;
  final bool canAdd;
  final bool divider;
  final String propertyId;

  @override
  Widget build(BuildContext context) {
    final existing = record;
    if (existing == null) {
      // 未记录的月份：今年且已经到月份了才给补录入口
      return ZListRow(
        icon: Icons.remove_circle_outline_rounded,
        title: monthLabel(monthKeyOf),
        subtitle: '未记录',
        divider: divider,
        chevron: false,
        trailing: canAdd
            ? TextButton(
                onPressed: () => zPush(
                  context,
                  UtilityEditPage(propertyId: propertyId, month: monthKeyOf),
                ),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  '去记录',
                  style: ZText.caption.copyWith(
                    color: Z.brand,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : null,
      );
    }

    final usage = [
      if (existing.electricity != null)
        '电 ${fmtAmount(existing.electricity!.usage)}',
      if (existing.water != null) '水 ${fmtAmount(existing.water!.usage)}',
      if (existing.gas != null) '气 ${fmtAmount(existing.gas!.usage)}',
    ];
    return ZListRow(
      icon: Icons.check_circle_outline_rounded,
      title: monthLabel(monthKeyOf),
      subtitle: usage.isEmpty ? '已记录' : usage.join(' · '),
      divider: divider,
      trailing: Text(
        fmtMoney(existing.totalCost),
        style: ZText.label.copyWith(
          fontSize: 13,
          color: Z.brand,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => zPush(
        context,
        UtilityEditPage(propertyId: propertyId, recordId: existing.id),
      ),
    );
  }
}
