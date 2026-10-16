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

  /// 基准是从哪来的：某条记录的月份，或者是「入住时的表底数」。
  /// 只用来在读数旁标一句「最后一次抄表来自 X 月」—— 跨月没抄时，
  /// 用量其实是好几个月合起来的，得让人自己判断。
  ({String month, bool moveIn})? _elecSource;
  ({String month, bool moveIn})? _waterSource;
  ({String month, bool moveIn})? _gasSource;

  /// 这个月的基准就是「入住时的表底数」：这套房还没有更早的抄表记录
  /// （刚入住、当月就来抄表时一定是这样）。
  /// 决定页面顶部那条提示怎么说：问入住表底数，还是问这条记录的「上月读数」。
  bool _baselineFromMoveIn = false;

  /// 三个「上月读数」输入框的焦点：提示里的「去填写」要滚过去并聚焦
  final FocusNode _elecPrevFocus = FocusNode();
  final FocusNode _waterPrevFocus = FocusNode();
  final FocusNode _gasPrevFocus = FocusNode();

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
      // 合同里勾了「有燃气表」就默认打开这一项；上一月记过燃气读数同理
      // （后者是旧数据的兜底：那时合同里还没有这个开关）。
      // 开着的结果是：首月没有基准时，页顶那条提示也会把燃气算进去
      if (_useGasFromContract(repository) || _gasPrev.text.isNotEmpty) {
        _useGas = true;
      }
    }

  }

  /// 合同里这套房是否勾了「有燃气表」
  bool _useGasFromContract(Repository repository) =>
      repository.propertyById(widget.propertyId)?.contract.hasGasMeter ?? false;

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
    for (final node in [_elecPrevFocus, _waterPrevFocus, _gasPrevFocus]) {
      node.dispose();
    }
    super.dispose();
  }

  /// 上月读数：默认取「日历上一月」那条记录里的读数。
  ///
  /// 上一月没有记录时（例如那个月没住）就**继续往前找**，直到找到有该表
  /// 读数的那个月为止 —— 表上的数是一直在走的，基准越近越准。
  ///
  /// 前面都翻不到时按这个顺序兜底：
  /// 1. 这条记录自己存过的上月读数（回来改一下本月读数，不能把当初的基准丢掉）；
  /// 2. 合同里**入住时的表底数**，但**只在这套房还没有任何抄表记录时**用：
  ///    它是这段租住开始时表盘上的数，等于首月的起点；中间已经有记录、
  ///    只是这块表那次没抄，拿它兜底会把好几个月的用量算进这一个月里。
  /// 都拿不到就留空（用量显示「—」，进来时会弹框让人当场填）。
  void _syncPreviousReadings() {
    final repository = context.read<Repository>();
    final contract = repository.propertyById(widget.propertyId)?.contract;
    final startMonth = monthKey(contract?.moveInDate ?? DateTime.now());

    double? elec;
    double? water;
    double? gas;
    ({String month, bool moveIn})? elecSource;
    ({String month, bool moveIn})? waterSource;
    ({String month, bool moveIn})? gasSource;
    var sawEarlierRecord = false;
    var cursor = previousMonthKey(_month);
    // 上限 36 个月：防止月份算错时死循环
    for (var guard = 0; guard < 36; guard++) {
      final record = repository.utilityOfMonth(widget.propertyId, cursor);
      if (record != null) {
        sawEarlierRecord = true;
        final reading = record.electricity?.reading;
        if (elec == null && reading != null) {
          elec = reading;
          elecSource = (month: cursor, moveIn: false);
        }
        final waterReading = record.water?.reading;
        if (water == null && waterReading != null) {
          water = waterReading;
          waterSource = (month: cursor, moveIn: false);
        }
        final gasReading = record.gas?.reading;
        if (gas == null && gasReading != null) {
          gas = gasReading;
          gasSource = (month: cursor, moveIn: false);
        }
      }
      if (elec != null && water != null && gas != null) break;
      if (cursor.compareTo(startMonth) <= 0) break; // 别翻到租住之前
      cursor = previousMonthKey(cursor);
    }

    // 1) 这条记录当初存下的基准（手填过就以它为准）
    final existing = _existing;
    elec ??= _storedBaseline(existing?.electricity?.previousReading);
    water ??= _storedBaseline(existing?.water?.previousReading);
    gas ??= _storedBaseline(existing?.gas?.previousReading);

    // 2) 入住时的表底数：只认「这是第一条记录」的情况
    if (!sawEarlierRecord) {
      if (elec == null && contract?.moveInElectricity != null) {
        elec = contract!.moveInElectricity;
        elecSource = (month: startMonth, moveIn: true);
      }
      if (water == null && contract?.moveInWater != null) {
        water = contract!.moveInWater;
        waterSource = (month: startMonth, moveIn: true);
      }
      if (gas == null && contract?.moveInGas != null) {
        gas = contract!.moveInGas;
        gasSource = (month: startMonth, moveIn: true);
      }
    }
    // 这一步也决定弹框的口径：没有更早记录时，基准只可能是入住表底数
    _baselineFromMoveIn = !sawEarlierRecord;

    _elecPrevMissing = elec == null;
    _waterPrevMissing = water == null;
    _gasPrevMissing = gas == null;
    _elecSource = elecSource;
    _waterSource = waterSource;
    _gasSource = gasSource;
    _elecPrev.text = elec == null ? '' : fmtAmount(elec);
    _waterPrev.text = water == null ? '' : fmtAmount(water);
    _gasPrev.text = gas == null ? '' : fmtAmount(gas);
  }

  /// 记录里存着的上月读数能不能当基准用。
  ///
  /// 0 不算：当初没填基准时落盘的就是 0（`parse` 空串给 0），
  /// 拿它当基准等于「本月读数 − 0」，那正是要避免的那个数。
  static double? _storedBaseline(double? value) =>
      value == null || value <= 0 ? null : value;

  /// 还缺基准的表（只算当前启用的）：
  /// 页面顶上那条提示和它的「去填写」都用这份清单。
  List<
    ({
      String label,
      String unit,
      TextEditingController field,
      FocusNode focus,
    })
  >
  get _missingBaselines => [
    if (_useElectricity && _elecPrevMissing)
      (label: '电表', unit: 'kWh', field: _elecPrev, focus: _elecPrevFocus),
    if (_useWater && _waterPrevMissing)
      (label: '水表', unit: 'm³', field: _waterPrev, focus: _waterPrevFocus),
    if (_useGas && _gasPrevMissing)
      (label: '燃气表', unit: 'm³', field: _gasPrev, focus: _gasPrevFocus),
  ];

  /// 手里有值了就撤掉「缺基准」标记 —— 否则费用那格会一直写「—」，
  /// 明明已经算得出来了
  void _syncMissingFlags() {
    _elecPrevMissing = _elecPrev.text.trim().isEmpty;
    _waterPrevMissing = _waterPrev.text.trim().isEmpty;
    _gasPrevMissing = _gasPrev.text.trim().isEmpty;
  }

  /// 基准不是「上一月」时给一句说明（写在读数旁边）：
  /// 跨月没抄的话，这个月的用量其实是好几个月合起来的，得让人自己判断。
  /// 来自「入住时的表底数」也按同一口径标出来。
  String? _baselineNote(({String month, bool moveIn})? source) {
    if (source == null) return null;
    if (!source.moveIn && source.month == previousMonthKey(_month)) return null;
    final from = source.moveIn
        ? '基准是入住抄表数（${monthLabel(source.month)}）'
        : '最后一次抄表来自 ${monthLabel(source.month)}';
    return '$from，中间没抄的月份会合进这个月';
  }

  /// 提示只负责指路：真正填的地方还是表卡里的「上月读数」。
  /// 滚过去并聚焦，省得用户自己在一屏里找那个空框。
  Future<void> _focusMissingBaseline() async {
    final missing = _missingBaselines;
    if (missing.isEmpty) return;
    final node = missing.first.focus;
    final target = node.context;
    if (target != null) {
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 260),
        alignment: 0.2,
      );
    }
    if (mounted) node.requestFocus();
  }

  /// 首月抄表时填的基准，就是合同里的「入住表底数」：
  /// 顺手写回合同，否则首页那条「补填入住时的水/电表数」的待办永远消不掉。
  ///
  /// 只写解析得出来的项，别拿空值把合同里已填的抹掉；
  /// 也不刷新 `updatedAt`（补历史资料，见 `updateProperty` 的 `touch`）。
  /// 返回是否真的写了。
  Future<bool> _writeBaselineToContract(Repository repository) async {
    final property = repository.propertyById(widget.propertyId);
    if (property == null) return false;

    double? valueOf(TextEditingController controller) {
      final text = controller.text.trim();
      return text.isEmpty ? null : double.tryParse(text);
    }

    final contract = property.contract;
    final elec = _useElectricity ? valueOf(_elecPrev) : null;
    final water = _useWater ? valueOf(_waterPrev) : null;
    final gas = _useGas ? valueOf(_gasPrev) : null;
    if (elec == null && water == null && gas == null) return false;

    await repository.updateProperty(
      property.copyWith(
        contract: contract.copyWith(
          moveInElectricity: elec ?? contract.moveInElectricity,
          moveInWater: water ?? contract.moveInWater,
          moveInGas: gas ?? contract.moveInGas,
        ),
      ),
      touch: false,
    );
    return true;
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
                // 所属月份：标签和月份同一行（左边标签、右边值），不再上下两行。
                // 月份不可改：新增时就是本月（或从年份页点进来的那个月），
                // 编辑时锁定为这条记录的月份——避免一条记录被改到别的月份上
                ZKv(
                  label: '所属月份',
                  value: monthLabel(_month),
                  mono: true,
                  divider: false,
                ),
                // 缺基准就常驻在这儿（以前是弹框，用户点「稍后」就永远不填了）。
                // 提示只指路，值填在下面表卡的「上月读数」里，填完自己消失
                if (editable && _missingBaselines.isNotEmpty)
                  _BaselineNotice(
                    askMoveIn: _baselineFromMoveIn,
                    withGas: _missingBaselines.any(
                      (meter) => meter.label == '燃气表',
                    ),
                    onFill: _focusMissingBaseline,
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
                  previousFocus: _elecPrevFocus,
                  previousFieldLabel: _baselineFromMoveIn
                      ? '入住抄表数'
                      : '上月读数',
                  previousNote: _baselineNote(_elecSource),
                  previousMissing: _elecPrevMissing,
                  previousLabel: previousLabel,
                  reversed: _isReversed(_elecReading, _elecPrev),
                  price: _elecPrice,
                  usage: _usage(_elecReading, _elecPrev),
                  cost:
                      _usage(_elecReading, _elecPrev) *
                      (double.tryParse(_elecPrice.text.trim()) ?? 0),
                  readOnly: !editable,
                  onChanged: () => setState(_syncMissingFlags),
                ),
                _MeterGroup(
                  title: '水表',
                  emoji: '💧',
                  unit: 'm³',
                  enabled: _useWater,
                  onToggle: (value) => setState(() => _useWater = value),
                  reading: _waterReading,
                  previous: _waterPrev,
                  previousFocus: _waterPrevFocus,
                  previousFieldLabel: _baselineFromMoveIn
                      ? '入住抄表数'
                      : '上月读数',
                  previousNote: _baselineNote(_waterSource),
                  previousMissing: _waterPrevMissing,
                  previousLabel: previousLabel,
                  reversed: _isReversed(_waterReading, _waterPrev),
                  price: _waterPrice,
                  usage: _usage(_waterReading, _waterPrev),
                  cost:
                      _usage(_waterReading, _waterPrev) *
                      (double.tryParse(_waterPrice.text.trim()) ?? 0),
                  readOnly: !editable,
                  onChanged: () => setState(_syncMissingFlags),
                ),
                _MeterGroup(
                  title: '燃气表',
                  emoji: '🔥',
                  unit: 'm³',
                  enabled: _useGas,
                  onToggle: (value) => setState(() => _useGas = value),
                  reading: _gasReading,
                  previous: _gasPrev,
                  previousFocus: _gasPrevFocus,
                  previousFieldLabel: _baselineFromMoveIn
                      ? '入住抄表数'
                      : '上月读数',
                  previousNote: _baselineNote(_gasSource),
                  previousMissing: _gasPrevMissing,
                  previousLabel: previousLabel,
                  reversed: _isReversed(_gasReading, _gasPrev),
                  price: _gasPrice,
                  usage: _usage(_gasReading, _gasPrev),
                  cost:
                      _usage(_gasReading, _gasPrev) *
                      (double.tryParse(_gasPrice.text.trim()) ?? 0),
                  readOnly: !editable,
                  onChanged: () => setState(_syncMissingFlags),
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
    // 首月填的基准就是合同里的「入住表底数」：顺手写回合同，
    // 首页那条「补填入住时的水/电表数」的待办才会跟着消失
    final wroteContract = _baselineFromMoveIn
        ? await _writeBaselineToContract(repository)
        : false;
    if (!mounted) return;
    Navigator.of(context).pop();
    zToast(context, wroteContract ? '已保存，入住表底数也记进合同了' : '已保存抄表记录');
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

/// 页顶那条「缺基准」提示：比页面上的 ZHintBar 重一档（同色系底 + 同色描边 +
/// 加重的字），并且**常驻到填上为止** —— 以前是弹框，用户点「稍后」就再也不管了。
///
/// 它只指路：真正的输入框还是表卡里的「上月读数」，「去填写」负责滚过去并聚焦。
class _BaselineNotice extends StatelessWidget {
  const _BaselineNotice({
    required this.askMoveIn,
    required this.withGas,
    required this.onFill,
  });

  /// true = 问「入住时的表底数」（这套房还没有更早的记录），
  /// false = 问这条记录的「上月读数」
  final bool askMoveIn;

  /// 缺的里面有没有燃气表（用燃气的房子才问）
  final bool withGas;
  final VoidCallback onFill;

  @override
  Widget build(BuildContext context) {
    final tone = askMoveIn ? Z.warnDeep : Z.brand;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            askMoveIn
                ? Icons.warning_amber_rounded
                : Icons.info_outline_rounded,
            size: 17,
            color: tone,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              askMoveIn
                  ? '合同里暂时还没有填写入住前的水/电'
                        '${withGas ? '/燃气' : ''}表数，请录入'
                  : '没有上一月的抄表记录，请填上个月的读数',
              style: ZText.body.copyWith(
                fontSize: 13.5,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: tone,
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: onFill,
            style: TextButton.styleFrom(
              foregroundColor: tone,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('去填写'),
                Icon(Icons.arrow_downward_rounded, size: 15),
              ],
            ),
          ),
        ],
      ),
    );
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
    required this.previousFocus,
    this.previousNote,
    required this.previousMissing,
    required this.previousLabel,
    this.previousFieldLabel = '上月读数',
    this.reversed = false,
    required this.price,
    required this.usage,
    required this.cost,
    required this.onChanged,
    this.readOnly = false,
  });

  final String title;
  final String emoji;
  final String unit;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final TextEditingController reading;

  /// 只读的上月读数来源（由「上一月」记录自动带入）
  final TextEditingController previous;

  /// 页顶提示里的「去填写」要滚到这里并聚焦
  final FocusNode previousFocus;

  /// 基准不是「上一月」时的说明（跨月没抄 / 来自入住表底数），没有就不写
  final String? previousNote;
  final bool previousMissing;

  /// 上一月的中文标签，用于「没有记录」的提示
  final String previousLabel;

  /// 「上月读数」那个框的名字。这套房还没有更早的记录时，
  /// 基准其实是入住时的抄表数，标签跟着改叫「入住抄表数」
  final String previousFieldLabel;
  final bool reversed;
  final TextEditingController price;
  final double usage;
  final double cost;
  final VoidCallback onChanged;

  /// 已退租的房子只读：开关与输入框都不给动（提交那边也拦着）
  final bool readOnly;

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
              Switch(value: enabled, onChanged: readOnly ? null : onToggle),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  // 上月读数可以自己改：上一月没记录（或换了表）时，
                  // 手填一个基准，用量 = 本月读数 − 这里填的数
                  child: TextField(
                    controller: previous,
                    focusNode: previousFocus,
                    readOnly: readOnly,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => onChanged(),
                    decoration: InputDecoration(
                      labelText: previousFieldLabel,
                      suffixText: unit,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: reading,
                    readOnly: readOnly,
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
                    readOnly: readOnly,
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
                          // 上月读数栏空着就算不出真实用量：显示「—」，
                          // 不能拿「本月读数 − 0」当用量 —— 那是个明显不对的数
                          previous.text.trim().isEmpty
                              // 首月那格叫「入住抄表数」，这里跟着它的名字走
                              ? '用量 —（缺$previousFieldLabel）'
                              : '用量 ${fmtAmount(usage)} $unit',
                          style: ZText.small,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          previousMissing ? '—' : fmtMoney(cost),
                          style: ZText.title4.copyWith(color: Z.brand),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // 基准不是「上一月」时标一句来源：跨月没抄的话，
            // 这个用量其实是好几个月合起来的，让人自己判断
            if (previousNote != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 令牌色跟着明暗走，不是 const
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: Z.ink3,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      previousNote!,
                      style: ZText.small.copyWith(
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
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
