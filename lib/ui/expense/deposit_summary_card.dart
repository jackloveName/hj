import 'package:flutter/material.dart';

import '../../data/logic.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';

/// 「还没退到手的押金」摘要卡。
///
/// 房子都退租之后，唯一还需要盯的钱就是押金：谁还没退、有没有在维权。
/// 首页 / 租住页 / 费用页在「没有在租的房子」时都摆这一张，口径统一
/// （金额走 [outstandingDeposit]：待退还算全部、纠纷中算争议的那部分）。
/// 押金都已经结清时换成一句「都退到手了」的浅色提示，不给假的告警感。
class DepositSummaryCard extends StatelessWidget {
  const DepositSummaryCard({
    super.key,
    required this.properties,
    this.onTap,
    this.actionLabel,
  });

  final List<Property> properties;

  /// 点整张卡的跳转（一般给「切到费用页看每套情况」，拿不到就传 null）
  final VoidCallback? onTap;

  /// 副标题里那句补充说明（比如「看每套的情况」）
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    // 「还没到手」按**状态**判断（见 depositNotBack）：金额还没填（0）的房子
    // 也算没到手 —— 以前按金额判断，于是「待退还但没填金额」会被念成
    // 「押金都结清了」。
    final pending = properties.where(depositNotBack).toList();
    final pendingAmount = pending.fold<double>(
      0,
      (sum, property) => sum + outstandingDeposit(property),
    );
    final deductedAmount = pending.fold<double>(
      0,
      (sum, property) => sum + deductedDeposit(property),
    );
    final amount = pendingAmount + deductedAmount;
    final disputing = pending
        .where((property) => property.deposit.status == DepositStatus.inDispute)
        .length;
    final settled = pending.isEmpty;
    final color = settled ? Z.ok : Z.warn;
    final deep = settled ? Z.okDeep : Z.warnDeep;

    final parts = <String>[
      if (pendingAmount > 0) '待退 ${fmtMoney(pendingAmount)}',
      if (deductedAmount > 0) '被扣 ${fmtMoney(deductedAmount)}',
      if (disputing > 0) '$disputing 套在维权',
      ?actionLabel,
    ];
    final detail = settled
        ? '押金都已经退到手'
        : (parts.isEmpty ? '${pending.length} 套还没结清' : parts.join(' · '));

    return ZCard(
      // 令牌里没有 warnTint / okTint：用对应色兑一点浅底，和 ZHintBar 一个做法
      color: color.withValues(alpha: 0.10),
      border: Border.all(color: deep.withValues(alpha: 0.25)),
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            settled
                ? Icons.verified_outlined
                : Icons.hourglass_bottom_rounded,
            size: 18,
            color: deep,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settled ? '押金都结清了' : '还没退到手的押金',
                  style: ZText.label,
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: ZText.caption.copyWith(color: deep, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!settled)
            Text(
              // 金额可能还没填：别念「¥0」，那是「没填」不是「不用退」
              amount > 0 ? fmtMoney(amount) : '金额未填',
              style: ZText.title3.copyWith(fontSize: 18, color: deep),
            ),
        ],
      ),
    );
  }
}
