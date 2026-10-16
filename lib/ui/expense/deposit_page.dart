import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';

/// 「更新押金状态」里能选的就这四种 —— 押金本身只有这些状态：
/// 无押金不在这里（那是「要不要押金」那一问的事），
/// 纠纷中也不在这里（它是房源状态，走详情页的「去纠纷」）。
const List<DepositStatus> _depositStates = [
  DepositStatus.paid,
  DepositStatus.toBeReturned,
  DepositStatus.partiallyDeducted,
  DepositStatus.returned,
];

/// 页面 15 · 押金追踪
///
/// 可选状态就四个（已缴纳 / 待退还 / 部分扣除 / 已退还），而且**只能往前走**
/// （见 [canSwitchDeposit]）；「要不要押金」在无押金时用页顶那张提问卡解决，
/// 纠纷中是房源状态（走详情页的「去纠纷」）。
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
    // 押金只是一笔钱的状态：改它从来拽不动房源状态（见 logic.dart 那条口径），
    // 房源状态的出口只有「退租」页的完成退租与详情页的「去纠纷」。
    final locked = property.status == PropertyStatus.ended;
    final inDispute = property.status == PropertyStatus.dispute;
    /// 只有还在租住中的房子能改押金金额（已退租 / 纠纷中是只读归档）
    final editable = canEditProperty(property);
    final noDeposit = deposit.status == DepositStatus.none;
    final amountMissing = property.contract.deposit <= 0;
    /// 不需要押金（且还能改）时，页面只留「要不要押金」这一问 + 金额输入框：
    /// 押金状态、金额明细都属于「有押金」的房子，等他改成需要押金再出现。
    final minimal = editable && noDeposit;
    // 合同里没填押金金额时谈不上「扣了多少」：先补金额，别记一笔扣款
    final canDeduct = property.contract.deposit > 0;
    // 能不能点这个状态：只能往后走（见 canSwitchDeposit），
    // 到头了（已退还）就都不能点；没金额时「部分扣除」也不给点
    bool blocked(DepositStatus status) =>
        !canSwitchDeposit(deposit.status, status) ||
        (status == DepositStatus.partiallyDeducted && !canDeduct);

    return ZScreen(
      child: Column(
        children: [
          const ZAppBar(title: '押金追踪', leading: ZBackButton()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                // 不需要押金：状态卡换成一张提问卡，下面那几段都不摆
                if (minimal)
                  _NoDepositPrompt(property: property, repository: repository)
                else
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
                        // 「不需要押金」的房子别摆一个「未填写」，那是两回事
                        noDeposit
                            ? '不需要押金'
                            : amountMissing
                            ? '未填写'
                            : fmtMoney(property.contract.deposit),
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
                // 押金金额这一格：本来就没押金的话，给一个「改成需要押金」的入口，
                // 而不是催人去「编辑房源」绕一圈；该有金额却没填的，在这儿补
                if (!minimal && editable && amountMissing)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ZHintBar(
                      text: '还没填押金金额：补上之后，这里才能追踪退还进度。',
                      tone: ZTone.warn,
                      icon: Icons.edit_outlined,
                      trailing: TextButton(
                        onPressed: () =>
                            _editAmount(context, repository, property),
                        child: const Text('填金额'),
                      ),
                    ),
                  ),
                if (!minimal) const ZSectionTitle(
                  title: '更新押金状态',
                  icon: Icons.sync_alt,
                ),
                if (!minimal) Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final status in _depositStates)
                      ChoiceChip(
                        label: Text(status.label),
                        selected: deposit.status == status,
                        // 已退租的房子不摆回头路：点「已缴纳」也没用
                        // （纠纷中的房子还能改这四种状态，改完房源状态一动不动）
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
                if (!minimal && deposit.status == DepositStatus.returned)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: ZHintBar(
                      text: '押金已经退到手：这套房的押金流程走完了，状态不用再改。',
                      tone: ZTone.ok,
                      icon: Icons.verified_outlined,
                    ),
                  )
                else if (!minimal && locked)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: ZHintBar(
                      text: '这套房已经退租：押金状态只能继续往后走'
                          '（待退还 / 部分扣除 / 已退还），不能回头改回去。',
                      icon: Icons.lock_outline_rounded,
                    ),
                  )
                else if (!minimal && inDispute)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: ZHintBar(
                      text: '纠纷中的房子：押金状态只能继续往后走'
                          '（部分扣除 / 已退还），房源仍然留在纠纷中；'
                          '要收尾走「退租」页。',
                      icon: Icons.gavel_outlined,
                    ),
                  ),
                if (!minimal) const ZSectionTitle(
                  title: '金额明细',
                  icon: Icons.receipt_long_outlined,
                ),
                if (!minimal) ZCard(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: Column(
                    children: [
                      ZKv(
                        // 钱还在房东手里时说「已缴纳」，退租后才叫「应退」，
                        // 免得刚交完押金就看到一个「应退押金」的词
                        label: deposit.status == DepositStatus.paid
                            ? '已缴纳押金'
                            : '应退押金',
                        value: noDeposit
                            ? '无需押金'
                            : amountMissing
                            ? '未填写'
                            : fmtMoney(property.contract.deposit),
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
    // 只许往前走：回头（改回已缴纳）和「已退还之后再改」都拦在这儿
    if (!canSwitchDeposit(deposit.status, status)) {
      zToast(context, '押金状态只能继续往后走，不能改成「${status.label}」');
      return;
    }
    // 合同押金还没填（0）时没有「扣了多少」可言：让他先去补金额
    if (status == DepositStatus.partiallyDeducted &&
        property.contract.deposit <= 0) {
      zToast(context, '先在「编辑房源 → 押金金额」补上押金金额，才能记部分扣除');
      return;
    }
    // 「部分扣除」要先问清楚扣了多少、为什么扣、备注 —— 这些就是金额明细的内容
    if (status == DepositStatus.partiallyDeducted) {
      await _applyPartialDeduction(context, repository, property);
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
        // 房源状态一动不动：押金只是记账，改它不等于退租
        // （房源状态的出口只有「退租」页的完成退租与详情页的「去纠纷」）
        status: property.status,
      ),
    );
    if (context.mounted) zToast(context, '已更新为「${status.label}」');
  }

  /// 填「押金金额」（合同里约定的那个数）。
  ///
  /// 只有「这套房要押金、但金额还没填」那条提示会走到这儿（不需要押金的房子
  /// 走页顶那张提问卡，那儿会连状态一起记成「已缴纳」）。
  Future<void> _editAmount(
    BuildContext context,
    Repository repository,
    Property property,
  ) async {
    // 和别处的弹窗一样：不建 TextEditingController —— 退场动画期间 dispose 掉
    // 会让输入框重建时直接抛「used after being disposed」，初值走 initialValue
    var typed = property.contract.deposit > 0
        ? fmtAmount(property.contract.deposit)
        : '';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, 20 + bottom),
          // 键盘顶起来时内容要能滚（不然小屏上会 RenderFlex overflowed）
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('押金金额', style: ZText.title3.copyWith(fontSize: 17)),
                const SizedBox(height: 6),
                Text('合同里约定的押金数额。', style: ZText.caption),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: typed,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  onChanged: (text) => typed = text,
                  decoration: const InputDecoration(
                    labelText: '押金金额',
                    prefixText: '¥ ',
                  ),
                ),
                const SizedBox(height: 16),
                ZButton(label: '保存', onTap: () => Navigator.of(ctx).pop(true)),
              ],
            ),
          ),
        );
      },
    );
    if (saved != true) return;
    final amount = double.tryParse(typed.trim()) ?? 0;
    if (amount <= 0) {
      if (context.mounted) zToast(context, '押金金额要大于 0');
      return;
    }
    await repository.updateProperty(
      property.copyWith(
        contract: property.contract.copyWith(deposit: amount),
        // 金额是合同里的数，状态与日志都不动（状态只能往前走，见 _canMoveTo）
        status: property.status,
      ),
    );
    if (context.mounted) zToast(context, '已保存押金金额');
  }

  /// 选「部分扣除」时问一次：被扣了多少、房东为什么扣、你自己留一句维权备注。
  ///
  /// 这三个字段就是「金额明细」里的内容；存完立刻落盘并按仓库通知重画页面。
  /// 输入框用 initialValue + 局部变量收，不建 TextEditingController ——
  /// 弹层退场动画期间 dispose 掉会抛「used after being disposed」，
  /// 那一帧报错会让页面停在旧数据上（就是「保存后不更新」那个毛病）。
  Future<void> _applyPartialDeduction(
    BuildContext context,
    Repository repository,
    Property property,
  ) async {
    final deposit = property.deposit;
    final contractDeposit = property.contract.deposit;
    var deductedText = deposit.deductedAmount > 0
        ? fmtAmount(deposit.deductedAmount)
        : '';
    var reasonText = deposit.deductReason;
    var noteText = deposit.disputeNote;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, 20 + bottom),
          // 键盘顶起来时内容要能滚：小屏 + 三个输入框会把这张弹层顶出去
          // （溢出会报 RenderFlex overflowed，debug 下就是一片红）
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('押金部分扣除', style: ZText.title3.copyWith(fontSize: 17)),
                const SizedBox(height: 6),
                Text(
                  contractDeposit > 0
                      ? '押金 ${fmtMoney(contractDeposit)}：'
                            '房东扣了多少、为什么扣，记下来留证据。'
                      : '房东扣了多少、为什么扣，记下来留证据。',
                  style: ZText.caption.copyWith(height: 1.5),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: deductedText,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  onChanged: (text) => deductedText = text,
                  decoration: const InputDecoration(
                    labelText: '扣除多少钱',
                    prefixText: '¥ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: reasonText,
                  onChanged: (text) => reasonText = text,
                  decoration: const InputDecoration(
                    labelText: '扣除理由',
                    hintText: '房东给出的扣款理由',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: noteText,
                  maxLines: 3,
                  onChanged: (text) => noteText = text,
                  decoration: const InputDecoration(
                    labelText: '维权备注',
                    hintText: '你的说明与主张',
                  ),
                ),
                const SizedBox(height: 16),
                ZButton(label: '保存', onTap: () => Navigator.of(ctx).pop(true)),
              ],
            ),
          ),
        );
      },
    );
    if (saved != true) return;

    final deducted = double.tryParse(deductedText.trim()) ?? 0;
    if (deducted <= 0) {
      if (context.mounted) zToast(context, '先填扣除金额（要大于 0）');
      return;
    }
    if (contractDeposit > 0 && deducted > contractDeposit) {
      if (context.mounted) {
        zToast(context, '扣除金额不能超过押金 ${fmtMoney(contractDeposit)}');
      }
      return;
    }
    // 剩下的那部分算「已退还」：金额明细里「押金退还 ¥X · 扣除 ¥Y」才对得上
    final returned = contractDeposit > deducted
        ? contractDeposit - deducted
        : 0.0;
    await repository.updateProperty(
      property.copyWith(
        deposit: deposit.copyWith(
          status: DepositStatus.partiallyDeducted,
          deductedAmount: deducted,
          deductReason: reasonText.trim(),
          disputeNote: noteText.trim(),
          returnedAmount: returned,
          logs: [
            ...deposit.logs,
            DepositLog(
              status: DepositStatus.partiallyDeducted,
              time: DateTime.now(),
              note: '部分扣除 ${fmtMoney(deducted)}'
                  '${reasonText.trim().isEmpty ? '' : ' · ${reasonText.trim()}'}',
            ),
          ],
        ),
        // 房源状态一动不动：押金只是记账
        status: property.status,
      ),
    );
    if (!context.mounted) return;
    zToast(context, '已记成「部分扣除」· 扣除 ${fmtMoney(deducted)}');
  }
}

/// 「无押金」房子的入口：先摆明现状（当前房源暂不需要押金），再问一句要不要改成
/// 「需要押金」，金额就填在这儿 —— 填完后状态记成「已缴纳」，之后能追踪退还进度。
///
/// 单独做成一个有状态的组件：输入框需要常驻在自己这层（页面本身是 StatelessWidget，
/// 弹层里又不能用 controller —— 退场动画期间 dispose 会报 used after being disposed）。
class _NoDepositPrompt extends StatefulWidget {
  const _NoDepositPrompt({required this.property, required this.repository});

  final Property property;
  final Repository repository;

  @override
  State<_NoDepositPrompt> createState() => _NoDepositPromptState();
}

class _NoDepositPromptState extends State<_NoDepositPrompt> {
  final TextEditingController _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      zToast(context, '先填押金金额（要大于 0）');
      return;
    }
    final property = widget.property;
    final deposit = property.deposit;
    await widget.repository.updateProperty(
      property.copyWith(
        contract: property.contract.copyWith(deposit: amount),
        deposit: deposit.copyWith(
          status: DepositStatus.paid,
          logs: [
            ...deposit.logs,
            DepositLog(
              status: DepositStatus.paid,
              time: DateTime.now(),
              note: '登记押金金额 ${fmtMoney(amount)}',
            ),
          ],
        ),
        // 房源状态一动不动：押金只是记账
        status: property.status,
      ),
    );
    if (!mounted) return;
    zToast(context, '已记成「已缴纳」· ${fmtMoney(amount)}');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ZCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 17,
                  color: Z.brand,
                ),
                const SizedBox(width: 7),
                Text('当前房源暂不需要押金', style: ZText.bodyStrong),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '如果房东其实收了押金，填上金额就改成「需要押金」，'
              '状态会记成「已缴纳」，之后能追踪退还进度。',
              style: ZText.caption.copyWith(height: 1.5),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: '押金金额',
                      prefixText: '¥ ',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ZButton(
                  label: '改成需要押金',
                  expand: false,
                  width: 128,
                  height: 48,
                  onTap: _apply,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
