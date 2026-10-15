import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../services/watermark.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';
import '../media.dart';
import '../pickers.dart';
import 'annotation.dart';

/// SCREEN 04 · 取证相机 · 标注水印（全屏深色沉浸）
class CapturePage extends StatefulWidget {
  const CapturePage({
    super.key,
    required this.propertyId,
    required this.room,
    required this.phase,
    required this.bytes,
  });

  final String propertyId;
  final String room;
  final PhotoPhase phase;
  final Uint8List bytes;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  late Uint8List _bytes = widget.bytes;
  late DateTime _capturedAt = DateTime.now();

  /// 原图尺寸：用于让预览区保持与照片一致的宽高比，标注坐标才能一一对应
  Size? _imageSize;
  final TextEditingController _description = TextEditingController();
  final TextEditingController _location = TextEditingController();
  String? _defaultLocation;
  final List<AnnotationShape> _shapes = <AnnotationShape>[];
  AnnotationShape? _draft;
  IssueType _issue = IssueType.none;
  String _tool = 'circle';
  int _color = 0xFFFF4D4F;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _resolveImageSize(_bytes);
  }

  @override
  void dispose() {
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  void _initDefaultLocation() {
    if (_defaultLocation != null) return;
    final property =
        context.read<Repository>().propertyById(widget.propertyId);
    final address = property?.address.trim() ?? '';
    if (address.isNotEmpty) {
      _defaultLocation = address;
      _location.text = address;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initDefaultLocation();
  }

  Future<void> _resolveImageSize(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      descriptor.dispose();
      buffer.dispose();
      if (mounted) setState(() => _imageSize = size);
    } catch (_) {
      // 解析失败时退回 4:3，不影响存证
    }
  }

  List<String> get _watermarkLines => [
    '拍摄时间：${fmtDateTime(_capturedAt)}',
    if (_location.text.trim().isNotEmpty) '拍摄地点：${_location.text.trim()}',
    '房　间：${widget.room} · ${widget.phase.label}',
    if (_issue != IssueType.none)
      '问　题：${_issue.label}'
          '${_description.text.trim().isEmpty ? '' : ' · ${_description.text.trim()}'}',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Z.camera,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(child: _photoArea()),
            _issueChips(),
            _toolRow(),
            _bottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 19, color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.room,
                style: const TextStyle(
                  fontFamily: Z.font,
                  fontFamilyFallback: Z.fallback,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              Text(
                '${widget.phase.label} · 已标注 ${_shapes.length} 处',
                style: const TextStyle(
                  fontFamily: Z.font,
                  fontFamilyFallback: Z.fallback,
                  fontSize: 11,
                  color: Color(0xA6FFFFFF),
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x24FFFFFF),
              borderRadius: BorderRadius.circular(100),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 11, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  '不可编辑',
                  style: TextStyle(
                    fontFamily: Z.font,
                    fontFamilyFallback: Z.fallback,
                    fontSize: 11,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoArea() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final imageSize = _imageSize;
          final ratio = imageSize == null || imageSize.height <= 0
              ? 4 / 3
              : imageSize.width / imageSize.height;
          var width = constraints.maxWidth;
          var height = width / ratio;
          if (height > constraints.maxHeight) {
            height = constraints.maxHeight;
            width = height * ratio;
          }
          final boxSize = Size(width, height);
          return Center(
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    _bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                  CustomPaint(
                    painter: AnnotationPainter(shapes: [..._shapes, ?_draft]),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) =>
                        _onStart(details.localPosition, boxSize),
                    onPanUpdate: (details) =>
                        _onUpdate(details.localPosition, boxSize),
                    onPanEnd: (_) => _onEnd(),
                    onTapUp: (details) =>
                        _onTap(details.localPosition, boxSize),
                  ),
                  if (_issue != IssueType.none)
                    Positioned(
                      left: 9,
                      top: 9,
                      child: ZPill(
                        label: '${_issue.emoji} ${_issue.label}',
                        background: const Color(0xE6E04145),
                        foreground: Colors.white,
                      ),
                    ),
                  const Positioned(
                    right: 9,
                    top: 9,
                    child: ZPill(
                      label: '已定位',
                      background: Color(0xB80A0F1A),
                      foreground: Colors.white,
                      icon: Icons.my_location_rounded,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ZWatermarkBar(lines: _watermarkLines),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _issueChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: IssueType.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final type = IssueType.values[index];
          final selected = _issue == type;
          return InkWell(
            borderRadius: BorderRadius.circular(100),
            onTap: () => setState(() {
              _issue = type;
              _color = type == IssueType.none
                  ? 0xFF2F6BFF
                  : (type.tone == ZTone.warn ? 0xFFE08600 : 0xFFFF4D4F);
            }),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: selected ? const Color(0x38E04145) : Z.onDarkChip,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: selected
                      ? const Color(0x73E04145)
                      : const Color(0x21FFFFFF),
                ),
              ),
              child: Text(
                '${type.emoji} ${type.label}',
                style: TextStyle(
                  fontFamily: Z.font,
                  fontFamilyFallback: Z.fallback,
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? const Color(0xFFFF7B7D)
                      : const Color(0xFF9AA5BC),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _toolRow() {
    final tools = <(String, IconData, String)>[
      ('circle', Icons.circle_outlined, '圆圈'),
      ('arrow', Icons.north_east_rounded, '箭头'),
      ('free', Icons.gesture_rounded, '画笔'),
      ('text', Icons.text_fields_rounded, '文字'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          for (final tool in tools) ...[
            InkWell(
              borderRadius: BorderRadius.circular(100),
              onTap: () => setState(() => _tool = tool.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _tool == tool.$1
                      ? const Color(0x332F6BFF)
                      : Z.onDarkChip,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: _tool == tool.$1
                        ? const Color(0x662F6BFF)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      tool.$2,
                      size: 13,
                      color: _tool == tool.$1
                          ? const Color(0xFF7FA8FF)
                          : Z.cameraText,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tool.$3,
                      style: TextStyle(
                        fontFamily: Z.font,
                        fontFamilyFallback: Z.fallback,
                        fontSize: 11,
                        color: _tool == tool.$1
                            ? const Color(0xFF7FA8FF)
                            : Z.cameraText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          const Spacer(),
          InkWell(
            onTap: _shapes.isEmpty
                ? null
                : () => setState(() => _shapes.removeLast()),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.undo_rounded, size: 17, color: Z.cameraText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    final repository = context.read<Repository>();
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Z.camera,
        border: Border(top: BorderSide(color: Z.onDarkChip)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _description,
            style: const TextStyle(
              fontFamily: Z.font,
              fontFamilyFallback: Z.fallback,
              fontSize: 13,
              color: Z.cameraChip,
            ),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              filled: true,
              fillColor: Z.onDarkChip,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              hintText: '问题描述（会写进水印）',
              hintStyle: const TextStyle(
                fontFamily: Z.font,
                fontFamilyFallback: Z.fallback,
                fontSize: 12,
                color: Z.cameraText,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Z.onDarkLine),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Z.onDarkLine),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _location,
            style: const TextStyle(
              fontFamily: Z.font,
              fontFamilyFallback: Z.fallback,
              fontSize: 13,
              color: Z.cameraChip,
            ),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              filled: true,
              fillColor: Z.onDarkChip,
              isDense: true,
              prefixIcon: const Icon(
                Icons.place_outlined,
                size: 15,
                color: Z.cameraText,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              hintText: '拍摄地点（默认为房子地址）',
              hintStyle: const TextStyle(
                fontFamily: Z.font,
                fontFamilyFallback: Z.fallback,
                fontSize: 12,
                color: Z.cameraText,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Z.onDarkLine),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Z.onDarkLine),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 96,
                child: GestureDetector(
                  onTap: _replace,
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Z.onDarkChip,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          size: 15,
                          color: Z.cameraText,
                        ),
                        SizedBox(width: 5),
                        Text(
                          '重拍',
                          style: TextStyle(
                            fontFamily: Z.font,
                            fontFamilyFallback: Z.fallback,
                            fontSize: 12,
                            color: Z.cameraText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ZButton(
                  label: _busy ? '正在保存…' : '保存',
                  onTap: _busy ? null : () => _save(repository),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Offset _normalize(Offset local, Size size) => Offset(
    (local.dx / size.width).clamp(0.0, 1.0),
    (local.dy / size.height).clamp(0.0, 1.0),
  );

  void _onStart(Offset local, Size size) {
    if (_tool == 'text') return;
    setState(() {
      _draft = AnnotationShape(
        type: _tool,
        points: [_normalize(local, size)],
        colorValue: _color,
      );
    });
  }

  void _onUpdate(Offset local, Size size) {
    final draft = _draft;
    if (draft == null) return;
    final point = _normalize(local, size);
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

  void _onEnd() {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      if (draft.points.length >= 2) _shapes.add(draft);
      _draft = null;
    });
  }

  Future<void> _onTap(Offset local, Size size) async {
    if (_tool != 'text') return;
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加文字标注'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '如：墙面裂缝 12cm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('取消', style: TextStyle(color: Z.ink3)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty) return;
    setState(() {
      _shapes.add(
        AnnotationShape(
          type: 'text',
          points: [_normalize(local, size)],
          text: text,
          colorValue: _color,
        ),
      );
    });
  }

  Future<void> _replace() async {
    final bytes = await pickImage(context);
    if (bytes == null) return;
    setState(() {
      _bytes = bytes;
      _capturedAt = DateTime.now();
      _shapes.clear();
    });
    // 计算原图尺寸只是为了让标注坐标正确，不阻塞照片展示
    unawaited(_resolveImageSize(bytes));
  }

  Future<void> _save(Repository repository) async {
    setState(() => _busy = true);
    final now = _capturedAt;
    try {
      final processed = await WatermarkService.process(
        source: _bytes,
        lines: _watermarkLines,
      );
      final token = newId('img');
      final imageRef = await repository.saveMedia(
        processed.image,
        folder: widget.propertyId,
        name: '$token.jpg',
      );
      final thumbRef = await repository.saveMedia(
        processed.thumb,
        folder: widget.propertyId,
        name: 'thumb_$token.jpg',
      );
      await repository.addPhoto(
        EvidencePhoto(
          id: newId('photo'),
          propertyId: widget.propertyId,
          room: widget.room,
          imageRef: imageRef,
          thumbRef: thumbRef,
          timestamp: now,
          location: _location.text.trim().isEmpty
              ? null
              : GeoLocation(address: _location.text.trim()),
          issueType: _issue,
          description: _description.text.trim(),
          annotations: _shapes,
          phase: widget.phase,
          width: processed.width,
          height: processed.height,
          auditLog: ['${fmtDateTime(now)} 拍摄并烧录水印存证'],
        ),
      );
      if (!mounted) return;
      // 存证成功但底层存储异常（例如浏览器容量不足）时给用户明确提示
      final warning = repository.lastError;
      repository.clearError();
      Navigator.of(context).pop();
      zToast(context, warning ?? '已保存 · 照片不可再修改');
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        zToast(context, '存证失败：$error');
      }
    }
  }
}
