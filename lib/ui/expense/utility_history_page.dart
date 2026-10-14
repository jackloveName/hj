import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';
import 'utility_year_page.dart';

/// 全部抄表记录：按年份列出，每行给这一年的合计；点进某一年看 12 个月
class UtilityHistoryPage extends StatelessWidget {
  const UtilityHistoryPage({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final records = repository.utilitiesOf(propertyId);
    final years = <String>{
      for (final record in records) record.month.split('-').first,
    }.toList()..sort((a, b) => b.compareTo(a));

    return ZScreen(
      child: Column(
        children: [
          ZAppBar(
            leading: const ZBackButton(),
            title: '全部抄表记录',
            subtitle: records.isEmpty ? null : '共 ${records.length} 条',
          ),
          Expanded(
            child: years.isEmpty
                ? const ZEmpty(
                    icon: Icons.list_alt_outlined,
                    title: '还没有抄表记录',
                    message: '回到水电燃气页记一笔，这里就会按年份汇总。',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      for (final year in years)
                        _YearCard(
                          propertyId: propertyId,
                          year: year,
                          records: records,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _YearCard extends StatelessWidget {
  const _YearCard({
    required this.propertyId,
    required this.year,
    required this.records,
  });

  final String propertyId;
  final String year;
  final List<UtilityRecord> records;

  @override
  Widget build(BuildContext context) {
    final summary = summarizeUtilityYear(records, propertyId, year);
    final usage = [
      if (summary.electricity > 0) '电 ${fmtAmount(summary.electricity)} kWh',
      if (summary.water > 0) '水 ${fmtAmount(summary.water)} m³',
      if (summary.gas > 0) '气 ${fmtAmount(summary.gas)} m³',
    ];

    return ZCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => zPush(
        context,
        UtilityYearPage(propertyId: propertyId, year: year),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$year 年', style: ZText.bodyStrong.copyWith(fontSize: 15)),
              const SizedBox(width: 8),
              ZTag(label: '${summary.months} 个月', tone: ZTone.brand),
              const Spacer(),
              Text(
                fmtMoney(summary.cost),
                style: ZText.title4.copyWith(color: Z.brand),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: ZIcon.s,
                color: Z.ink4,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  usage.isEmpty ? '这一年还没有用量记录' : usage.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZText.small.copyWith(fontSize: 11.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '合计',
                style: ZText.micro.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
