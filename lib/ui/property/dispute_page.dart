import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';

/// 页面 · 标记纠纷（「去纠纷」的落点）
///
/// 这不是点一下就完事的开关：标记纠纷时要顺手留下维权最关键的一句话
/// （为什么起争议）、被扣了多少钱，以及「手里有什么证据」的现状。
/// 标记之后房源转入「纠纷中」：资料变只读，但沟通记录还能继续记（留证）。
class DisputePage extends StatefulWidget {
  const DisputePage({super.key, required this.propertyId});

  final String propertyId;

  @override
  State<DisputePage> createState() => _DisputePageState();
}

class _DisputePageState extends State<DisputePage> {
  final TextEditingController _reason = TextEditingController();
  final TextEditingController _deducted = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final property = context.read<Repository>().propertyById(widget.propertyId);
    if (property == null) return;
    final deposit = property.deposit;
    _reason.text = deposit.disputeNote;
    if (deposit.deductedAmount > 0) {
      _deducted.text = fmtAmount(deposit.deductedAmount);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    _deducted.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final property = repository.propertyById(widget.propertyId);
    if (property == null) return const ZScreen(child: SizedBox.shrink());

    final photos = repository.photosOf(property.id);
    final moveOutPhotos = photos
        .where((photo) => photo.phase == PhotoPhase.moveOut)
        .length;
    final comms = repository.commsOf(property.id).length;
    final rules = repository.rulesOf(property.id).length;

    return ZScreen(
      bottomBar: ZBottomBar(
        child: ZButton(
          label: '确认标记纠纷',
          danger: true,
          onTap: _busy ? null : _submit,
        ),
      ),
      child: Column(
        children: [
          const ZAppBar(title: '标记纠纷', leading: ZBackButton()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                const ZHintBar(
                  text: '押金被无理扣除、房东失联这类情况都算。'
                      '写清原因，这就是维权材料里的第一条。',
                  tone: ZTone.danger,
                  icon: Icons.gavel_outlined,
                ),
                const ZSectionTitle(
                  title: '为什么纠纷',
                  icon: Icons.edit_note_rounded,
                ),
                ZCard(
                  child: TextField(
                    controller: _reason,
                    maxLines: 4,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: '比如：以墙面划痕为由扣了 2000 元，没给照片',
                    ),
                  ),
                ),
                const ZSectionTitle(
                  title: '被扣了多少',
                  icon: Icons.money_off_rounded,
                ),
                ZCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _deducted,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '房东扣掉的金额',
                          prefixText: '¥ ',
                          helperText: property.contract.deposit > 0
                              ? '合同押金 ${fmtMoney(property.contract.deposit)}'
                              : '合同里没写押金金额',
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
                const ZSectionTitle(
                  title: '手里的证据',
                  icon: Icons.folder_open_outlined,
                ),
                ZCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      _EvidenceRow(
                        label: '退租照片',
                        ready: moveOutPhotos > 0,
                        hint: moveOutPhotos > 0
                            ? '$moveOutPhotos 张已留'
                            : '还没拍：对比报告靠它',
                      ),
                      _EvidenceRow(
                        label: '沟通记录',
                        ready: comms > 0,
                        hint: comms > 0
                            ? '$comms 条留痕'
                            : '还没有：纠纷期间也能继续记',
                      ),
                      _EvidenceRow(
                        label: '房东要求 / 特殊条款',
                        ready: rules > 0,
                        hint: rules > 0 ? '$rules 条' : '没有记录过',
                        divider: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const ZHintBar(
                  text: '标记之后：这套房按「已经搬走、进入维权」处理 —— '
                      '合同、照片、抄表都变成只读，不再记租金与抄表；'
                      '沟通记录还能继续补（那是维权留证）。',
                  icon: Icons.lock_outline_rounded,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final repository = context.read<Repository>();
    final property = repository.propertyById(widget.propertyId);
    if (property == null) return;

    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      zToast(context, '写一下纠纷原因');
      return;
    }
    final deducted = double.tryParse(_deducted.text.trim()) ?? 0;

    final deposit = property.deposit;
    // 押金状态只能往前走：已经「已退还」的房子押金流程走完了，
    // 不能再被标成纠纷（部分扣除 → 纠纷中 是允许的：不服这笔扣款就继续维权）
    if (!canSwitchDeposit(deposit.status, DepositStatus.inDispute)) {
      zToast(context, '押金已经退到手了：这套房的押金流程走完了，不能再标押金纠纷');
      return;
    }
    setState(() => _busy = true);
    try {
      await repository.updateProperty(
        property.copyWith(
          status: PropertyStatus.dispute,
          deposit: deposit.copyWith(
            status: DepositStatus.inDispute,
            disputeNote: reason,
            // 只覆盖「填了数字」的情况，别把已有的金额清成 0
            deductedAmount: deducted > 0 ? deducted : deposit.deductedAmount,
            logs: [
              ...deposit.logs,
              DepositLog(
                status: DepositStatus.inDispute,
                time: DateTime.now(),
                note: '标记纠纷：$reason',
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      zToast(context, '已标记为纠纷中，维权材料都在这套房源里');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// 「手里的证据」一行：够 / 还缺，用一处文案说清
class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({
    required this.label,
    required this.ready,
    required this.hint,
    this.divider = true,
  });

  final String label;
  final bool ready;
  final String hint;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final tone = ready ? ZTone.ok : ZTone.warn;
    return ZListRow(
      title: label,
      subtitle: hint,
      trailing: ZPill(
        label: ready ? '有了' : '还缺',
        background: ZTag.paletteOf(tone).$1,
        foreground: ZTag.paletteOf(tone).$2,
      ),
      divider: divider,
    );
  }
}
