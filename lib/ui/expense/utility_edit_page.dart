import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';

/// 页面 13 · 抄表录入
class UtilityEditPage extends StatefulWidget {
  const UtilityEditPage({
    super.key,
    required this.propertyId,
    this.recordId,
    this.month,
  });

  final String propertyId;
  final String? recordId;

  /// 补录某个指定月份（从「全部抄表记录 → 某年」里点未记录的月份进来）。
  /// 不传就是本月；编辑已有记录时一律以记录自己的月份为准。
  final String? month;

  @override
  State<UtilityEditPage> createState() => _UtilityEditPageState();
}

class _UtilityEditPageState extends State<UtilityEditPage> {
  final TextEditingController _elecReading = TextEditingController();
  final TextEditingController _elecPrev = TextEditingController();
  final TextEditingController _elecPrice = TextEditingController();
  final TextEditingController _waterReading = TextEditingController();
  final TextEditingController _waterPrev = TextEditingController();
  final TextEditingController _waterPrice = TextEditingController();
  final TextEditingController _gasReading = TextEditingController();
  final TextEditingController _gasPrev = TextEditingController();
  final TextEditingController _gasPrice = TextEditingController();
  final TextEditingController _propertyFee = TextEditingController();
  final TextEditingController _networkFee = TextEditingController();
  final TextEditingController _note = TextEditingController();

  late String _month = widget.month ?? monthKey(DateTime.now());
  String? _photoRef;
  bool _useWater = true;
  bool _useElectricity = true;
  bool _useGas = false;

  /// 上一月没有对应读数（没有记录 / 记录里没这项），界面需要明确提示
  bool _elecPrevMissing = false;
  bool _waterPrevMissing = false;
  bool _gasPrevMissing = false;

  UtilityRecord? _existing;

  @override
  void initState() {
    super.initState();
    final repository = context.read<Repository>();
    final settings = repository.settings;
    _elecPrice.text = fmtAmount(settings.defaultElectricityPrice);
    _waterPrice.text = fmtAmount(settings.defaultWaterPrice);
    _gasPrice.text = fmtAmount(settings.defaultGasPrice);

    for (final record in repository.utilitiesOf(widget.propertyId)) {
      if (record.id == widget.recordId) {
        _existing = record;
        break;
      }
    }

    final existing = _existing;
    if (existing != null) {
      _month = existing.month;
      _photoRef = existing.photoRef;
      _note.text = existing.note;
      _propertyFee.text = existing.propertyFee == 0
          ? ''
          : fmtAmount(existing.propertyFee);
      _networkFee.text = existing.networkFee == 0
          ? ''
          : fmtAmount(existing.networkFee);
      final elec = existing.electricity;
      if (elec != null) {
        _elecReading.text = fmtAmount(elec.reading);
        _elecPrice.text = fmtAmount(elec.unitPrice);
      } else {
        _useElectricity = false;
      }
      final water = existing.water;
      if (water != null) {
        _waterReading.text = fmtAmount(water.reading);
        _waterPrice.text = fmtAmount(water.unitPrice);
      } else {
        _useWater = false;
      }
      final gas = existing.gas;
      if (gas != null) {
        _useGas = true;
        _gasReading.text = fmtAmount(gas.reading);
        _gasPrice.text = fmtAmount(gas.unitPrice);
      }
      // 上月读数以「日历上一月」的记录为准；
      // 没有上一月记录就标缺失，不再回退到本月记录自存的读数
      _syncPreviousReadings();
    } else {
      _syncPreviousReadings();
      // 上一月有燃气读数，说明这户在用燃气，默认打开
      if (_gasPrev.text.isNotEmpty) _useGas = true;
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _elecReading,
      _elecPrev,
      _elecPrice,
      _waterReading,
      _waterPrev,
      _waterPrice,
      _gasReading,
      _gasPrev,
      _gasPrice,
      _propertyFee,
      _networkFee,
      _note,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 上月读数（只读）：严格只取「日历上一月」那条记录里的读数。
  /// 没有上一月记录时：标记缺失（上月读数为空，用量 = 本月读数 − 0）。
  /// 不再回退到当前记录自存的读数，避免「上月读数 = 本月读数」。
  void _syncPreviousReadings() {
    final previous = previousUtilityOf(
      utilities: context.read<Repository>().utilitiesOf(widget.propertyId),
      propertyId: widget.propertyId,
      month: _month,
    );

    final elec = previous?.electricity;
    final water = previous?.water;
    final gas = previous?.gas;

    _elecPrevMissing = elec == null;
    _waterPrevMissing = water == null;
    _gasPrevMissing = gas == null;
    _elecPrev.text = elec == null ? '' : fmtAmount(elec.reading);
    _waterPrev.text = water == null ? '' : fmtAmount(water.reading);
    _gasPrev.text = gas == null ? '' : fmtAmount(gas.reading);
  }

  double _usage(TextEditingController reading, TextEditingController prev) {
    final current = double.tryParse(reading.text.trim()) ?? 0;
    final previous = double.tryParse(prev.text.trim()) ?? 0;
    final value = current - previous;
    return value > 0 ? value : 0;
  }

  /// 本月读数小于上月：可能是换表，也可能是抄错，需要明确提示
  bool _isReversed(
    TextEditingController reading,
    TextEditingController previous,
  ) {
    final current = double.tryParse(reading.text.trim());
    final prev = double.tryParse(previous.text.trim());
    if (current == null || prev == null || prev <= 0) return false;
    return current < prev;
  }

  @override
  Widget build(BuildContext context) {
    final previousLabel = monthLabel(previousMonthKey(_month));
    // 只读归档：已退租的房子只能看，不给提交
    final property = context.watch<Repository>().propertyById(
      widget.propertyId,
    );
    final editable = property == null || canAddUtility(property);
    return ZScreen(
      bottomBar: ZBottomBar(
        child: Row(
          children: [
            Expanded(
              child: ZButton(
                label: '取消',
                style: ZButtonStyle.ghost,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ZButton(label: '提交', onTap: editable ? _save : null),
            ),
          ],
        ),
      ),
      child: Column(
        children: [
          ZAppBar(
            leading: const ZBackButton(),
            title: _existing == null ? '抄表录入' : '编辑抄表记录',
          ),
          if (!editable)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ZHintBar(
                text: '这套房子已退租：抄表记录只能查看，不能再新增或修改。',
                icon: Icons.lock_outline_rounded,
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                ZField(
                  label: '所属月份',
                  // 月份不可改：新增时就是本月（或从年份页点进来的那个月），
                  // 编辑时锁定为这条记录的月份——避免一条记录被改到别的月份上
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Z.line3,
                      borderRadius: Z.radiusField,
                    ),
                    child: Row(
                      children: [
                        Text(
                          monthLabel(_month),
                          style: ZText.label.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        // 月份是锁定的：写清楚，别让人以为这里能点开选年月
                        const ZTag(
                          label: '不可修改',
                          icon: Icons.lock_outline_rounded,
                        ),
                      ],
                    ),
                  ),
                ),
                const ZHintBar(
                  text: '上月读数按「上一月」的抄表记录自动带入，不可修改；用量 = 本月读数 − 上月读数。',
                  icon: Icons.lock_outline_rounded,
                ),
                const SizedBox(height: 12),
                _MeterGroup(
                  title: '电表',
                  emoji: '⚡',
                  unit: 'kWh',
                  enabled: _useElectricity,
                  onToggle: (value) => setState(() => _useElectricity = value),
                  reading: _elecReading,
                  previous: _elecPrev,
                  previousMissing: _elecPrevMissing,
                  previousLabel: previousLabel,
                  reversed: _isReversed(_elecReading, _elecPrev),
                  price: _elecPrice,
                  usage: _usage(_elecReading, _elecPrev),
                  cost:
                      _usage(_elecReading, _elecPrev) *
                      (double.tryParse(_elecPrice.text.trim()) ?? 0),
                  onChanged: () => setState(() {}),
                ),
                _MeterGroup(
                  title: '水表',
                  emoji: '💧',
                  unit: 'm³',
                  enabled: _useWater,
                  onToggle: (value) => setState(() => _useWater = value),
                  reading: _waterReading,
                  previous: _waterPrev,
                  previousMissing: _waterPrevMissing,
                  previousLabel: previousLabel,
                  reversed: _isReversed(_waterReading, _waterPrev),
                  price: _waterPrice,
                  usage: _usage(_waterReading, _waterPrev),
                  cost:
                      _usage(_waterReading, _waterPrev) *
                      (double.tryParse(_waterPrice.text.trim()) ?? 0),
                  onChanged: () => setState(() {}),
                ),
                _MeterGroup(
                  title: '燃气表',
                  emoji: '🔥',
                  unit: 'm³',
                  enabled: _useGas,
                  onToggle: (value) => setState(() => _useGas = value),
                  reading: _gasReading,
                  previous: _gasPrev,
                  previousMissing: _gasPrevMissing,
                  previousLabel: previousLabel,
                  reversed: _isReversed(_gasReading, _gasPrev),
                  price: _gasPrice,
                  usage: _usage(_gasReading, _gasPrev),
                  cost:
                      _usage(_gasReading, _gasPrev) *
                      (double.tryParse(_gasPrice.text.trim()) ?? 0),
                  onChanged: () => setState(() {}),
                ),
                ZCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ZSectionTitle(
                        title: '物业 / 网络',
                        icon: Icons.wifi_outlined,
                        margin: EdgeInsets.only(bottom: 10),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _propertyFee,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: '物业费',
                                prefixText: '¥ ',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _networkFee,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: '网络费',
                                prefixText: '¥ ',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _note,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: '备注',
                          hintText: '如：水电由房东代收',
                        ),
                      ),
                    ],
                  ),
                ),
                if (_existing != null) ...[
                  const SizedBox(height: 4),
                  const SizedBox(height: 14),
                  TextButton.icon(
                    onPressed: _delete,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: Z.danger,
                    ),
                    label: const Text(
                      '删除这条记录',
                      style: TextStyle(color: Z.danger),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final repository = context.read<Repository>();
    // 只读归档：房子已退租后不再允许新增或修改抄表记录
    final property = repository.propertyById(widget.propertyId);
    if (property != null && !canAddUtility(property)) {
      if (mounted) zToast(context, '这套房子已退租，抄表记录只能查看，不能再改');
      return;
    }
    double parse(TextEditingController controller) =>
        double.tryParse(controller.text.trim()) ?? 0;

    // 一个月只保留一条记录。月份在页面上是锁定的，所以这里只可能是
    // 「新建」或「更新同一条」，绝不会把某个月的数据写到另一条记录上去。
    final existing = _existing;
    final sameMonth = repository.utilityOfMonth(widget.propertyId, _month);
    final kept = existing ?? sameMonth;

    await repository.saveUtility(
      UtilityRecord(
        id: kept?.id ?? newId('util'),
        propertyId: widget.propertyId,
        month: _month,
        electricity: _useElectricity
            ? UtilityReading(
                reading: parse(_elecReading),
                previousReading: parse(_elecPrev),
                unitPrice: parse(_elecPrice),
                unit: 'kWh',
              )
            : null,
        water: _useWater
            ? UtilityReading(
                reading: parse(_waterReading),
                previousReading: parse(_waterPrev),
                unitPrice: parse(_waterPrice),
                unit: 'm³',
              )
            : null,
        gas: _useGas
            ? UtilityReading(
                reading: parse(_gasReading),
                previousReading: parse(_gasPrev),
                unitPrice: parse(_gasPrice),
                unit: 'm³',
              )
            : null,
        propertyFee: parse(_propertyFee),
        networkFee: parse(_networkFee),
        recordedAt: kept?.recordedAt ?? DateTime.now(),
        note: _note.text.trim(),
        photoRef: _photoRef,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    zToast(context, '已保存抄表记录');
  }

  Future<void> _delete() async {
    final existing = _existing;
    if (existing == null) return;
    final ok = await zConfirm(
      context,
      title: '删除抄表记录',
      message: '删除后无法恢复，确定继续吗？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    await context.read<Repository>().deleteUtility(existing.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

class _MeterGroup extends StatelessWidget {
  const _MeterGroup({
    required this.title,
    required this.emoji,
    required this.unit,
    required this.enabled,
    required this.onToggle,
    required this.reading,
    required this.previous,
    required this.previousMissing,
    required this.previousLabel,
    this.reversed = false,
    required this.price,
    required this.usage,
    required this.cost,
    required this.onChanged,
  });

  final String title;
  final String emoji;
  final String unit;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final TextEditingController reading;

  /// 只读的上月读数来源（由「上一月」记录自动带入）
  final TextEditingController previous;
  final bool previousMissing;

  /// 上一月的中文标签，用于「没有记录」的提示
  final String previousLabel;
  final bool reversed;
  final TextEditingController price;
  final double usage;
  final double cost;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: ZIcon.s)),
              const SizedBox(width: 6),
              Text(title, style: ZText.title4),
              const Spacer(),
              Switch(value: enabled, onChanged: onToggle),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: '上月读数',
                      suffixText: previousMissing ? null : unit,
                      suffixIcon: Icon(
                        Icons.lock_outline_rounded,
                        size: ZIcon.xs,
                        color: Z.ink4,
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: ZIcon.xs,
                        minHeight: ZIcon.xs,
                      ),
                      filled: true,
                      fillColor: Z.surfaceMuted,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: Z.radiusField,
                        borderSide: BorderSide(color: Z.line),
                      ),
                    ),
                    child: Text(
                      previousMissing ? '—' : previous.text,
                      style: ZText.body.copyWith(
                        color: previousMissing ? Z.ink4 : Z.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: reading,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => onChanged(),
                    decoration: InputDecoration(
                      labelText: '本月读数',
                      suffixText: unit,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: price,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => onChanged(),
                    decoration: InputDecoration(
                      labelText: '单价',
                      suffixText: '元/$unit',
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '用量 ${fmtAmount(usage)} $unit',
                          style: ZText.small,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fmtMoney(cost),
                          style: ZText.title4.copyWith(color: Z.brand),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (previousMissing) ...[
              const SizedBox(height: 8),
              ZHintBar(
                text: '没有 $previousLabel 的抄表记录：上月读数按 0 计，用量会等于本月读数。',
                icon: Icons.event_busy_outlined,
              ),
            ],
            if (reversed) ...[
              const SizedBox(height: 8),
              const ZHintBar(
                text: '本月读数小于上月：若非换表，请核对是否抄错。当前用量按 0 计算。',
                tone: ZTone.danger,
                icon: Icons.error_outline_rounded,
              ),
            ],
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '未启用，打开开关即可记录该项读数',
                style: ZText.small,
              ),
            ),
        ],
      ),
    );
  }
}
