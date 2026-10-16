import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';
import '../media.dart';
import '../pickers.dart';

/// SCREEN 10 · 维修 · 沟通时间线
class TimelinePage extends StatefulWidget {
  const TimelinePage({
    super.key,
    required this.propertyId,
    this.initialTab = 0,
  });

  final String propertyId;

  /// 0 表示从「记维修」进入，1 表示从「记沟通」进入
  final int initialTab;

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  int _filter = 0;

  static const List<String> _filters = ['全部', '待处理', '处理中', '押金', '退租'];

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final repairs = repository.repairsOf(widget.propertyId);
    final comms = repository.commsOf(widget.propertyId);

    final entries = <_Entry>[
      for (final repair in repairs)
        _Entry(time: repair.reportedAt, repair: repair),
      for (final comm in comms) _Entry(time: comm.timestamp, comm: comm),
    ]..sort((a, b) => b.time.compareTo(a.time));

    final filtered = entries.where(_match).toList();
    final pending = repairs
        .where((r) => r.status == RepairStatus.pending)
        .length;
    final inProgress = repairs
        .where((r) => r.status == RepairStatus.inProgress)
        .length;
    // 已退租的房子是只读归档：底部不再给「记维修 / 记沟通」
    final property = repository.propertyById(widget.propertyId);
    final canAdd = property == null || canAddTimeline(property);

    return ZScreen(
      bottomBar: canAdd
          ? ZBottomBar(
              child: Row(
                children: [
                  Expanded(
                    child: ZButton(
                      label: '记维修',
                      style: ZButtonStyle.ghost,
                      icon: Icons.build_outlined,
                      onTap: () => _addRepair(context, repository),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ZButton(
                      label: '记沟通',
                      icon: Icons.chat_bubble_outline_rounded,
                      onTap: () => _addComm(context, repository),
                    ),
                  ),
                ],
              ),
            )
          : null,
      child: Column(
        children: [
          // 底部两个大按钮已经能记维修 / 记沟通，右上角的加号去掉
          const ZAppBar(leading: ZBackButton(), title: '维修与沟通'),
          if (!canAdd)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ZHintBar(
                text: '这套房子已退租：维修与沟通记录只能查看和导出，不能再新增。',
                icon: Icons.lock_outline_rounded,
              ),
            ),
          // tab 与标题之间留一点呼吸感，别贴着头部
          const SizedBox(height: 10),
          ZChips<int>(
            options: List<int>.generate(_filters.length, (index) => index),
            value: _filter,
            labelOf: (index) => switch (index) {
              1 => '待处理 $pending',
              2 => '处理中 $inProgress',
              _ => _filters[index],
            },
            onChanged: (value) => setState(() => _filter = value),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const ZEmpty(
                    icon: Icons.forum_outlined,
                    title: '还没有记录',
                    message: '报修进度、房东承诺都可以记在这里，\n退租时就是一条完整的时间线。',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) => _TimelineCard(
                      entry: filtered[index],
                      isLast: index == filtered.length - 1,
                      onTap: () => filtered[index].repair != null
                          ? _addRepair(
                              context,
                              repository,
                              record: filtered[index].repair,
                            )
                          : _addComm(
                              context,
                              repository,
                              record: filtered[index].comm,
                            ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  bool _match(_Entry entry) {
    final repair = entry.repair;
    final comm = entry.comm;
    switch (_filter) {
      case 1:
        return repair?.status == RepairStatus.pending;
      case 2:
        return repair?.status == RepairStatus.inProgress;
      case 3:
        return comm?.tags.contains('押金') ?? false;
      case 4:
        return comm?.tags.contains('退租') ?? false;
      default:
        return true;
    }
  }

  Future<void> _addRepair(
    BuildContext context,
    Repository repository, {
    RepairRecord? record,
  }) async {
    // 只读归档：已退租的房子不再允许新增维修（仍可查看与导出）
    if (record == null && !_canAdd(repository)) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RepairSheet(
        propertyId: widget.propertyId,
        repository: repository,
        existing: record,
      ),
    );
    if (saved == true && context.mounted) zToast(context, '已保存');
  }

  Future<void> _addComm(
    BuildContext context,
    Repository repository, {
    CommunicationRecord? record,
  }) async {
    if (record == null && !_canAdd(repository)) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CommSheet(
        propertyId: widget.propertyId,
        repository: repository,
        existing: record,
      ),
    );
    if (saved == true && context.mounted) zToast(context, '已保存');
  }

  /// 还能不能新增记录：已退租为只读；纠纷中仍可继续留证
  bool _canAdd(Repository repository) {
    final property = repository.propertyById(widget.propertyId);
    if (property != null && !canAddTimeline(property)) {
      zToast(context, '这套房子已退租，维修与沟通记录只能查看');
      return false;
    }
    return true;
  }
}

/// 时间轴的几何：圆点尺寸与竖线要对齐，竖线还要跨过卡片间距接到下一行
const double _railDotLeft = 10.5;
const double _railDotSize = 9;
const double _railWidth = 1.5;
const double _railTop = 16;

/// 卡片之间留的间距（与 [_TimelineCard] 的 Padding(bottom) 保持一致）
const double _railGap = 10;

class _Entry {
  const _Entry({required this.time, this.repair, this.comm});

  final DateTime time;
  final RepairRecord? repair;
  final CommunicationRecord? comm;
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.entry,
    required this.isLast,
    required this.onTap,
  });

  final _Entry entry;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final repair = entry.repair;
    final comm = entry.comm;
    final tone = repair?.status.tone ?? ZTone.brand;
    final dotColor = ZTag.paletteOf(tone).$2;

    return Padding(
      padding: const EdgeInsets.only(bottom: _railGap),
      // 用 Stack 让「卡片」决定整行高度：竖线铺满这一行，并向下延伸 10px 接上下一颗圆点。
      // 不能再用 Row + stretch + Expanded：列表里高度是无界的，会抛
      // 「BoxConstraints forces an infinite height」，整页因此卡死。
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: ZCard(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 第一行：类型 + 右侧状态（沟通的标签统一放到正文下面，
                  // 以前首个标签在这、其余标签在卡片底部，看着东一块西一块）
                  Row(
                    children: [
                      Text(
                        repair != null ? '维修' : '沟通',
                        style: ZText.label.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Z.ink2,
                        ),
                      ),
                      const Spacer(),
                      if (repair != null)
                        ZTag(label: repair.status.label, tone: tone)
                      else if (comm?.isKeyPromise == true)
                        const ZTag(label: '关键承诺', tone: ZTone.brand),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 第二行：维修是「物品 + 描述」，沟通是整段文字记录
                  if (repair != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ZTag(label: repair.item, tone: tone),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            repair.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: ZText.body.copyWith(
                              fontSize: 12.5,
                              height: 1.5,
                              color: Z.ink,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    // 以前只取第一行，多行记录等于没显示出来
                    Text(
                      comm?.content ?? '',
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: ZText.body.copyWith(
                        fontSize: 12.5,
                        height: 1.6,
                        color: Z.ink,
                      ),
                    ),
                  // 第三行：照片证据 / 聊天截图（有才显示）
                  if (repair != null && repair.photoRefs.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _EvidenceStrip(
                      refs: repair.photoRefs,
                      title: '维修证据',
                      size: 46,
                    ),
                  ],
                  if (comm != null && comm.screenshotRefs.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _EvidenceStrip(
                      refs: comm.screenshotRefs,
                      title: '聊天截图',
                      size: 68,
                    ),
                  ],
                  if (comm != null && comm.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in comm.tags) ZTag(label: tag),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  // 第四段：时间 / 费用 / 承担方
                  if (repair != null) ...[
                    ZKv(
                      label: '维修时间',
                      value: fmtDate(repair.completedAt ?? repair.reportedAt),
                    ),
                    ZKv(label: '维修费用', value: fmtMoney(repair.cost)),
                    ZKv(
                      label: '承担方',
                      value: repair.costPaidBy.label,
                      divider: false,
                    ),
                  ] else ...[
                    ZKv(
                      label: '沟通时间',
                      value: fmtDate(comm!.timestamp),
                      divider: false,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!isLast)
            Positioned(
              // 竖线的几何：从本行圆点下沿一直连到「下一行圆点的中心」。
              // 卡片之间有 _railGap 的间距，所以线必须多伸出去
              // _railGap + _railTop + 半个圆点，否则中间就会断开。
              left: _railDotLeft + _railDotSize / 2 - _railWidth / 2,
              top: _railTop + _railDotSize,
              bottom: -(_railGap + _railTop + _railDotSize / 2),
              child: Container(width: _railWidth, color: Z.line),
            ),
          Positioned(
            left: _railDotLeft,
            top: _railTop,
            child: Container(
              width: _railDotSize,
              height: _railDotSize,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 证据缩略图条：维修照片与聊天截图共用；超过 3 张时显示 +N
class _EvidenceStrip extends StatelessWidget {
  const _EvidenceStrip({
    required this.refs,
    required this.title,
    required this.size,
  });

  final List<String> refs;
  final String title;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      child: Row(
        children: [
          for (var i = 0; i < refs.length && i < 3; i++) ...[
            InkWell(
              onTap: () => showPhoto(context, refs[i], title: title),
              child: ZPhoto(ref: refs[i], width: size, height: size),
            ),
            const SizedBox(width: 6),
          ],
          if (refs.length > 3)
            Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Z.line3,
                borderRadius: BorderRadius.circular(Z.rSm),
              ),
              child: Text(
                '+${refs.length - 3}',
                style: ZText.small.copyWith(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _RepairSheet extends StatefulWidget {
  const _RepairSheet({
    required this.propertyId,
    required this.repository,
    this.existing,
  });

  final String propertyId;
  final Repository repository;
  final RepairRecord? existing;

  @override
  State<_RepairSheet> createState() => _RepairSheetState();
}

class _RepairSheetState extends State<_RepairSheet> {
  late final TextEditingController _description = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final TextEditingController _cost = TextEditingController(
    text: (widget.existing?.cost ?? 0) == 0
        ? ''
        : fmtAmount(widget.existing!.cost),
  );
  late String _item = widget.existing?.item ?? RepairRecord.commonItems.first;

  /// 「报修物品」选「其他」时手输的名称
  late final TextEditingController _itemOther = TextEditingController(
    text: RepairRecord.commonItems.contains(widget.existing?.item ?? '')
        ? ''
        : (widget.existing?.item ?? ''),
  );

  /// 下拉框显示值：自定义名称时回到「其他」
  String get _itemChip =>
      RepairRecord.commonItems.contains(_item) ? _item : '其他';

  /// 是否要手输名称
  bool get _itemCustomMode =>
      _item == '其他' || !RepairRecord.commonItems.contains(_item);
  late RepairStatus _status = widget.existing?.status ?? RepairStatus.pending;
  late CostBearer _bearer = widget.existing?.costPaidBy ?? CostBearer.undecided;
  late final List<String> _photos = List<String>.from(
    widget.existing?.photoRefs ?? const [],
  );

  @override
  void dispose() {
    _description.dispose();
    _cost.dispose();
    _itemOther.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ZSheetHeader(
              title: widget.existing == null ? '记一笔维修' : '维修详情',
            ),
            const SizedBox(height: 8),
            ZField(
              label: '报修物品',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Z.card,
                  borderRadius: Z.radiusField,
                  border: Border.all(color: Z.line),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _itemChip,
                    isExpanded: true,
                    items: [
                      for (final item in RepairRecord.commonItems)
                        DropdownMenuItem(value: item, child: Text(item)),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _item = value);
                    },
                  ),
                ),
              ),
            ),
            if (_itemCustomMode)
              ZField(
                label: '物品名称',
                child: TextField(
                  controller: _itemOther,
                  onChanged: (value) => setState(
                    () => _item = value.trim().isEmpty ? '其他' : value.trim(),
                  ),
                  decoration: const InputDecoration(hintText: '如：阳台晾衣架'),
                ),
              ),
            ZField(
              label: '问题描述',
              child: TextField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '如：热水器不出热水，已微信报修房东',
                ),
              ),
            ),
            ZField(
              label: '处理状态',
              child: ZChips<RepairStatus>(
                options: RepairStatus.values,
                value: _status,
                emphasize: true,
                padding: EdgeInsets.zero,
                labelOf: (value) => value.label,
                onChanged: (value) => setState(() => _status = value),
              ),
            ),
            ZField(
              label: '维修费用',
              child: TextField(
                controller: _cost,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(prefixText: '¥ '),
              ),
            ),
            ZField(
              label: '承担方',
              // 用换行的 chip：四个选项一眼全看到，不用横向滑（滑出去的那个等于没有）
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final bearer in CostBearer.values)
                    ChoiceChip(
                      label: Text(bearer.label),
                      selected: _bearer == bearer,
                      showCheckmark: true,
                      checkmarkColor: Z.page,
                      onSelected: (_) => setState(() => _bearer = bearer),
                    ),
                ],
              ),
            ),
            ZField(
              label: '照片证据',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final ref in _photos)
                    Stack(
                      children: [
                        ZPhoto(ref: ref, width: 68, height: 68),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: InkWell(
                            onTap: () => setState(() => _photos.remove(ref)),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Z.photoScrim,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  InkWell(
                    onTap: _addPhoto,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Z.rSm),
                        border: Border.all(color: Z.line),
                      ),
                      child: Icon(
                        Icons.add_a_photo_outlined,
                        size: 18,
                        color: Z.ink4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.existing != null) ...[
                  Expanded(
                    child: ZButton(
                      label: '删除',
                      style: ZButtonStyle.ghost,
                      onTap: _delete,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: ZButton(label: '保存', onTap: _save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPhoto() async {
    final bytes = await pickImage(context);
    if (bytes == null) return;
    final ref = await widget.repository.saveMedia(
      bytes,
      folder: widget.propertyId,
      name: 'repair_${newId('rp')}.jpg',
    );
    if (mounted) setState(() => _photos.add(ref));
  }

  Future<void> _save() async {
    final existing = widget.existing;
    await widget.repository.saveRepair(
      RepairRecord(
        id: existing?.id ?? newId('repair'),
        propertyId: widget.propertyId,
        item: _item,
        description: _description.text.trim(),
        photoRefs: _photos,
        reportedAt: existing?.reportedAt ?? DateTime.now(),
        status: _status,
        completedAt:
            // 重复保存已完成的记录时，保留原始完成时间
            _status == RepairStatus.completed
            ? (existing?.completedAt ?? DateTime.now())
            : null,
        costPaidBy: _bearer,
        cost: double.tryParse(_cost.text.trim()) ?? 0,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    await widget.repository.deleteRepair(existing.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }
}

class _CommSheet extends StatefulWidget {
  const _CommSheet({
    required this.propertyId,
    required this.repository,
    this.existing,
  });

  final String propertyId;
  final Repository repository;
  final CommunicationRecord? existing;

  @override
  State<_CommSheet> createState() => _CommSheetState();
}

class _CommSheetState extends State<_CommSheet> {
  /// 「其他」标签的手输名称
  final TextEditingController _tagOther = TextEditingController();
  late final TextEditingController _content = TextEditingController(
    text: widget.existing?.content ?? '',
  );
  late final List<String> _tags = List<String>.from(
    widget.existing?.tags ?? const [],
  );
  late final List<String> _shots = List<String>.from(
    widget.existing?.screenshotRefs ?? const [],
  );
  late bool _promise = widget.existing?.isKeyPromise ?? false;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ZSheetHeader(
              title: widget.existing == null ? '记一次沟通' : '沟通详情',
            ),
            const SizedBox(height: 8),
            ZField(
              label: '沟通内容',
              child: TextField(
                controller: _content,
                maxLines: 4,
                decoration: const InputDecoration(hintText: '如：房东承诺退租时全额退还押金'),
              ),
            ),
            ZField(
              // 多选：选中态给勾，避免看不出「可以同时选好几个」
              label: '标签（可多选）',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in CommunicationRecord.tagOptions)
                    FilterChip(
                      label: Text(tag),
                      selected: _tags.contains(tag),
                      showCheckmark: true,
                      checkmarkColor: Z.page,
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _tags.add(tag);
                        } else {
                          _tags.remove(tag);
                          // 取消「其他」时把自定义标签一起清掉
                          if (tag == '其他') {
                            _tags.removeWhere(
                              (item) =>
                                  !CommunicationRecord.tagOptions.contains(item),
                            );
                          }
                        }
                      }),
                    ),
                ],
              ),
            ),
            if (_tags.contains('其他'))
              ZField(
                label: '自定义标签',
                child: TextField(
                  controller: _tagOther,
                  onChanged: (value) => setState(() {
                    // 输入即替换上一条自定义标签，保存时无需再特殊处理
                    _tags.removeWhere(
                      (item) => !CommunicationRecord.tagOptions.contains(item),
                    );
                    final text = value.trim();
                    if (text.isNotEmpty) _tags.add(text);
                  }),
                  decoration: const InputDecoration(hintText: '如：宠物押金'),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _promise,
              onChanged: (value) => setState(() => _promise = value),
              title: Text('标记为关键承诺', style: ZText.label.copyWith(fontSize: 14)),
              subtitle: Text('退租时可直接作为反驳依据', style: ZText.small),
            ),
            ZField(
              label: '聊天截图',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final ref in _shots)
                    Stack(
                      children: [
                        ZPhoto(ref: ref, width: 68, height: 68),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: InkWell(
                            onTap: () => setState(() => _shots.remove(ref)),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Z.photoScrim,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  InkWell(
                    onTap: _addShot,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Z.rSm),
                        border: Border.all(color: Z.line),
                      ),
                      child: Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 18,
                        color: Z.ink4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.existing != null) ...[
                  Expanded(
                    child: ZButton(
                      label: '删除',
                      style: ZButtonStyle.ghost,
                      onTap: _delete,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: ZButton(label: '保存', onTap: _save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addShot() async {
    final items = await pickImages(context);
    if (items.isEmpty) return;
    for (final bytes in items) {
      final ref = await widget.repository.saveMedia(
        bytes,
        folder: widget.propertyId,
        name: 'chat_${newId('c')}.jpg',
      );
      _shots.add(ref);
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_content.text.trim().isEmpty && _shots.isEmpty) {
      zToast(context, '请填写内容或上传截图');
      return;
    }
    final existing = widget.existing;
    await widget.repository.saveComm(
      CommunicationRecord(
        id: existing?.id ?? newId('comm'),
        propertyId: widget.propertyId,
        type: _shots.isEmpty ? CommType.text : CommType.screenshot,
        content: _content.text.trim(),
        screenshotRefs: _shots,
        tags: _tags,
        timestamp: existing?.timestamp ?? DateTime.now(),
        isKeyPromise: _promise,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    await widget.repository.deleteComm(existing.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }
}
