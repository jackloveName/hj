import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';

/// 表计读数的一行：左边是哪块表，右边是本月读数与费用；
/// 本月还没记录时右侧显示「去记录」。
class UtilityMeterRow extends StatelessWidget {
  const UtilityMeterRow({
    super.key,
    required this.emoji,
    required this.name,
    required this.tone,
    required this.reading,
    required this.onTap,
    this.divider = true,
  });

  final String emoji;
  final String name;
  final ZTone tone;

  /// 本月这条记录里的读数；null 表示本月没有记录
  final UtilityReading? reading;

  /// 已退租归档时不给点击（null）
  final VoidCallback? onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final (badgeColor, accent) = ZTag.paletteOf(tone);
    // 燃气没有专属语义色，金额用正文色
    final amountColor = tone == ZTone.neutral ? Z.ink : accent;
    final value = reading;

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: ZIcon.s)),
                ),
                const SizedBox(width: Z.s3),
                Text(name, style: ZText.bodyStrong),
                if (value == null)
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // 只读归档（onTap 为 null）时不再引导「去记录」
                        Text(
                          onTap == null ? '未记录' : '去记录',
                          style: ZText.label.copyWith(
                            color: onTap == null ? Z.ink4 : Z.brand,
                            fontWeight: onTap == null
                                ? FontWeight.w400
                                : FontWeight.w600,
                          ),
                        ),
                        if (onTap != null)
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: ZIcon.s,
                            color: Z.brand,
                          ),
                      ],
                    ),
                  )
                else ...[
                  const SizedBox(width: Z.s2),
                  // 读数可能很长（或字体偏宽），让它收缩省略，不挤破这一行
                  Expanded(
                    child: Text(
                      '${fmtAmount(value.reading)} ${value.unit}'.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: ZText.monoStrong,
                    ),
                  ),
                  const SizedBox(width: Z.s3),
                  Text(
                    fmtMoney(value.cost),
                    style: ZText.title4.copyWith(color: amountColor),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (divider) Divider(height: 1, color: Z.line2),
      ],
    );
  }
}

/// 一条抄表记录：月份 + 当月总额 + 各表用量费用（只展示有读数的表）
class UtilityRecordCard extends StatelessWidget {
  const UtilityRecordCard({
    super.key,
    required this.record,
    required this.onTap,
  });

  final UtilityRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fees = [
      if (record.propertyFee > 0) fmtMoney(record.propertyFee),
      if (record.networkFee > 0) fmtMoney(record.networkFee),
    ];
    final meters = <(String, UtilityReading)>[
      if (record.electricity != null) ('电表', record.electricity!),
      if (record.water != null) ('水表', record.water!),
      if (record.gas != null) ('燃气表', record.gas!),
    ];
    final hasDetail = meters.isNotEmpty || fees.isNotEmpty;

    return ZCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(monthLabel(record.month), style: ZText.bodyStrong),
              const Spacer(),
              Text(
                fmtMoney(record.totalCost),
                style: ZText.title4.copyWith(color: Z.brand),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                size: ZIcon.s,
                color: Z.ink4,
              ),
            ],
          ),
          if (hasDetail) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: Z.line2),
            const SizedBox(height: 6),
            for (final (label, reading) in meters)
              _row(
                label,
                '${fmtAmount(reading.usage)} ${reading.unit}',
                fmtMoney(reading.cost),
              ),
            if (fees.isNotEmpty)
              _row('物业 / 网络', '', fees.join(' · ')),
          ] else ...[
            const SizedBox(height: 6),
            Text('这条记录没有读数', style: ZText.caption),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String usage, String cost) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3.5),
    child: Row(
      children: [
        SizedBox(width: 60, child: Text(label, style: ZText.caption)),
        Expanded(
          child: Text(
            usage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ZText.mono.copyWith(color: Z.ink2),
          ),
        ),
        const SizedBox(width: Z.s2),
        Text(cost, style: ZText.labelStrong),
      ],
    ),
  );
}
