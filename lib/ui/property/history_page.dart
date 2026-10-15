import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';
import '../media.dart';
import 'property_detail_page.dart';
import 'property_edit_page.dart';

/// 历史租住：已经退租（含仍在维权的）的房子
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final history =
        repository.properties
            .where((property) => property.status != PropertyStatus.active)
            .toList()
          ..sort((a, b) => _leftAt(b).compareTo(_leftAt(a)));

    return ZScreen(
      child: Column(
        children: [
          ZAppBar(
            leading: const ZBackButton(),
            title: '历史租住',
            subtitle: history.isEmpty ? null : '共 ${history.length} 套',
            actions: [
              ZIconButton(
                icon: Icons.add_rounded,
                tooltip: '新增一套租住',
                color: Z.ink,
                onTap: () => zPush(context, const PropertyEditPage()),
              ),
            ],
          ),
          Expanded(
            child: history.isEmpty
                ? const ZEmpty(
                    icon: Icons.history_rounded,
                    title: '还没有历史租住',
                    message: '退租后把押金状态改成「已退还 / 已扣除」，'
                        '这套房子就会出现在这里，照片和费用记录都会保留。',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                    children: [
                      for (final group in _groupByYear(history)) ...[
                        ZSectionTitle(
                          title: '${group.year} 年',
                          icon: Icons.event_note_outlined,
                          margin: const EdgeInsets.only(top: 14, bottom: 10),
                        ),
                        for (final property in group.items) ...[
                          _HistoryCard(property: property),
                          const SizedBox(height: 10),
                        ],
                      ],
                      const SizedBox(height: 4),
                      const ZHintBar(
                        text: '历史记录的取证照片、费用与维权材料都还在，'
                            '随时可以点开查看或再次导出报告。',
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// 退租时间：优先用押金退还日期，否则退回最后更新时间
DateTime _leftAt(Property property) =>
    property.deposit.returnedDate ?? property.updatedAt;

List<({int year, List<Property> items})> _groupByYear(
  List<Property> properties,
) {
  final groups = <int, List<Property>>{};
  for (final property in properties) {
    groups.putIfAbsent(_leftAt(property).year, () => []).add(property);
  }
  final years = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final year in years) (year: year, items: groups[year]!)];
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final photos = repository.photoCountOf(property.id);
    final deposit = property.deposit;
    final leftAt = _leftAt(property);
    final inDispute = property.status == PropertyStatus.dispute;

    return ZCard(
      padding: const EdgeInsets.all(Z.s3),
      onTap: () =>
          zPush(context, PropertyDetailPage(propertyId: property.id)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ZPhoto(
            ref: property.coverRef,
            width: 72,
            height: 72,
            radius: Z.rMd,
          ),
          const SizedBox(width: Z.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        property.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZText.bodyStrong,
                      ),
                    ),
                    const SizedBox(width: 6),
                    ZTag(
                      label: property.status.label,
                      tone: property.status.tone,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  property.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZText.caption,
                ),
                const SizedBox(height: 6),
                _line(
                  '月租 ${fmtMoney(property.contract.monthlyRent)} · '
                  '押金 ${fmtMoney(property.contract.deposit)}',
                ),
                const SizedBox(height: 2),
                _line(
                  '押金${deposit.status.label}'
                  '${deposit.returnedAmount > 0 ? ' ${fmtMoney(deposit.returnedAmount)}' : ''}'
                  '${deposit.deductedAmount > 0 ? ' · 扣除 ${fmtMoney(deposit.deductedAmount)}' : ''}'
                  ' · 存证 $photos 张',
                  color: inDispute ? Z.danger : Z.ink2,
                ),
                const SizedBox(height: 2),
                _line('退租 ${fmtDate(leftAt)}'),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Z.ink4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String text, {Color? color}) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: ZText.small.copyWith(color: color ?? Z.ink3),
  );
}
