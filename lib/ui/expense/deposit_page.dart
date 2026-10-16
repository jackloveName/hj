import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../compare/compare_page.dart';
import '../kit.dart';

/// 页面 15 · 押金追踪（五态流转）
class DepositPage extends StatelessWidget {
  const DepositPage({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final property = repository.propertyById(propertyId);
    if (property == null) return const ZScreen(child: SizedBox.shrink());
    final deposit = property.deposit;
    final (bg, fg) = ZTag.paletteOf(deposit.status.tone);
    // 已退租：押金只能继续往后走（待退还 → 已退还 / 部分扣除 / 纠纷中），
    // 不再给「改回已缴纳 / 无押金」的回头路 —— 那等于把一次退租撤销掉。
    //
    // 纠纷中不一样（口径）：押金可以改回「已缴纳 / 无押金」（比如房东其实
    // 没收这笔钱），但房源仍然留在纠纷里 —— 押金只是一笔钱的状态，
    // 拽不动房源状态（见 `propertyStatusAfterDeposit`），要收尾走「退租」页。
    final locked = property.status == PropertyStatus.ended;
    final inDispute = property.status == PropertyStatus.dispute;
    bool blocked(DepositStatus status) =>
        locked &&
        (status == DepositStatus.paid || status == DepositStatus.none);

    return ZScreen(
      child: Column(
        children: [
          const ZAppBar(title: '押金追踪', leading: ZBackButton()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(Z.rLg),
                    border: Border.all(color: fg.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            switch (deposit.status) {
                              DepositStatus.none => Icons.block_outlined,
                              DepositStatus.paid => Icons.savings_outlined,
                              DepositStatus.toBeReturned =>
                                Icons.hourglass_bottom_rounded,
                              DepositStatus.partiallyDeducted =>
                                Icons.content_cut_rounded,
                              DepositStatus.returned => Icons.verified_outlined,
                              DepositStatus.inDispute => Icons.gavel_outlined,
                            },
                            size: 19,
                            color: fg,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            deposit.status.label,
                            style: ZText.label.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: fg,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        property.contract.deposit > 0
                            ? fmtMoney(property.contract.deposit)
                            : '未填写',
                        style: ZText.display.copyWith(fontSize: 30),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        deposit.status.hint,
                        style: ZText.caption.copyWith(
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                // 金额是 0 时别让人对着「¥0」发愣：说清去哪儿补
                if (property.contract.deposit <= 0) ...[
                  const ZHintBar(
                    text: '还没填押金金额：去「编辑房源 → 押金金额」补上，'
                        '这里才能追踪退还进度。',
                    tone: ZTone.warn,
                    icon: Icons.edit_outlined,
                  ),
                  const SizedBox(height: 4),
                ],
                const ZSectionTitle(title: '更新押金状态', icon: Icons.sync_alt),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final status in DepositStatus.values)
                      ChoiceChip(
                        label: Text(status.label),
                        selected: deposit.status == status,
                        // 已退租的房子不摆回头路：这两项点了也没用
                        // （纠纷中还留着，点完房源状态一动不动）
                        onSelected: blocked(status)
                            ? null
                            : (_) => _update(
                                context,
                                repository,
                                property,
                                status,
                              ),
                      ),
                  ],
                ),
                if (locked)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: ZHintBar(
                      text: '这套房已经退租：押金只能继续往后走'
                          '（待退还 / 已退还 / 部分扣除 / 纠纷中），'
                          '不能再改回「已缴纳 / 无押金」—— 那等于把退租撤销掉。',
                      icon: Icons.lock_outline_rounded,
                    ),
                  )
                else if (inDispute)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: ZHintBar(
                      text: '纠纷中的房子：押金可以改回「已缴纳 / 无押金」'
                          '（比如房东其实没收这笔钱），但房源仍然留在纠纷中，'
                          '不会恢复「租住中」；要收尾走「退租」页。',
                      icon: Icons.gavel_outlined,
                    ),
                  ),
                const ZSectionTitle(
                  title: '金额明细',
                  icon: Icons.receipt_long_outlined,
                ),
                ZCard(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: Column(
                    children: [
                      ZKv(
                        // 钱还在房东手里时说「已缴纳」，退租后才叫「应退」，
                        // 免得刚交完押金就看到一个「应退押金」的词
                        label: deposit.status == DepositStatus.paid
                            ? '已缴纳押金'
                            : '应退押金',
                        value: property.contract.deposit > 0
                            ? fmtMoney(property.contract.deposit)
                            : '未填写',
                        valueColor: property.contract.deposit > 0
                            ? Z.ink
                            : Z.ink3,
                      ),
                      ZKv(
                        label: '已退还',
                        value: deposit.returnedAmount > 0
                            ? '${fmtMoney(deposit.returnedAmount)}'
                                  '${deposit.returnedDate == null ? '' : ' · ${fmtDate(deposit.returnedDate!)}'}'
                            : '尚未退还',
                        valueColor: deposit.returnedAmount > 0
                            ? Z.okDeep
                            : Z.ink3,
                      ),
                      ZKv(
                        label: '被扣除',
                        value: deposit.deductedAmount > 0
                            ? fmtMoney(deposit.deductedAmount)
                            : '无',
                        valueColor: deposit.deductedAmount > 0
                            ? Z.dangerDeep
                            : Z.ink3,
                      ),
                      if (deposit.deductReason.isNotEmpty)
                        ZKv(label: '扣除理由', value: deposit.deductReason),
                      ZKv(
                        label: '维权备注',
                        value: deposit.disputeNote.isEmpty
                            ? '未填写'
                            : deposit.disputeNote,
                        divider: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 「退租」页记下的对接信息在这里也露一下：
                // 押金和交接是同一件事的两面，别让人以为填丢了
                if (deposit.handoverDone || deposit.handoverNote.isNotEmpty) ...[
                  const ZSectionTitle(
                    title: '与房东对接',
                    icon: Icons.handshake_outlined,
                  ),
                  ZCard(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: Column(
                      children: [
                        ZKv(
                          label: '交接',
                          value: deposit.handoverDone ? '已完成' : '未完成',
                          valueColor: deposit.handoverDone
                              ? Z.okDeep
                              : Z.ink3,
                          divider: deposit.handoverNote.isNotEmpty,
                        ),
                        if (deposit.handoverNote.isNotEmpty)
                          ZKv(
                            label: '交接备注',
                            value: deposit.handoverNote,
                            divider: false,
                          ),
                      ],
                    ),
                  ),
                ],
                Row(
                  children: [
                    Expanded(
                      child: ZButton(
                        label: '编辑金额',
                        style: ZButtonStyle.ghost,
                        onTap: () => _edit(context, repository, property),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ZButton(
                        label: '生成对比报告',
                        icon: Icons.compare_arrows_rounded,
                        onTap: () => zPush(
                          context,
                          ComparePage(propertyId: property.id),
                        ),
                      ),
                    ),
                  ],
                ),
                const ZSectionTitle(
                  title: '状态变更记录',
                  icon: Icons.history_rounded,
                ),
                ZCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (deposit.logs.isEmpty)
                        Text('暂无记录', style: ZText.caption),
                      for (final log in deposit.logs.reversed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: ZDot(
                                  color: ZTag.paletteOf(log.status.tone).$2,
                                  size: 6,
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      log.status.label,
                                      style: ZText.label.copyWith(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (log.note.isNotEmpty)
                                      Text(
                                        log.note,
                                        style: ZText.caption.copyWith(
                                          fontSize: 12,
                                        ),
                                      ),
                                    Text(
                                      fmtDateTime(log.time),
                                      style: ZText.mono.copyWith(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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

  Future<void> _update(
    BuildContext context,
    Repository repository,
    Property property,
    DepositStatus status,
  ) async {
    final deposit = property.deposit;
    if (deposit.status == status) return;
    // 兜底：已退租的房子不能改回「已缴纳 / 无押金」——
    // 那等于撤销退租。纠纷中不拦（改完房源状态也不会动）
    if (property.status == PropertyStatus.ended &&
        (status == DepositStatus.paid || status == DepositStatus.none)) {
      zToast(context, '这套房已经退租，不能改回「${status.label}」');
      return;
    }
    final logs = [
      ...deposit.logs,
      DepositLog(status: status, time: DateTime.now(), note: '手动更新状态'),
    ];
    var updated = deposit.copyWith(status: status, logs: logs);
    if (status == DepositStatus.returned) {
      updated = updated.copyWith(
        returnedAmount: property.contract.deposit,
        returnedDate: DateTime.now(),
      );
    }
    await repository.updateProperty(
      property.copyWith(
        deposit: updated,
        // 只有还在租住中的房子跟着押金联动；已退租 / 纠纷中只是押金记账，
        // 房源状态一动不动（房源状态的出口在「退租」页与「去纠纷」）
        status: propertyStatusAfterDeposit(property.status, status),
      ),
    );
    if (context.mounted) zToast(context, '已更新为「${status.label}」');
  }

  Future<void> _edit(
    BuildContext context,
    Repository repository,
    Property property,
  ) async {
    final deposit = property.deposit;
    final returned = TextEditingController(
      text: deposit.returnedAmount == 0
          ? ''
          : fmtAmount(deposit.returnedAmount),
    );
    final deducted = TextEditingController(
      text: deposit.deductedAmount == 0
          ? ''
          : fmtAmount(deposit.deductedAmount),
    );
    final reason = TextEditingController(text: deposit.deductReason);
    final note = TextEditingController(text: deposit.disputeNote);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, 20 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('编辑押金金额', style: ZText.title3.copyWith(fontSize: 17)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: returned,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '已退还金额',
                        prefixText: '¥ ',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: deducted,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '被扣除金额',
                        prefixText: '¥ ',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                decoration: const InputDecoration(
                  labelText: '扣除理由',
                  hintText: '房东给出的扣款理由',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '维权备注',
                  hintText: '你的说明与主张',
                ),
              ),
              const SizedBox(height: 16),
              ZButton(label: '保存', onTap: () => Navigator.of(ctx).pop(true)),
            ],
          ),
        );
      },
    );

    if (saved == true) {
      await repository.updateProperty(
        property.copyWith(
          deposit: deposit.copyWith(
            returnedAmount: double.tryParse(returned.text.trim()) ?? 0,
            deductedAmount: double.tryParse(deducted.text.trim()) ?? 0,
            deductReason: reason.text.trim(),
            disputeNote: note.text.trim(),
          ),
        ),
      );
      if (context.mounted) zToast(context, '已保存');
    }
    returned.dispose();
    deducted.dispose();
    reason.dispose();
    note.dispose();
  }
}
