import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';
import '../media.dart';
import 'annotation.dart';

class PhotoDetailPage extends StatelessWidget {
  const PhotoDetailPage({super.key, required this.photoId});

  final String photoId;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final photo = repository.photoById(photoId);
    if (photo == null) {
      return const ZScreen(
        child: ZEmpty(icon: Icons.image_not_supported_outlined, title: '照片不存在'),
      );
    }
    final property = repository.propertyById(photo.propertyId);
    // 已退租 / 纠纷中只读：照片能看，不能再标注、改说明、设封面、删除
    final editable = property == null || canEditProperty(property);

    return ZScreen(
      child: Column(
        children: [
          ZAppBar(
            leading: const ZBackButton(),
            // 「入住取证-客厅」：和相册页的标题格式保持一致
            title: '${photo.phase.label}-${photo.room}',
            actions: [
              ZIconButton(
                icon: Icons.zoom_out_map_rounded,
                tooltip: '全屏查看',
                onTap: () => showPhoto(
                  context,
                  photo.imageRef,
                  title: photo.issueType.label,
                  caption: photo.description,
                ),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Z.rMd),
                  child: AnnotatedPhoto(photo: photo),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    ZTag(
                      label:
                          '${photo.issueType.emoji} ${photo.issueType.label}',
                      tone: photo.issueType.tone,
                    ),
                    ZTag(label: photo.room),
                    if (photo.watermarked)
                      const ZTag(label: '已烧录水印', tone: ZTone.ok),
                    if (photo.annotations.isNotEmpty)
                      ZTag(label: '${photo.annotations.length} 处标注'),
                  ],
                ),
                const ZSectionTitle(
                  title: '存证信息',
                  icon: Icons.info_outline_rounded,
                ),
                ZCard(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: Column(
                    children: [
                      ZKv(
                        label: '拍摄时间',
                        value: fmtDateTime(photo.timestamp),
                        mono: true,
                      ),
                      ZKv(
                        label: '拍摄地点',
                        value: photo.location?.address.isNotEmpty == true
                            ? photo.location!.address
                            : '未记录',
                      ),
                      ZKv(
                        label: '图片尺寸',
                        value: photo.width > 0
                            ? '${photo.width} × ${photo.height}'
                            : '未知',
                      ),
                      ZKv(
                        label: '问题描述',
                        value: photo.description.isEmpty
                            ? '未填写'
                            : photo.description,
                        divider: false,
                      ),
                    ],
                  ),
                ),
                const ZSectionTitle(
                  title: '证据操作记录',
                  icon: Icons.history_rounded,
                ),
                ZCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in photo.auditLog)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: ZDot(color: Z.brand, size: 6),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  entry,
                                  style: ZText.caption.copyWith(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (editable)
                Row(
                  children: [
                    Expanded(
                      child: ZButton(
                        label: '追加标注',
                        style: ZButtonStyle.ghost,
                        icon: Icons.brush_outlined,
                        onTap: () => _annotate(context, repository, photo),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ZButton(
                        label: '修改说明',
                        style: ZButtonStyle.ghost,
                        icon: Icons.edit_note_outlined,
                        onTap: () => _edit(context, repository, photo),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (property != null && editable)
                  ZButton(
                    label: '设为房源封面',
                    style: ZButtonStyle.ghost,
                    icon: Icons.wallpaper_outlined,
                    onTap: () async {
                      await repository.updateProperty(
                        property.copyWith(coverRef: photo.thumbRef),
                      );
                      if (context.mounted) zToast(context, '已设为封面');
                    },
                  ),
                if (editable) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => _delete(context, repository, photo),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: Z.danger,
                    ),
                    label: const Text(
                      '删除照片',
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

  Future<void> _edit(
    BuildContext context,
    Repository repository,
    EvidencePhoto photo,
  ) async {
    // 别用 TextEditingController：下面这张 sheet 退场动画期间它一旦被 dispose，
    // TextField 重建就会红屏。初值交给 initialValue，输入用局部变量收。
    var typed = photo.description;
    var issue = photo.issueType;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 20 + bottom),
            // 键盘顶起来时内容要能滚（不然小屏上会 RenderFlex overflowed）
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text('修改问题说明', style: ZText.title3.copyWith(fontSize: 17)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in IssueType.values)
                      ChoiceChip(
                        label: Text('${type.emoji} ${type.label}'),
                        selected: issue == type,
                        onSelected: (_) => setSheetState(() => issue = type),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: photo.description,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: '补充说明这个问题'),
                  onChanged: (value) => typed = value,
                ),
                const SizedBox(height: 16),
                ZButton(label: '保存', onTap: () => Navigator.of(ctx).pop(true)),
              ],
              ),
            ),
          );
        },
      ),
    );
    if (saved == true) {
      await repository.updatePhoto(
        photo.copyWith(issueType: issue, description: typed.trim()),
        auditEntry: '更新问题说明为「${issue.label}」',
      );
      if (context.mounted) zToast(context, '已保存');
    }
  }

  Future<void> _annotate(
    BuildContext context,
    Repository repository,
    EvidencePhoto photo,
  ) async {
    final shapes = await showModalBottomSheet<List<AnnotationShape>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AnnotateSheet(photo: photo),
    );
    if (shapes == null) return;
    await repository.updatePhoto(
      photo.copyWith(annotations: shapes),
      auditEntry: '更新标注（共 ${shapes.length} 处）',
    );
    if (context.mounted) zToast(context, '标注已保存');
  }

  Future<void> _delete(
    BuildContext context,
    Repository repository,
    EvidencePhoto photo,
  ) async {
    final ok = await zConfirm(
      context,
      title: '删除取证照片',
      message: '删除后无法恢复，也不会出现在对比报告中。确定删除吗？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    await repository.deletePhoto(photo.id);
    MediaCache.evict(photo.imageRef);
    MediaCache.evict(photo.thumbRef);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _AnnotateSheet extends StatefulWidget {
  const _AnnotateSheet({required this.photo});

  final EvidencePhoto photo;

  @override
  State<_AnnotateSheet> createState() => _AnnotateSheetState();
}

class _AnnotateSheetState extends State<_AnnotateSheet> {
  late final List<AnnotationShape> _shapes = List<AnnotationShape>.from(
    widget.photo.annotations,
  );
  AnnotationShape? _draft;
  String _tool = 'circle';

  /// 四个工具：圆圈 / 箭头 / 画笔 / 文字
  static const List<(String, IconData, String)> _tools = [
    ('circle', Icons.circle_outlined, '圆圈'),
    ('arrow', Icons.north_east_rounded, '箭头'),
    ('free', Icons.gesture_rounded, '画笔'),
    ('text', Icons.text_fields_rounded, '文字'),
  ];

  @override
  Widget build(BuildContext context) {
    final ratio = widget.photo.width > 0 && widget.photo.height > 0
        ? widget.photo.width / widget.photo.height
        : 4 / 3;
    // 照片区域封顶；外面的 Flexible 再兜一层，竖图 + 小屏时也不会把
    // 标题、工具和底部按钮顶出屏幕
    final maxImageHeight = MediaQuery.sizeOf(context).height * 0.5;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('追加标注', style: ZText.title3.copyWith(fontSize: 17)),
                const Spacer(),
                TextButton(
                  onPressed: _shapes.isEmpty
                      ? null
                      : () => setState(() => _shapes.removeLast()),
                  child: const Text('撤销'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 工具栏：4 个 chip 在窄屏上会挤爆一行，用 Wrap 换行
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final tool in _tools)
                  ChoiceChip(
                    avatar: Icon(tool.$2, size: 14),
                    label: Text(tool.$3),
                    selected: _tool == tool.$1,
                    onSelected: (_) {
                      // 选工具时收起键盘：刚看完问题描述就直接在照片上画
                      FocusManager.instance.primaryFocus?.unfocus();
                      setState(() => _tool = tool.$1);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Flexible(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxImageHeight),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Z.rMd),
                    child: AspectRatio(
                      aspectRatio: ratio,
                      child: LayoutBuilder(
                        builder: (context, constraints) => Stack(
                          fit: StackFit.expand,
                          children: [
                            ZPhoto(
                              ref: widget.photo.imageRef,
                              fit: BoxFit.cover,
                              radius: 0,
                            ),
                            CustomPaint(
                              painter: AnnotationPainter(
                                shapes: [..._shapes, ?_draft],
                              ),
                            ),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (d) =>
                                  _start(d.localPosition, constraints.biggest),
                              onPanUpdate: (d) =>
                                  _update(d.localPosition, constraints.biggest),
                              onPanEnd: (_) => _end(),
                              onTapUp: (d) =>
                                  _tap(d.localPosition, constraints.biggest),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ZButton(
                    label: '取消',
                    style: ZButtonStyle.ghost,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ZButton(
                    label: '保存',
                    onTap: () => Navigator.of(context).pop(_shapes),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Offset _norm(Offset local, Size size) => Offset(
    (local.dx / size.width).clamp(0.0, 1.0),
    (local.dy / size.height).clamp(0.0, 1.0),
  );

  void _start(Offset local, Size size) {
    FocusManager.instance.primaryFocus?.unfocus();
    // 文字是「点一下放上去」，不跟着手指拖
    if (_tool == 'text') return;
    setState(() {
      _draft = AnnotationShape(
        type: _tool,
        points: [_norm(local, size)],
        colorValue: Z.cameraAnnotate.toARGB32(),
      );
    });
  }

  /// 文字工具：点图片上某个位置，输入内容后放在那里
  Future<void> _tap(Offset local, Size size) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_tool != 'text') return;
    // 弹窗里不用 controller：退场动画期间 dispose 会让输入框重建时红屏
    var typed = '';
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加文字标注'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: '如：墙面裂缝 12cm'),
          onChanged: (value) => typed = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('取消', style: TextStyle(color: Z.ink3)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(typed.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    final point = _norm(local, size);
    setState(() {
      _shapes.add(
        AnnotationShape(
          type: 'text',
          points: [point],
          text: text,
          colorValue: Z.cameraAnnotate.toARGB32(),
        ),
      );
    });
  }

  void _update(Offset local, Size size) {
    final draft = _draft;
    if (draft == null) return;
    final point = _norm(local, size);
    setState(() {
      _draft = _tool == 'free'
          ? draft.copyWith(points: [...draft.points, point])
          : AnnotationShape(
              type: draft.type,
              points: [draft.points.first, point],
              colorValue: draft.colorValue,
            );
    });
  }

  void _end() {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      if (draft.points.length >= 2) _shapes.add(draft);
      _draft = null;
    });
  }
}
