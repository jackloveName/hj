import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../charts.dart';
import '../kit.dart';
import 'utility_edit_page.dart';
import 'utility_history_page.dart';
import 'utility_parts.dart';

/// SCREEN 07 · 水电燃气 · 费用趋势
class UtilityPage extends StatelessWidget {
  const UtilityPage({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final property = repository.propertyById(propertyId);
    if (property == null) return const ZScreen(child: SizedBox.shrink());

    final records = repository.utilitiesOf(property.id);
    final now = DateTime.now();
    final currentKey = monthKey(now);
    final thisMonth = repository.utilityOfMonth(property.id, currentKey);
    final latest = records.isEmpty ? null : records.first;
    final yearRecords = records
        .where((record) => record.month.startsWith('${now.year}'))
        .toList();

    // 近 6 个月：电 / 水 / 燃气各自一条线，没有记录的月份断开
    final months = [
      for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i, 1),
    ];
    List<double?> monthly(UtilityReading? Function(UtilityRecord) pick) => [
      for (final month in months)
        _costOf(repository, property.id, monthKey(month), pick),
    ];
    final series = [
      ChartSeries(
        name: '电费',
        color: Z.warnDeep,
        values: monthly((record) => record.electricity),
      ),
      ChartSeries(
        name: '水费',
        color: Z.brand,
        values: monthly((record) => record.water),
      ),
      ChartSeries(
        name: '燃气费',
        color: Z.violet,
        values: monthly((record) => record.gas),
      ),
    ].where((item) => item.values.any((value) => value != null)).toList();

    // 已退租的房子是只读归档：不给新增 / 修改入口
    final editable = canAddUtility(property);

    return ZScreen(
      child: Column(
        children: [
          ZAppBar(
            leading: const ZBackButton(),
            title: '水电燃气',
            actions: [
              ZPill(label: currentKey),
            ],
          ),
          if (!editable)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ZHintBar(
                text: '这套房子已退租：抄表记录只能查看和导出，不能再新增或修改。',
                icon: Icons.lock_outline_rounded,
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                ZCard(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Z.brandWash, Z.card],
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  child: Column(
                    children: [
                      Text('本月预估总费用', style: ZText.small),
                      const SizedBox(height: 4),
                      Text(
                        fmtMoney(
                          thisMonth?.totalCost ?? latest?.totalCost ?? 0,
                        ),
                        style: ZText.display,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        thisMonth != null
                            ? '本月已抄表 · 记录于 ${fmtDate(thisMonth.recordedAt)}'
                            : (latest == null
                                  ? '还没有任何抄表记录'
                                  : '本月尚未抄表 · 上次 ${fmtMonthDay(latest.recordedAt)}'),
                        style: ZText.small,
                      ),
                    ],
                  ),
                ),
                ZSectionTitle(
                  title: '表计读数',
                  icon: Icons.bolt_outlined,
                  moreLabel: canAddUtility(property)
                      ? (thisMonth == null ? '去记录' : '修改本月')
                      : null,
                  onMore: canAddUtility(property)
                      ? () => _openEditor(context, property, thisMonth)
                      : null,
                ),
                ZCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Z.s4 - 2,
                    vertical: 0,
                  ),
                  child: Column(
                    children: [
                      UtilityMeterRow(
                        emoji: '⚡',
                        name: '电表',
                        tone: ZTone.warn,
                        reading: thisMonth?.electricity,
                        onTap: editable
                            ? () => _openEditor(context, property, thisMonth)
                            : null,
                      ),
                      UtilityMeterRow(
                        emoji: '💧',
                        name: '水表',
                        tone: ZTone.brand,
                        reading: thisMonth?.water,
                        onTap: editable
                            ? () => _openEditor(context, property, thisMonth)
                            : null,
                      ),
                      UtilityMeterRow(
                        emoji: '🔥',
                        name: '燃气表',
                        tone: ZTone.neutral,
                        reading: thisMonth?.gas,
                        divider: false,
                        onTap: editable
                            ? () => _openEditor(context, property, thisMonth)
                            : null,
                      ),
                    ],
                  ),
                ),
                const ZSectionTitle(
                  title: '近 6 个月费用趋势',
                  icon: Icons.show_chart_rounded,
                ),
                ZCard(
                  child: MultiTrendChart(
                    labels: [for (final month in months) '${month.month}月'],
                    series: series,
                  ),
                ),
                ZSectionTitle(
                  title: '抄表记录',
                  icon: Icons.list_alt_outlined,
                  moreLabel: records.isEmpty ? null : '全部记录',
                  onMore: records.isEmpty
                      ? null
                      : () => zPush(
                          context,
                          UtilityHistoryPage(propertyId: property.id),
                        ),
                ),
                if (yearRecords.isEmpty)
                  ZCard(
                    child: ZListRow(
                      icon: Icons.speed_outlined,
                      title: '${now.year} 年还没有抄表记录',
                      subtitle: '每月抄一次表，退租结算时就说得清',
                      divider: false,
                      onTap: () =>
                          _openEditor(context, property, thisMonth),
                    ),
                  )
                else
                  for (final record in yearRecords)
                    UtilityRecordCard(
                      record: record,
                      onTap: () => zPush(
                        context,
                        UtilityEditPage(
                          propertyId: property.id,
                          recordId: record.id,
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

  /// 「去记录」：本月已填过就改这条，没填过就新增
  void _openEditor(BuildContext context, Property property, UtilityRecord? existing) {
    zPush(
      context,
      UtilityEditPage(propertyId: property.id, recordId: existing?.id),
    );
  }

  double? _costOf(
    Repository repository,
    String propertyId,
    String month,
    UtilityReading? Function(UtilityRecord record) pick,
  ) {
    final record = repository.utilityOfMonth(propertyId, month);
    if (record == null) return null;
    return pick(record)?.cost;
  }
}
