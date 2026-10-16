import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../compare/compare_page.dart';
import '../expense/deposit_page.dart';
import '../expense/utility_page.dart';
import '../kit.dart';

/// 页面 · 退租（租住走完之后的结算）
///
/// 顺序就是真的退租顺序：
/// 1. 先确认该留的证据都留了（退租取证、最后一次抄表）；
/// 2. 再说押金：房东退了没有、退了多少、扣了什么；
/// 3. 最后记下跟房东的对接（钥匙、水电燃气结清、验收）。
///
/// 点「完成退租」把房源转成「已退租」——这是房源状态唯一的正常出口，
/// 建房源时不再手选状态了。
class MoveOutPage extends StatefulWidget {
  const MoveOutPage({super.key, required this.propertyId});

  final String propertyId;

  @override
  State<MoveOutPage> createState() => _MoveOutPageState();
}

class _MoveOutPageState extends State<MoveOutPage> {
  final TextEditingController _returned = TextEditingController();
  final TextEditingController _deducted = TextEditingController();
  final TextEditingController _deductReason = TextEditingController();
  final TextEditingController _handoverNote = TextEditingController();

  /// 押金怎么处理。可选范围见 [_choices]（按当前状态过滤，和押金追踪页同一套规则）
  DepositStatus _deposit = DepositStatus.toBeReturned;
  bool _handoverDone = false;
  bool _busy = false;

  /// 退租这一步可能出现的押金结果（三个里再按当前状态筛）
  /// 顺序按押金的流转走：待退还 → 部分扣除 → 已退还
  static const List<DepositStatus> _allChoices = [
    DepositStatus.toBeReturned,
    DepositStatus.partiallyDeducted,
    DepositStatus.returned,
  ];

  /// 这一页实际能选的结果：只留「从这个押金状态往前走」走得通的
  /// （口径见 canSwitchDeposit，和押金追踪页共用一套判断）
  List<DepositStatus> _choices = const [];

  @override
  void initState() {
    super.initState();
    final property = context.read<Repository>().propertyById(widget.propertyId);
    if (property == null) return;
    final deposit = property.deposit;
    _choices = _allChoices
        .where((status) => canSwitchDeposit(deposit.status, status))
        .toList();
    if (_choices.contains(deposit.status)) {
      _deposit = deposit.status;
    } else if (_choices.isNotEmpty) {
      _deposit = _choices.first;
    }
    _returned.text = deposit.returnedAmount > 0
        ? fmtAmount(deposit.returnedAmount)
        : (deposit.status == DepositStatus.returned && property.contract.deposit > 0
              ? fmtAmount(property.contract.deposit)
              : '');
    _deducted.text = deposit.deductedAmount > 0
        ? fmtAmount(deposit.deductedAmount)
        : '';
    _deductReason.text = deposit.deductReason;
    _handoverNote.text = deposit.handoverNote;
    _handoverDone = deposit.handoverDone;
  }

  @override
  void dispose() {
    for (final controller in [
      _returned,
      _deducted,
      _deductReason,
      _handoverNote,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final property = repository.propertyById(widget.propertyId);
    if (property == null) return const ZScreen(child: SizedBox.shrink());
    final hasDeposit = property.contract.deposit > 0;
    /// 押金已经在「押金追踪」里记过结果（待退还 / 部分扣除 / 已退还）：
    /// 这一页只把它带过去收尾，不再问一遍「房东退了吗」
    /// （这页没什么可选的，比如无押金的房子，也按「不用问」处理）
    final depositSettled =
        _choices.isEmpty || _allChoices.contains(property.deposit.status);
    final moveOutPhotos = repository.photoCountOf(
      property.id,
      phase: PhotoPhase.moveOut,
    );
    final recordedThisMonth =
        repository.utilityOfMonth(property.id, monthKey(DateTime.now())) !=
        null;

    return ZScreen(
      bottomBar: ZBottomBar(
        child: ZButton(
          label: property.status == PropertyStatus.active
              ? '完成退租'
              : '保存退租信息',
          onTap: _busy ? null : _finish,
        ),
      ),
      child: Column(
        children: [
          const ZAppBar(title: '退租', leading: ZBackButton()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                // 这次退租的全貌：住了多久、每月多少、押金多少
                ZHintBar(
                  text: '${fmtDate(property.contract.moveInDate)} 入住 · '
                      '${stayDurationLabel(property.contract.moveInDate)} · '
                      '月租 ${fmtMoney(property.contract.monthlyRent)}'
                      '${hasDeposit ? ' · 押金 ${fmtMoney(property.contract.deposit)}' : ''}',
                  icon: Icons.insights_outlined,
                ),
                const ZSectionTitle(
                  title: '退租前确认',
                  icon: Icons.checklist_rounded,
                ),
                ZCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      ZListRow(
                        icon: Icons.compare_arrows_rounded,
                        title: '退租取证',
                        subtitle: moveOutPhotos > 0
                            ? '$moveOutPhotos 张退租照片已留'
                            : '还没拍退租照片：拍照对比后押金才有据可依',
                        trailing: _ReadyPill(ok: moveOutPhotos > 0),
                        onTap: () => zPush(
                          context,
                          ComparePage(propertyId: property.id),
                        ),
                      ),
                      ZListRow(
                        icon: Icons.bolt_outlined,
                        title: '最后一次抄表',
                        subtitle: recordedThisMonth
                            ? '本月水电已记录'
                            : '本月还没抄表：把最后的水电读数留下来',
                        trailing: _ReadyPill(ok: recordedThisMonth),
                        onTap: () => zPush(
                          context,
                          UtilityPage(propertyId: property.id),
                        ),
                        divider: false,
                      ),
                    ],
                  ),
                ),
                if (hasDeposit) ...[
                  const ZSectionTitle(
                    title: '押金',
                    icon: Icons.savings_outlined,
                  ),
                  ZCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ZKv(
                          label: '合同押金',
                          value: fmtMoney(property.contract.deposit),
                          valueColor: Z.ink,
                          divider: false,
                        ),
                        const SizedBox(height: 10),
                        // 押金已经在「押金追踪」里记过结果了：这一页只回显，
                        // 不再问一遍「房东退了吗」—— 两处都能改只会互相覆盖，
                        // 用户也得多填一次
                        if (depositSettled) ...[
                          Row(
                            children: [
                              ZTag(
                                label: property.deposit.status.label,
                                tone: property.deposit.status.tone,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  depositLine(property),
                                  style: ZText.caption.copyWith(height: 1.5),
                                ),
                              ),
                            ],
                          ),
                          if (property.deposit.deductReason.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              '扣除理由：${property.deposit.deductReason}',
                              style: ZText.caption.copyWith(height: 1.5),
                            ),
                          ],
                          const SizedBox(height: 10),
                          ZButton(
                            label: '去押金追踪',
                            style: ZButtonStyle.ghost,
                            icon: Icons.savings_outlined,
                            onTap: () => zPush(
                              context,
                              DepositPage(propertyId: property.id),
                            ),
                          ),
                        ],
                        if (!depositSettled)
                          Text(
                            '房东退了吗',
                            style: ZText.label.copyWith(fontSize: 13),
                          ),
                        if (!depositSettled) const SizedBox(height: 8),
                        if (!depositSettled) ZChips<DepositStatus>(
                          options: _choices,
                          value: _deposit,
                          emphasize: true,
                          padding: EdgeInsets.zero,
                          labelOf: (status) => status.label,
                          onChanged: (status) =>
                              setState(() => _deposit = status),
                        ),
                        if (!depositSettled) const SizedBox(height: 14),
                        if (!depositSettled &&
                            _deposit == DepositStatus.returned)
                          TextField(
                            controller: _returned,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: '已退还给你的金额',
                              prefixText: '¥ ',
                              helperText:
                                  '押金 ${fmtMoney(property.contract.deposit)} 全额退还就照着填',
                            ),
                          ),
                        if (!depositSettled &&
                            _deposit == DepositStatus.partiallyDeducted) ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _deducted,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    labelText: '被扣除',
                                    prefixText: '¥ ',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(11),
                                  decoration: BoxDecoration(
                                    color: Z.brandTint,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('实际该退', style: ZText.small),
                                      const SizedBox(height: 2),
                                      Text(
                                        fmtMoney(_stillOwed(property)),
                                        style: ZText.title4.copyWith(
                                          color: Z.brand,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _deductReason,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: '扣除理由',
                              hintText: '房东怎么说就怎么写，维权时这就是证据',
                            ),
                          ),
                        ],
                        if (!depositSettled &&
                            _deposit == DepositStatus.toBeReturned)
                          Text(
                            '押金还没到手也能先完成退租：会照实记成「未退还」，'
                            '等房东退到手再回来补上金额。',
                            style: ZText.small.copyWith(height: 1.5),
                          ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ],
                const ZSectionTitle(
                  title: '与房东对接',
                  icon: Icons.handshake_outlined,
                ),
                ZCard(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _handoverDone,
                        activeThumbColor: Z.brand,
                        onChanged: (value) =>
                            setState(() => _handoverDone = value),
                        title: const Text('对接完成'),
                        subtitle: Text(
                          '钥匙交还、水电燃气结清、退租验收都谈妥了',
                          style: ZText.caption,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _handoverNote,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: '交接备注',
                          hintText: '口头约定、遗留问题，比如「墙面划痕双方确认不算」',
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ZHintBar(text: _hintText(property), tone: _hintTone(property)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 部分扣除时实际该退多少：合同押金 − 被扣金额，最低 0
  double _stillOwed(Property property) {
    final deducted = double.tryParse(_deducted.text.trim()) ?? 0;
    final left = property.contract.deposit - deducted;
    return left > 0 ? left : 0;
  }

  /// 底部那句话：同一个页面会被三种状态用到，口径得跟着状态走 ——
  /// 纠纷中的房子不该再被劝「去纠纷」，已退租的房子只剩改记录
  String _hintText(Property property) => switch (property.status) {
    PropertyStatus.dispute =>
      '这套房正在维权：押金结算清楚后点「完成退租」，'
          '对比报告与催告函在房源详情页的「去维权」里。',
    PropertyStatus.ended => _handoverDone
        ? '退租记录已归档：这里改的是记录本身，改完点「保存退租信息」即可。'
        : '退租记录已归档：交接还没记全就补上，改完点「保存退租信息」。',
    // 押金没到手也算正常退租：先把房源收尾，钱慢慢催
    _ when _deposit == DepositStatus.toBeReturned && !_handoverDone =>
      '押金还没到手也能先完成退租：会记成「未退还」，退到手再回来补金额。',
    _ => '点「完成退租」后，房源会转成「已退租」，照片与合同只读归档；'
        '押金扣得不服气，就在房源详情里用「去纠纷」标记。',
  };

  ZTone _hintTone(Property property) {
    if (property.status == PropertyStatus.dispute) return ZTone.warn;
    if (property.status == PropertyStatus.ended) return ZTone.brand;
    return _handoverDone ? ZTone.brand : ZTone.warn;
  }

  Future<void> _finish() async {
    final repository = context.read<Repository>();
    final property = repository.propertyById(widget.propertyId);
    if (property == null) return;

    final contractDeposit = property.contract.deposit;
    if (contractDeposit > 0 && _deposit == DepositStatus.partiallyDeducted) {
      if (_deducted.text.trim().isEmpty ||
          (double.tryParse(_deducted.text.trim()) ?? 0) <= 0) {
        zToast(context, '填一下被扣了多少钱');
        return;
      }
      if (_deductReason.text.trim().isEmpty) {
        zToast(context, '写一下房东给的扣除理由');
        return;
      }
    }

    // 退租不可逆（房源转「已退租」、资料进只读归档），点之前再确认一次
    if (property.status == PropertyStatus.active) {
      // 「退租前确认」里那两件没做的事，在确认框里点出来 ——
      // 退完就进只读归档，这两项再也补不了
      final missing = <String>[
        if (repository.photoCountOf(property.id, phase: PhotoPhase.moveOut) == 0)
          '退租取证',
        if (repository.utilityOfMonth(property.id, monthKey(DateTime.now())) ==
            null)
          '最后一次抄表',
      ];
      final ok = await zConfirm(
        context,
        title: '完成退租？',
        message: missing.isEmpty
            ? '确认后房源转入「已退租」，照片和合同变成只读归档'
                  '${contractDeposit > 0 ? '，押金按上面记的结果带过去' : ''}。'
            : '有 ${missing.length} 项还没做：${missing.join('、')}。'
                  '退租之后这套房就只读了，这两项再也补不了。',
        confirmText: missing.isEmpty ? '确认退租' : '仍要退租',
        cancelText: missing.isEmpty ? '再看看' : '回去补',
        danger: missing.isNotEmpty,
      );
      if (!ok || !mounted) return;
    }

    setState(() => _busy = true);
    final deposit = property.deposit;
    final now = DateTime.now();
    var returned = deposit.returnedAmount;
    var deducted = 0.0;
    var deductReason = deposit.deductReason;
    DateTime? returnedDate = deposit.returnedDate;
    var status = deposit.status;
    var summary = '完成退租';

    if (contractDeposit > 0) {
      status = _deposit;
      if (_deposit == DepositStatus.returned) {
        returned = double.tryParse(_returned.text.trim()) ?? contractDeposit;
        deducted = 0;
        deductReason = '';
        returnedDate ??= now;
        summary = '完成退租：押金 ${fmtMoney(returned)} 已退还';
      } else if (_deposit == DepositStatus.partiallyDeducted) {
        deducted = double.tryParse(_deducted.text.trim()) ?? 0;
        returned = _stillOwed(property);
        deductReason = _deductReason.text.trim();
        returnedDate ??= now;
        summary =
            '完成退租：退还 ${fmtMoney(returned)}'
            '，被扣 ${fmtMoney(deducted)}（$deductReason）';
      } else {
        summary = '完成退租：押金 ${fmtMoney(contractDeposit)} 未退还';
      }
    }

    try {
      await repository.updateProperty(
        property.copyWith(
          // 房源状态只有这一条正常出口：建房源时不再手选状态
          status: PropertyStatus.ended,
          deposit: deposit.copyWith(
            status: status,
            returnedAmount: returned,
            returnedDate: returnedDate,
            deductedAmount: deducted,
            deductReason: deductReason,
            handoverDone: _handoverDone,
            handoverNote: _handoverNote.text.trim(),
            logs: [
              ...deposit.logs,
              DepositLog(status: status, time: now, note: summary),
            ],
          ),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      zToast(context, '已完成退租，房源转入「已退租」');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// 退租前确认那一列右侧的「已留 / 还没」标记
class _ReadyPill extends StatelessWidget {
  const _ReadyPill({required this.ok});

  final bool ok;

  @override
  Widget build(BuildContext context) => ZPill(
    label: ok ? '已留' : '还没',
    background: ZTag.paletteOf(ok ? ZTone.ok : ZTone.warn).$1,
    foreground: ZTag.paletteOf(ok ? ZTone.ok : ZTone.warn).$2,
  );
}
