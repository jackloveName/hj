import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../services/contract_scanner.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';
import '../media.dart';
import '../pickers.dart';
import 'property_edit_page.dart';

class ContractPage extends StatelessWidget {
  const ContractPage({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final property = repository.propertyById(propertyId);
    if (property == null) {
      return const ZScreen(child: SizedBox.shrink());
    }
    final contract = property.contract;
    // 没燃气表的房子不把燃气算进「待补」，不然这条提示永远消不掉
    final missingReadings = missingMoveInReadings(
      contract,
      repository.utilitiesOf(property.id),
      property.id,
    );
    final missing = <String>[
      if (contract.earlyTermination.isEmpty) '提前退租条件',
      if (contract.renewalTerms.isEmpty) '续租条款',
      if (contract.contractPhotoRefs.isEmpty) '合同照片',
    ];

    return ZScreen(
      // 已退租 / 纠纷中只读：没有「保存并生成提醒计划」这一步了
      bottomBar: canEditProperty(property)
          ? _BottomBar(property: property)
          : null,
      child: Column(
        children: [
          ZAppBar(
            leading: const ZBackButton(),
            title: '合同信息',
            actions: [
              InkWell(
                onTap: () => _scan(context, repository, property),
                child: ZPill(
                  label: '风险扫描',
                  background: Z.brandTint,
                  foreground: Z.brand,
                  icon: Icons.auto_awesome_outlined,
                ),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                const ZHintBar(
                  text: '填完自动生成 交租计划 与 到期倒计时，并写入本地提醒。',
                  icon: Icons.bolt_outlined,
                ),
                const ZSectionTitle(
                  title: '出租方',
                  icon: Icons.person_outline_rounded,
                ),
                ZCard(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  onTap: () =>
                      zPush(context, PropertyEditPage(propertyId: property.id)),
                  child: Column(
                    children: [
                      ZKv(label: '房东姓名', value: property.landlord.name),
                      ZKv(
                        label: '联系电话',
                        value: property.landlord.phone.isEmpty
                            ? '未填写'
                            : property.landlord.phone,
                        divider: property.landlord.wechat.isNotEmpty,
                      ),
                      if (property.landlord.wechat.isNotEmpty)
                        ZKv(
                          label: '微信 / 其他',
                          value: property.landlord.wechat,
                          divider: false,
                        ),
                    ],
                  ),
                ),
                const ZSectionTitle(
                  title: '金额与周期',
                  icon: Icons.account_balance_wallet_outlined,
                ),
                ZCard(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  onTap: () =>
                      zPush(context, PropertyEditPage(propertyId: property.id)),
                  child: Column(
                    children: [
                      ZKv(
                        label: '月租金额',
                        value: '${fmtMoney(contract.monthlyRent)} / 月',
                        valueColor: Z.ink,
                      ),
                      ZKv(
                        label: '押金金额',
                        value: fmtMoney(contract.deposit),
                        valueColor: Z.warnDeep,
                      ),
                      ZKv(
                        label: '付款方式',
                        value: contract.paymentMethod,
                        divider: false,
                      ),
                    ],
                  ),
                ),
                const ZSectionTitle(
                  title: '关键日期',
                  icon: Icons.event_available_outlined,
                ),
                ZCard(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  onTap: () =>
                      zPush(context, PropertyEditPage(propertyId: property.id)),
                  child: Column(
                    children: [
                      ZKv(
                        label: '入住日期',
                        value: fmtDate(contract.moveInDate),
                        mono: true,
                        valueColor: Z.ink,
                      ),
                      ZKv(
                        label: '合同到期',
                        value: fmtDate(contract.contractEnd),
                        mono: true,
                        valueColor: Z.ink,
                      ),
                      ZKv(
                        label: '交租日',
                        value: '每月 ${contract.rentDueDay} 号',
                      ),
                      ZKv(
                        label: '退租通知',
                        value: '需提前 ${contract.noticeDays} 天通知房东',
                      ),
                      ZKv(
                        label: '租住方式',
                        value: contract.rentScope,
                        divider: canEditProperty(property),
                      ),
                      // 续租：只改到期日（要涨租一起改），起租日与押金不动。
                      // 已退租 / 纠纷中是只读归档，不给这个入口
                      if (canEditProperty(property))
                        ZListRow(
                          icon: Icons.event_repeat_outlined,
                          title: '续租',
                          subtitle: '延长合同到期日，顺便改月租（涨租）',
                          onTap: () =>
                              _renew(context, repository, property),
                          divider: false,
                        ),
                    ],
                  ),
                ),
                ZSectionTitle(
                  title: '入住时的表底数',
                  icon: Icons.speed_outlined,
                  moreLabel: missingReadings == 0
                      ? '已填齐'
                      : '还有 $missingReadings 项待补',
                ),
                _MoveInReadings(
                  property: property,
                  editable: canEditProperty(property),
                ),
                ZSectionTitle(
                  title: '合同照片（选填）',
                  icon: Icons.image_outlined,
                  moreLabel: '${contract.contractPhotoRefs.length} / 6 页',
                ),
                _ContractPhotos(property: property),
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ZHintBar(
                    text: '未填写：${missing.join('、')} — 建议补全，否则退租时无据可依。',
                    tone: ZTone.warn,
                    icon: Icons.warning_amber_rounded,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 续租：只动「合同到期日」和「月租」，起租日、押金、押金状态都不碰。
  ///
  /// 保存后由 repository 按新的到期日把租金计划往后补齐（多出来的月份
  /// 会生成待付账单），不用再去「编辑房源」改一堆字段。
  Future<void> _renew(
    BuildContext context,
    Repository repository,
    Property property,
  ) async {
    final contract = property.contract;
    var end = contract.contractEnd;
    var rentText = fmtAmount(contract.monthlyRent);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 20 + bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('续租', style: ZText.title3.copyWith(fontSize: 17)),
                  const SizedBox(height: 6),
                  Text(
                    '现在到期日 ${fmtDate(contract.contractEnd)}：'
                    '改成新的到期日就行，起租日与押金不动。',
                    style: ZText.caption.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final picked = await pickDate(
                        ctx,
                        initial: end,
                        helpText: '选择新的到期日',
                      );
                      if (picked != null) setSheetState(() => end = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: '新的到期日',
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(fmtDate(end))),
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                            color: Z.ink3,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: rentText,
                    keyboardType: TextInputType.number,
                    onChanged: (text) => rentText = text,
                    decoration: const InputDecoration(
                      labelText: '月租（涨租就改这里）',
                      prefixText: '¥ ',
                    ),
                  ),
                  const SizedBox(height: 16),
                  ZButton(label: '保存续租', onTap: () => Navigator.of(ctx).pop(true)),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (saved != true) return;

    final rent = double.tryParse(rentText.trim()) ?? 0;
    if (!end.isAfter(contract.contractEnd)) {
      if (context.mounted) zToast(context, '新的到期日要晚于现在的到期日');
      return;
    }
    if (rent <= 0) {
      if (context.mounted) zToast(context, '月租要大于 0');
      return;
    }
    // 用仓库里最新那份当底：这一页的表底数是另外写盘的
    final latest = repository.propertyById(property.id) ?? property;
    await repository.updateProperty(
      latest.copyWith(
        contract: latest.contract.copyWith(
          contractEnd: end,
          monthlyRent: rent,
        ),
      ),
    );
    if (!context.mounted) return;
    zToast(
      context,
      '已续租到 ${fmtDate(end)}· 月租 ${fmtMoney(rent)}',
    );
  }

  Future<void> _scan(
    BuildContext context,
    Repository repository,
    Property property,
  ) async {
    final risks = scanContract(property.contract);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          children: [
            Text('合同风险扫描', style: ZText.title3.copyWith(fontSize: 17)),
            const SizedBox(height: 4),
            Text(
              risks.isEmpty
                  ? '未发现明显的风险关键词，仍建议逐条核对合同原文。'
                  : '共发现 ${risks.length} 处需要留意的地方',
              style: ZText.caption,
            ),
            const SizedBox(height: 14),
            for (final risk in risks)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ZTag.paletteOf(risk.tone).$1,
                    borderRadius: BorderRadius.circular(Z.rLg),
                    border: Border.all(
                      color: ZTag.paletteOf(risk.tone).$2
                          .withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ZTag(
                            label: switch (risk.tone) {
                              ZTone.danger => '高风险',
                              ZTone.warn => '需注意',
                              _ => '提示',
                            },
                            tone: risk.tone,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              risk.title,
                              style: ZText.label.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        risk.detail,
                        style: ZText.caption.copyWith(height: 1.5),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.tips_and_updates_outlined,
                            size: 15,
                            color: Z.brand,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              risk.advice,
                              style: ZText.body.copyWith(
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 入住时的三个表底数（电 / 水 / 燃气）：填完（失焦）自动存。
///
/// 抄表录入的首月用量拿它当基准，所以这里要能补、能改 ——
/// 首页那条「补填入住时的水/电表数」的待办点进来就是这儿。
///
/// 为什么不是「边敲边存」：每敲一个字符就整份数据落盘 + 全量重建太重，
/// 而且输入到一半的串（「1.2.3」这种）解析不出来，写进去等于把已填的值清掉。
/// 所以攒到失焦（或退出这个页面）才写，且只写解析成功的那一项。
class _MoveInReadings extends StatefulWidget {
  const _MoveInReadings({required this.property, required this.editable});

  final Property property;

  /// 已退租 / 纠纷中的房子只读：能看，不能改
  final bool editable;

  @override
  State<_MoveInReadings> createState() => _MoveInReadingsState();
}

class _MoveInReadingsState extends State<_MoveInReadings> {
  late final TextEditingController _electricity;
  late final TextEditingController _water;
  late final TextEditingController _gas;
  final List<FocusNode> _nodes = [FocusNode(), FocusNode(), FocusNode()];

  /// 最近一次和仓库对齐的三项值：用来判断「外部改了没」和「有没有变化」
  late (double?, double?, double?) _saved;
  bool _dirty = false;
  Repository? _repository;

  @override
  void initState() {
    super.initState();
    final contract = widget.property.contract;
    _saved = (
      contract.moveInElectricity,
      contract.moveInWater,
      contract.moveInGas,
    );
    _electricity = TextEditingController(text: _textOf(_saved.$1));
    _water = TextEditingController(text: _textOf(_saved.$2));
    _gas = TextEditingController(text: _textOf(_saved.$3));
    // 失焦就存：三个框都走同一条路，键盘上点「完成」、点别处、
    // 点页面底部那个按钮（默认会先让输入框失焦）都会落到这儿
    if (widget.editable) {
      for (final node in _nodes) {
        node.addListener(() {
          if (!node.hasFocus) _save();
        });
      }
    }
  }

  @override
  void dispose() {
    // 手还没离开输入框就退出页面（返回键）：把没存的补上，
    // 不然用户填的数字会静默丢掉
    if (widget.editable && _dirty) unawaited(_write());
    for (final node in _nodes) {
      node.dispose();
    }
    _electricity.dispose();
    _water.dispose();
    _gas.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repository = context.read<Repository>();
  }

  @override
  void didUpdateWidget(_MoveInReadings old) {
    super.didUpdateWidget(old);
    // 别处（云端同步、编辑房源）改过这三项时跟着刷新：
    // 否则页面还显示旧文本，下一次落盘会用旧值把新值盖回去
    final contract = widget.property.contract;
    final now = (
      contract.moveInElectricity,
      contract.moveInWater,
      contract.moveInGas,
    );
    if (now == _saved) return;
    _saved = now;
    _dirty = false;
    _electricity.text = _textOf(now.$1);
    _water.text = _textOf(now.$2);
    _gas.text = _textOf(now.$3);
  }

  /// 没抄过就留空框，别显示成 0（0 是「表上本来就是 0」）
  static String _textOf(double? value) => value == null ? '' : fmtAmount(value);

  /// 空框 = 没抄（null），不是 0；解析不出来（输入到一半 / 填了别的字符）
  /// 返回 [_unreadable]，交给调用方跳过这一项，别把已存的值清掉
  static const Object _unreadable = Object();

  static Object? _valueOf(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text) ?? _unreadable;
  }

  /// 失焦时调用：三个框的值和仓库里一致就什么都不做
  void _save() {
    if (!widget.editable) return;
    final repository = _repository;
    if (repository == null || !mounted) return;
    final contract = repository.propertyById(widget.property.id)?.contract;
    final current = contract == null
        ? _saved
        : (
            contract.moveInElectricity,
            contract.moveInWater,
            contract.moveInGas,
          );
    final typed = (_valueOf(_electricity), _valueOf(_water), _valueOf(_gas));
    final changed = [
      (!identical(typed.$1, _unreadable) && typed.$1 != current.$1),
      (!identical(typed.$2, _unreadable) && typed.$2 != current.$2),
      (!identical(typed.$3, _unreadable) && typed.$3 != current.$3),
    ].any((item) => item);
    if (!changed) {
      _dirty = false;
      return;
    }
    _dirty = true;
    unawaited(_write());
  }

  /// 真正落盘：用仓库里最新那份改（别拿 build 时捕获的旧对象覆盖别处改动），
  /// 并且不刷新 `updatedAt` —— 补个历史资料不该让首页押金「已等待 N 天」归零，
  /// 也不该把旧房源顶到历史列表前面去
  Future<void> _write() async {
    final repository = _repository;
    if (repository == null) return;
    // 用仓库里最新的那份，别拿 build 时捕获的旧对象覆盖别处的改动
    final property =
        repository.propertyById(widget.property.id) ?? widget.property;
    final contract = property.contract;
    final typed = (_valueOf(_electricity), _valueOf(_water), _valueOf(_gas));
    final next = contract.copyWith(
      moveInElectricity: identical(typed.$1, _unreadable)
          ? contract.moveInElectricity
          : typed.$1 as double?,
      moveInWater: identical(typed.$2, _unreadable)
          ? contract.moveInWater
          : typed.$2 as double?,
      moveInGas: identical(typed.$3, _unreadable)
          ? contract.moveInGas
          : typed.$3 as double?,
    );
    try {
      await repository.updateProperty(
        property.copyWith(contract: next),
        touch: false,
      );
      _saved = (next.moveInElectricity, next.moveInWater, next.moveInGas);
      _dirty = false;
    } catch (error) {
      // 静默失败过：用户以为存上了，退出再进才发现没有
      if (mounted) zToast(context, '表底数没存上：$error');
    }
  }

  Widget _field(
    TextEditingController controller,
    FocusNode node,
    String label,
  ) => Expanded(
    child: TextField(
      controller: controller,
      focusNode: node,
      readOnly: !widget.editable,
      keyboardType: TextInputType.number,
      onChanged: (_) => _dirty = true,
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ZCard(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 13),
      child: Row(
        children: [
          _field(_electricity, _nodes[0], '电表'),
          const SizedBox(width: 10),
          _field(_water, _nodes[1], '水表'),
          // 家里没有燃气表的，不摆这个框（要改去「编辑房源 → 有燃气表吗」）
          if (widget.property.contract.hasGasMeter) ...[
            const SizedBox(width: 10),
            _field(_gas, _nodes[2], '燃气表'),
          ],
        ],
      ),
    );
  }
}

class _ContractPhotos extends StatelessWidget {
  const _ContractPhotos({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final refs = property.contract.contractPhotoRefs;
    return Row(
      children: [
        for (var i = 0; i < refs.length; i++) ...[
          Expanded(
            child: InkWell(
              onTap: () => showPhoto(context, refs[i], title: '合同照片'),
              child: ZPhoto(
                ref: refs[i],
                height: 56,
                watermark: ['第 ${i + 1} 页'],
                // 读不到就用固定占位图（合同照片丢失也别写成「文件缺失」）
                fallback: const ZMissingPhoto(),
              ),
            ),
          ),
          const SizedBox(width: 7),
        ],
        // 已退租 / 纠纷中只读：照片能看，不能再加
        if (canEditProperty(property))
        Expanded(
          child: InkWell(
            onTap: () => _add(context),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Z.rSm),
                border: Border.all(color: Z.dashed, width: 1.4),
              ),
              child: Icon(Icons.add_rounded, size: 18, color: Z.ink4),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final repository = context.read<Repository>();
    final bytes = await pickImage(context);
    if (bytes == null) return;
    final ref = await repository.saveMedia(
      bytes,
      folder: property.id,
      name: 'contract_${newId('c')}.jpg',
    );
    await repository.updateProperty(
      property.copyWith(
        contract: property.contract.copyWith(
          contractPhotoRefs: [...property.contract.contractPhotoRefs, ref],
        ),
      ),
    );
    if (context.mounted) zToast(context, '合同照片已保存');
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    return ZBottomBar(
      child: ZButton(
        label: '保存并生成提醒计划',
        onTap: () async {
          final repository = context.read<Repository>();
          // 取仓库里最新那份：这一页上的表底数是另外写盘的，
          // 拿 build 时捕获的快照会把刚填进去的读数盖掉
          final latest =
              repository.propertyById(property.id) ?? property;
          await repository.updateProperty(latest);
          if (!context.mounted) return;
          zToast(
            context,
            '已生成：每月 ${latest.contract.rentDueDay} 号交租，'
            '${fmtDate(latest.contract.contractEnd)} 到期',
          );
        },
      ),
    );
  }
}
