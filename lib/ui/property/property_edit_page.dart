import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../evidence/evidence_rooms_page.dart';
import '../kit.dart';

class PropertyEditPage extends StatefulWidget {
  const PropertyEditPage({super.key, this.propertyId});

  final String? propertyId;

  @override
  State<PropertyEditPage> createState() => _PropertyEditPageState();
}

class _PropertyEditPageState extends State<PropertyEditPage> {
  static const List<String> _steps = ['基本信息', '房东', '合同', '特殊条款'];

  final TextEditingController _name = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _area = TextEditingController();
  final TextEditingController _landlordName = TextEditingController();
  final TextEditingController _landlordPhone = TextEditingController();
  final TextEditingController _landlordWechat = TextEditingController();
  final TextEditingController _rent = TextEditingController();
  final TextEditingController _deposit = TextEditingController();
  final TextEditingController _moveInElectricity = TextEditingController();
  final TextEditingController _moveInWater = TextEditingController();
  final TextEditingController _moveInGas = TextEditingController();
  final TextEditingController _early = TextEditingController();
  final TextEditingController _renewal = TextEditingController();
  final TextEditingController _special = TextEditingController();

  int _step = 0;
  int _rooms = 2;
  int _halls = 1;
  int _baths = 1;
  int _minLeaseMonths = 1;
  bool _hasDeposit = true;
  String _paymentMethod = '月付';
  String _rentScope = '整租';
  int _noticeDays = 30;
  bool _hasGasMeter = false;
  DateTime _moveInDate = DateTime.now();
  DateTime _contractEnd = DateTime(
    DateTime.now().year + 1,
    DateTime.now().month,
    DateTime.now().day,
  );
  bool _rentDueDayEdited = false;
  bool _contractEndEdited = false;
  // 默认就是入住日前一天（入住日默认今天）
  int _rentDueDay = (DateTime.now().day - 1).clamp(1, 28);
  Property? _existing;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final id = widget.propertyId;
    if (id == null) return;
    final property = context.read<Repository>().propertyById(id);
    if (property == null) return;
    _existing = property;
    _name.text = property.name;
    _address.text = property.address;
    _area.text = property.area;
    final layoutMatch = RegExp(
      r'(\d+)\s*室.*?(\d+)\s*厅.*?(\d+)\s*卫',
    ).firstMatch(property.layout);
    if (layoutMatch != null) {
      _rooms = int.tryParse(layoutMatch.group(1)!) ?? 2;
      _halls = int.tryParse(layoutMatch.group(2)!) ?? 1;
      _baths = int.tryParse(layoutMatch.group(3)!) ?? 1;
    }
    _landlordName.text = property.landlord.name;
    _landlordPhone.text = property.landlord.phone;
    _landlordWechat.text = property.landlord.wechat;
    _rent.text = fmtAmount(property.contract.monthlyRent);
    _deposit.text = fmtAmount(property.contract.deposit);
    _moveInElectricity.text = _readingText(
      property.contract.moveInElectricity,
    );
    _moveInWater.text = _readingText(property.contract.moveInWater);
    _moveInGas.text = _readingText(property.contract.moveInGas);
    _early.text = property.contract.earlyTermination;
    _renewal.text = property.contract.renewalTerms;
    _special.text = property.contract.specialTerms;
    _paymentMethod = property.contract.paymentMethod;
    _rentScope = property.contract.rentScope;
    _noticeDays = property.contract.noticeDays;
    _minLeaseMonths = property.contract.minLeaseMonths;
    if (_minLeaseMonths <= 0) _minLeaseMonths = 1;
    _hasDeposit = property.contract.deposit > 0;
    // 旧数据没有这个开关，但抄表记录里记过燃气：按「有燃气表」带出来
    _hasGasMeter =
        property.contract.hasGasMeter ||
        usesGas(
          property.contract,
          context.read<Repository>().utilitiesOf(property.id),
          property.id,
        );
    _moveInDate = property.contract.moveInDate;
    _contractEnd = property.contract.contractEnd;
    _rentDueDay = property.contract.rentDueDay;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _address,
      _area,
      _landlordName,
      _landlordPhone,
      _landlordWechat,
      _rent,
      _deposit,
      _moveInElectricity,
      _moveInWater,
      _moveInGas,
      _early,
      _renewal,
      _special,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = _existing != null;
    return ZScreen(
      bottomBar: _BottomBar(
        step: _step,
        busy: _busy,
        editing: editing,
        onBack: () {
          // 翻页时先收起键盘并取消焦点：否则上一步那个输入框会一直留成高亮选中态
          FocusScope.of(context).unfocus();
          setState(() => _step = (_step - 1).clamp(0, 3));
        },
        onNext: () {
          FocusScope.of(context).unfocus();
          if (!_validateStep()) return;
          setState(() => _step = (_step + 1).clamp(0, 3));
        },
        onSave: _save,
      ),
      child: Column(
        children: [
          ZAppBar(
            leading: const ZBackButton(),
            title: editing ? '编辑房源' : '添加房源',
            subtitle: '第 ${_step + 1} / 4 步 · ${_steps[_step]}',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: ZSteps(steps: _steps, current: _step),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: switch (_step) {
                0 => _basicStep(),
                1 => _landlordStep(),
                2 => _contractStep(),
                _ => _termsStep(),
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _basicStep() => [
    ZField(
      label: '房源名称',
      required: true,
      child: TextField(
        controller: _name,
        decoration: const InputDecoration(hintText: '如：翠屏里 3 栋 502'),
      ),
    ),
    ZField(
      label: '详细地址',
      required: true,
      child: TextField(
        controller: _address,
        decoration: const InputDecoration(hintText: '用于取证照片水印与维权材料'),
      ),
    ),
    ZField(
      label: '户型',
      child: Row(
        children: [
          Expanded(
            child: _LayoutWheel(
              label: '室',
              value: _rooms,
              onChanged: (v) => setState(() => _rooms = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _LayoutWheel(
              label: '厅',
              value: _halls,
              onChanged: (v) => setState(() => _halls = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _LayoutWheel(
              label: '卫',
              value: _baths,
              onChanged: (v) => setState(() => _baths = v),
            ),
          ),
        ],
      ),
    ),
    ZField(
      label: '面积',
      child: TextField(
        controller: _area,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          hintText: '89',
          suffixText: '㎡',
        ),
      ),
    ),
    const SizedBox(height: 10),
    const ZHintBar(text: '填完合同信息后，租盾会自动生成交租计划与到期倒计时。'),
  ];

  List<Widget> _landlordStep() => [
    ZField(
      label: '房东姓名',
      required: true,
      child: TextField(
        controller: _landlordName,
        decoration: const InputDecoration(hintText: '出租方姓名'),
      ),
    ),
    ZField(
      label: '联系电话',
      child: TextField(
        controller: _landlordPhone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(hintText: '手机号或固定电话'),
      ),
    ),
    ZField(
      label: '微信 / 其他联系方式',
      child: TextField(
        controller: _landlordWechat,
        decoration: const InputDecoration(hintText: '选填'),
      ),
    ),
    const SizedBox(height: 6),
    const ZHintBar(
      text: '建议同时留存房东的微信截图，退租时可作为沟通证据。',
      icon: Icons.chat_bubble_outline_rounded,
    ),
  ];

  List<Widget> _contractStep() => [
    ZField(
      label: '月租金额',
      required: true,
      child: TextField(
        controller: _rent,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(prefixText: '¥ '),
      ),
    ),
    ZField(
      label: '是否需要押金',
      child: ZChips<bool>(
        options: const [true, false],
        value: _hasDeposit,
        emphasize: true,
        padding: EdgeInsets.zero,
        labelOf: (v) => v ? '需要' : '不需要',
        onChanged: (v) => setState(() {
          _hasDeposit = v;
          if (!v) _deposit.clear();
        }),
      ),
    ),
    if (_hasDeposit)
      ZField(
        label: '押金金额',
        required: true,
        child: TextField(
          controller: _deposit,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(prefixText: '¥ '),
        ),
      ),
    ZField(
      label: '付款周期',
      child: ZChips<String>(
        options: const ['月付', '季付', '半年付', '年付'],
        value: _paymentMethod,
        emphasize: true,
        padding: EdgeInsets.zero,
        labelOf: (value) => value,
        onChanged: (value) => setState(() => _paymentMethod = value),
      ),
    ),
    // 先选最少租期，再填入住日期 —— 合同到期默认由这两项算出来
    ZField(
      label: '最少租期',
      child: ZChips<int>(
        options: const [1, 3, 6, 12, 24],
        value: _minLeaseMonths,
        emphasize: true,
        padding: EdgeInsets.zero,
        labelOf: (value) => '$value 个月',
        onChanged: (value) => setState(() {
          _minLeaseMonths = value;
          // 合同到期默认 = 入住日 + 最少租期；手动改过到期日就不再覆盖
          if (!_contractEndEdited) {
            _contractEnd = _addMonths(_moveInDate, value);
          }
        }),
      ),
    ),
    const SizedBox(height: 4),
    Row(
      children: [
        Expanded(
          child: ZField(
            label: '入住日期',
            child: _DateButton(
              value: _moveInDate,
              onChanged: (value) => setState(() {
                _moveInDate = value;
                // 交租日默认跟着入住日走：入住日前一天（没手改过时才联动）
                if (!_rentDueDayEdited) {
                  _rentDueDay = (value.day - 1).clamp(1, 28);
                }
                // 合同到期默认 = 入住日 + 最少租期（手改过到期日就不再覆盖）
                if (!_contractEndEdited) {
                  _contractEnd = _addMonths(value, _minLeaseMonths);
                }
              }),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ZField(
            label: '合同到期',
            child: _DateButton(
              value: _contractEnd,
              onChanged: (value) => setState(() {
                _contractEnd = value;
                _contractEndEdited = true;
              }),
            ),
          ),
        ),
      ],
    ),
    ZField(
      label: '租住方式',
      child: ZChips<String>(
        options: const ['整租', '合租'],
        value: _rentScope,
        emphasize: true,
        padding: EdgeInsets.zero,
        labelOf: (value) => value,
        onChanged: (value) => setState(() => _rentScope = value),
      ),
    ),
    ZField(
      label: '退租提前通知',
      child: ZChips<int>(
        options: const [7, 15, 30, 60],
        value: _noticeDays,
        emphasize: true,
        padding: EdgeInsets.zero,
        labelOf: (value) => '提前 $value 天',
        onChanged: (value) => setState(() => _noticeDays = value),
      ),
    ),
    ZField(
      label: '每月交租日',
      // 以前是 DropdownButton：1–28 号一展开菜单就占满半屏。
      // 改成点开一个紧凑的数字格子弹层，点哪个就是哪一天。
      child: InkWell(
        borderRadius: Z.radiusField,
        onTap: () => _pickRentDueDay(context),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: Z.card,
            borderRadius: Z.radiusField,
            border: Border.all(color: Z.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '每月 $_rentDueDay 号',
                  style: ZText.body.copyWith(fontSize: 14),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: Z.ink3,
              ),
            ],
          ),
        ),
      ),
    ),
    // 入住表底数：抄表录入的首月用量要拿它当基准。
    // 选填 —— 先不填也建得起来，首页待办会一直提醒补。
    // 先问有没有燃气表，再决定要不要填燃气表读数：
    // 家里没燃气表的房子不该被追着填一个（填 0 也是假的）
    ZField(
      label: '有燃气表吗',
      child: ZChips<bool>(
        options: const [true, false],
        value: _hasGasMeter,
        emphasize: true,
        padding: EdgeInsets.zero,
        labelOf: (value) => value ? '有燃气表' : '没有燃气表',
        onChanged: (value) => setState(() => _hasGasMeter = value),
      ),
    ),
    ZField(
      label: '入住时的表底数（选填）',
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _moveInElectricity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '电表'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _moveInWater,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '水表'),
            ),
          ),
          if (_hasGasMeter) ...[
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _moveInGas,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '燃气表'),
              ),
            ),
          ],
        ],
      ),
    ),
    const ZHintBar(
      text: '填的是入住当天的表数（电 kWh / 水 m³）。'
          '抄表录入的上月读数拿它；不填也能建房源，'
          '只是首页会一直留着「补填水/电表数」这条待办。',
      icon: Icons.speed_outlined,
    ),
    const SizedBox(height: 10),
    ZHintBar(
      text:
          '按当前设置：每月 $_rentDueDay 号交租，'
          '共 ${_months()} 期，下次交租 ${fmtDate(nextRentDue(_rentDueDay))}。',
      icon: Icons.event_available_outlined,
    ),
  ];

  List<Widget> _termsStep() => [
    ZField(
      label: '特殊条款',
      child: TextField(
        controller: _special,
        maxLines: 4,
        decoration: const InputDecoration(hintText: '如：不可养宠物、不可打孔'),
      ),
    ),
    Text('常见条款（点一下加到上面）', style: ZText.caption),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final preset in LandlordRule.presets)
          InkWell(
            borderRadius: BorderRadius.circular(100),
            onTap: () => setState(() {
              final current = _special.text.trim();
              if (current.contains(preset)) return;
              _special.text = current.isEmpty ? preset : '$current\n$preset';
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _special.text.contains(preset)
                    ? Z.brandTint
                    : Z.card,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: _special.text.contains(preset)
                      ? Z.brand.withValues(alpha: 0.28)
                      : Z.line,
                ),
              ),
              child: Text(
                preset,
                style: ZText.label.copyWith(
                  color: _special.text.contains(preset) ? Z.brand : Z.ink3,
                  fontWeight: _special.text.contains(preset)
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ),
          ),
      ],
    ),
    const SizedBox(height: 14),
    const ZHintBar(
      text: '提前退租与续租条件已并入特殊条款；未填写的条款会在保存后以黄条提醒，不阻塞流程。',
      tone: ZTone.warn,
      icon: Icons.warning_amber_rounded,
    ),
  ];

  /// 入住日 + N 个月（用于「合同到期」的默认值）
  DateTime _addMonths(DateTime from, int months) =>
      DateTime(from.year, from.month + months, from.day);

  /// 没抄过的表底数保持在空框里，别把「还没填」显示成 0
  String _readingText(double? value) => value == null ? '' : fmtAmount(value);

  /// 输入框里的表底数：空就是还没抄（null），不是 0
  /// 输入框里的表底数读成数字。
  ///
  /// 空 = 没抄（清掉），填了非法字符（同事的「1.2.3」这种）就**保留原值**：
  /// 用户是想改，不是想删，静默清掉等于把他的数弄丢了
  /// （`_validateStep` 那边会先拦一道，这里只是兜底）。
  double? _readingValue(TextEditingController controller, double? stored) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text) ?? stored;
  }

  /// 一共几期（含首尾月）：和按租期生成的租金计划一致。
  /// 纯月份差会少算一期，这里必须 +1（`ContractInfo.totalMonths` 同一个口径）
  int _months() {
    final months =
        (_contractEnd.year - _moveInDate.year) * 12 +
        (_contractEnd.month - _moveInDate.month) +
        1;
    return months <= 0 ? 1 : months;
  }

  bool _validateStep() {
    if (_step == 0) {
      if (_name.text.trim().isEmpty || _address.text.trim().isEmpty) {
        zToast(context, '请填写房源名称与详细地址');
        return false;
      }
    }
    if (_step == 1 && _landlordName.text.trim().isEmpty) {
      zToast(context, '请填写房东姓名');
      return false;
    }
    if (_step == 2) {
      final rent = double.tryParse(_rent.text.trim()) ?? 0;
      if (rent <= 0) {
        zToast(context, '请填写正确的月租金额');
        return false;
      }
      if (_hasDeposit) {
        final deposit = double.tryParse(_deposit.text.trim()) ?? 0;
        if (deposit <= 0) {
          zToast(context, '请填写押金金额');
          return false;
        }
      }
      // 表底数是选填的，但填了就得是数字：别让「1.2.3」这类手滑
      // 静默变成「没填」，把之前存过的值抹掉
      final readings = <String, TextEditingController>{
        '电表': _moveInElectricity,
        '水表': _moveInWater,
        if (_hasGasMeter) '燃气表': _moveInGas,
      };
      for (final entry in readings.entries) {
        final text = entry.value.text.trim();
        if (text.isEmpty) continue;
        if (double.tryParse(text) == null) {
          zToast(context, '${entry.key}读数只能填数字');
          return false;
        }
      }
    }
    return true;
  }

  /// 表底数和合同照片两边都能改：合同页那三个框（失焦即存）和那边照片的加号。
  ///
  /// 保存向导时先把两边合一下，别拿「打开向导时的快照」把人家刚改的盖回去：
  /// - 别处改过、这里没动过 → 用别处的新值（合并）；
  /// - 两边都改了 → 弹框问用户用哪个（这是真冲突）；
  /// - 合同照片取并集（那边随时能加一页）。
  Future<({double? elec, double? water, double? gas, List<String> photos})>
  _mergeContractEdits(Repository repository) async {
    final loaded = _existing?.contract;
    final id = widget.propertyId;
    final current = id == null ? null : repository.propertyById(id)?.contract;
    if (loaded == null || current == null) {
      // 新建房源（或仓库里那份没了）：照填的写
      return (
        elec: _readingValue(_moveInElectricity, null),
        water: _readingValue(_moveInWater, null),
        gas: _hasGasMeter ? _readingValue(_moveInGas, null) : null,
        photos: const <String>[],
      );
    }

    String show(double? value) => value == null ? '未填' : fmtAmount(value);

    Future<double?> pick({
      required String label,
      required double? loadedValue,
      required double? storedValue,
      required TextEditingController controller,
      bool enabled = true,
    }) async {
      // 明确关掉了这块表（改成「没有燃气表」）：以这里为准，直接清掉
      if (!enabled) return null;
      final typed = _readingValue(controller, loadedValue);
      // 别处没动过：照这里填的写
      if (storedValue == loadedValue) return typed;
      // 别处动过、这里没动过：用别处的新值（合并，别抹掉人家刚填的）
      if (typed == loadedValue) return storedValue;
      // 两边都动过：问用户
      final useMine = await zConfirm(
        context,
        title: '表底数两边都改过',
        message:
            '$label：打开这一页时是 ${show(loadedValue)}，'
            '后来在合同页改成了 ${show(storedValue)}，'
            '这里填的是 ${show(typed)}。用哪个？',
        confirmText: '用这里填的',
        cancelText: '用合同页的',
      );
      return useMine ? typed : storedValue;
    }

    final storedPhotos = current.contractPhotoRefs;
    final loadedPhotos = loaded.contractPhotoRefs;
    return (
      elec: await pick(
        label: '电表',
        loadedValue: loaded.moveInElectricity,
        storedValue: current.moveInElectricity,
        controller: _moveInElectricity,
      ),
      water: await pick(
        label: '水表',
        loadedValue: loaded.moveInWater,
        storedValue: current.moveInWater,
        controller: _moveInWater,
      ),
      gas: await pick(
        label: '燃气表',
        loadedValue: loaded.moveInGas,
        storedValue: current.moveInGas,
        controller: _moveInGas,
        enabled: _hasGasMeter,
      ),
      photos: [
        ...storedPhotos,
        for (final ref in loadedPhotos)
          if (!storedPhotos.contains(ref)) ref,
      ],
    );
  }

  Future<void> _save() async {
    if (!_validateStep()) return;
    final repository = context.read<Repository>();
    setState(() => _busy = true);
    final now = DateTime.now();
    final depositValue = _hasDeposit
        ? (double.tryParse(_deposit.text.trim()) ?? 0)
        : 0.0;
    // 表底数 / 合同照片两边都能改：先和仓库里最新的那份合一下
    // （新建房源没人跟它抢，就是照填的写）
    final readings = await _mergeContractEdits(repository);
    final contract = ContractInfo(
      monthlyRent: double.tryParse(_rent.text.trim()) ?? 0,
      deposit: depositValue,
      paymentMethod: _paymentMethod,
      rentScope: _rentScope,
      noticeDays: _noticeDays,
      moveInDate: _moveInDate,
      contractEnd: _contractEnd,
      rentDueDay: _rentDueDay,
      minLeaseMonths: _minLeaseMonths,
      earlyTermination: _early.text.trim(),
      renewalTerms: _renewal.text.trim(),
      specialTerms: _special.text.trim(),
      contractPhotoRefs: readings.photos,
      hasGasMeter: _hasGasMeter,
      moveInElectricity: readings.elec,
      moveInWater: readings.water,
      moveInGas: readings.gas,
    );
    final landlord = Landlord(
      name: _landlordName.text.trim(),
      phone: _landlordPhone.text.trim(),
      wechat: _landlordWechat.text.trim(),
    );

    try {
      if (_existing == null) {
        final created = await repository.addProperty(
          Property(
            id: newId('prop'),
            name: _name.text.trim(),
            address: _address.text.trim(),
            layout: '$_rooms室$_halls厅$_baths卫',
            area: _area.text.trim(),
            landlord: landlord,
            contract: contract,
            // 状态不在这里手选：新建就是「租住中」，
            // 之后也只有「完成退租」和「去纠纷」这两条路会改它
            // （押金状态不联动房源状态，见 logic.dart 的口径）
            status: PropertyStatus.active,
            deposit: DepositInfo(
              status: _hasDeposit ? DepositStatus.paid : DepositStatus.none,
              logs: [
                DepositLog(
                  status: _hasDeposit
                      ? DepositStatus.paid
                      : DepositStatus.none,
                  time: now,
                  note: _hasDeposit
                      ? '创建房源时记录押金 ${fmtMoney(contract.deposit)}'
                      : '本房源无需押金',
                ),
              ],
            ),
            createdAt: now,
            updatedAt: now,
          ),
        );
        if (!mounted) return;
        // 注意顺序：先问「要不要现在取证」，再决定离开向导页 ——
        // 以前是先 pop 再弹框，等用户点「立即取证」时这页已经卸载，
        // context.mounted 变成 false，于是什么都不发生
        final start = await zConfirm(
          context,
          title: '房源已创建',
          message: '建议现在完成「入住取证」，逐房间拍照留证，退租时才有对比依据。',
          confirmText: '立即取证',
          cancelText: '稍后',
        );
        if (!mounted) return;
        if (start) {
          // 用 replace：从取证页返回时直接回到列表，别再回到已经保存过的向导
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => EvidenceRoomsPage(propertyId: created.id),
            ),
          );
        } else {
          Navigator.of(context).pop();
        }
      } else {
        // 以仓库里最新那份为底：向导打开之后，押金状态 / 房源状态 / 表底数
        // 都可能在别处（押金追踪、合同页）改过，
        // 别拿打开时的快照把它们盖回去
        final base = repository.propertyById(_existing!.id) ?? _existing!;
        await repository.updateProperty(
          base.copyWith(
            name: _name.text.trim(),
            address: _address.text.trim(),
            layout: '$_rooms室$_halls厅$_baths卫',
            area: _area.text.trim(),
            landlord: landlord,
            contract: contract,
            // 编辑时不动状态：退租 / 纠纷由「押金追踪」那边流转，
            // 这里改合同资料不该把房子从「已退租」拽回「租住中」
          ),
        );
        if (!mounted) return;
        zToast(context, '已保存并生成提醒计划');
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 选「每月几号交租」：1–28 号排成一片数字，点一个就选中。
  ///
  /// 以前用 DropdownButton，28 项一展开菜单就占满半屏；这里换成紧凑的弹层。
  /// 只到 28 号：29–31 号在有的月份不存在，交租日统一取 28 号以内。
  Future<void> _pickRentDueDay(BuildContext context) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      // 28 个日期在小屏上会超过默认的半个屏幕高度：放开高度上限并允许滚动
      isScrollControlled: true,
      backgroundColor: Z.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Z.rXl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('每月几号交租', style: ZText.title4),
                const SizedBox(height: 4),
                Text(
                  '点一个日期就选中；只到 28 号（有的月份没有 29–31 号）。',
                  style: ZText.caption,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var day = 1; day <= 28; day++)
                      ChoiceChip(
                        label: Text('$day'),
                        selected: _rentDueDay == day,
                        onSelected: (_) => Navigator.of(ctx).pop(day),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _rentDueDay = picked;
      _rentDueDayEdited = true;
    });
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.value, required this.onChanged});

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(DateTime.now().year - 20),
          lastDate: DateTime(DateTime.now().year + 30),
          locale: const Locale('zh', 'CN'),
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: Z.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Z.line),
        ),
        child: Row(
          children: [
            // 小屏 + 大字时日期会把格子撑破：让它缩到宽度内，别裁掉
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  fmtDate(value),
                  maxLines: 1,
                  style: ZText.mono.copyWith(fontSize: 13, color: Z.ink),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.calendar_today_outlined,
              size: 15,
              color: Z.ink4,
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个户型数字选择器：点击后从底部弹出数字选择
final class _LayoutWheel extends StatelessWidget {
  const _LayoutWheel({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  static const _options = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _show(context),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: Z.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Z.line),
        ),
        child: Row(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontFamily: Z.font,
                fontFamilyFallback: Z.fallback,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Z.ink,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: ZText.caption.copyWith(fontSize: 12),
            ),
            const Spacer(),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: Z.ink4,
            ),
          ],
        ),
      ),
    );
  }

  void _show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Z.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Z.rXl)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                child: ZSheetHeader(
                  title: '选择$label数',
                  onClose: () => Navigator.of(ctx).pop(),
                ),
              ),
              SizedBox(
                height: 220,
                child: ListView.builder(
                  itemCount: _options.length,
                  itemBuilder: (_, index) {
                    final option = _options[index];
                    final selected = option == value;
                    return InkWell(
                      onTap: () {
                        onChanged(option);
                        Navigator.of(ctx).pop();
                      },
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        color: selected ? Z.brandTint : Colors.transparent,
                        child: Text(
                          '$option $label',
                          style: TextStyle(
                            fontFamily: Z.font,
                            fontFamilyFallback: Z.fallback,
                            fontSize: 15,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? Z.brand : Z.ink2,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.step,
    required this.busy,
    required this.editing,
    required this.onBack,
    required this.onNext,
    required this.onSave,
  });

  final int step;
  final bool busy;
  final bool editing;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return ZBottomBar(
      child: Row(
        children: [
          if (step > 0) ...[
            SizedBox(
              width: 104,
              child: ZButton(
                label: '上一步',
                style: ZButtonStyle.ghost,
                onTap: onBack,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: ZButton(
              label: step < 3
                  ? '下一步'
                  : (busy ? '保存中…' : (editing ? '保存修改' : '保存并生成提醒计划')),
              // 下一步始终是主操作（品牌渐变），上一步保持次要样式
              style: ZButtonStyle.primary,
              onTap: busy ? null : (step < 3 ? onNext : onSave),
            ),
          ),
        ],
      ),
    );
  }
}
