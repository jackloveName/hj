import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../services/pdf_service.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../evidence/annotation.dart';
import '../evidence/evidence_rooms_page.dart';
import '../kit.dart';
import '../media.dart';

/// SCREEN 05 · 退租对比 · 维权核心
class ComparePage extends StatefulWidget {
  const ComparePage({super.key, required this.propertyId});

  final String propertyId;

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  final Map<String, String> _moveIn = <String, String>{};
  final Map<String, String> _moveOut = <String, String>{};
  final Map<String, TextEditingController> _notes =
      <String, TextEditingController>{};
  final TextEditingController _conclusion = TextEditingController();
  String? _room;
  bool _busy = false;

  @override
  void dispose() {
    for (final controller in _notes.values) {
      controller.dispose();
    }
    _conclusion.dispose();
    super.dispose();
  }

  TextEditingController _noteFor(String room) => _notes.putIfAbsent(
    room,
    () => TextEditingController(
      text:
          '$room 的瑕疵于入住拍照时即已存在，退租拍照位置、长度、走向一致，'
          '期间无扩大。依据《民法典》第 714 条，合理损耗不应从押金中扣除。',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final property = repository.propertyById(widget.propertyId);
    if (property == null) return const ZScreen(child: SizedBox.shrink());

    final rooms = property.allRooms.where((room) {
      return repository.photoCountOf(
                property.id,
                phase: PhotoPhase.moveIn,
                room: room,
              ) >
              0 ||
          repository.photoCountOf(
                property.id,
                phase: PhotoPhase.moveOut,
                room: room,
              ) >
              0;
    }).toList();

    if (rooms.isEmpty) {
      return ZScreen(
        child: Column(
          children: [
            const ZAppBar(title: '退租对比', leading: ZBackButton()),
            Expanded(
              child: ZEmpty(
                icon: Icons.compare_arrows_rounded,
                title: '还没有对比素材',
                message: '先完成入住取证；退租时再拍一套，这里会自动做左右对照。',
                actionLabel: '去退租取证',
                onAction: () => zPush(
                  context,
                  EvidenceRoomsPage(
                    propertyId: property.id,
                    initialPhase: PhotoPhase.moveOut,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final current = _room ?? rooms.first;
    _room = current;
    final inPhoto = _pick(
      repository.photosOf(property.id, phase: PhotoPhase.moveIn, room: current),
      _moveIn[current],
    );
    final outPhoto = _pick(
      repository.photosOf(
        property.id,
        phase: PhotoPhase.moveOut,
        room: current,
      ),
      _moveOut[current],
    );

    return ZScreen(
      bottomBar: ZBottomBar(
        child: Row(
          children: [
            SizedBox(
              width: 108,
              child: ZButton(
                label: '整套房汇总',
                style: ZButtonStyle.ghost,
                onTap: () => _export(context, repository, property, rooms),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ZButton(
                label: _busy ? '生成中…' : '导出对比报告 PDF',
                style: ZButtonStyle.dark,
                icon: Icons.download_rounded,
                onTap: _busy
                    ? null
                    : () => _export(context, repository, property, rooms),
              ),
            ),
          ],
        ),
      ),
      child: Column(
        children: [
          ZAppBar(
            leading: const ZBackButton(),
            title: '退租对比',
            actions: [
              ZIconButton(
                icon: Icons.ios_share,
                tooltip: '导出报告',
                onTap: () => _export(context, repository, property, rooms),
              ),
            ],
          ),
          ZChips<String>(
            options: rooms,
            value: current,
            emphasize: true,
            labelOf: (value) => value,
            onChanged: (value) => setState(() => _room = value),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                ZCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _Side(
                              label: '入住时',
                              dotColor: Z.ok,
                              photo: inPhoto,
                              onPick: () => _choose(
                                context,
                                repository,
                                property,
                                current,
                                true,
                              ),
                            ),
                          ),
                          Container(width: 1, color: Z.line),
                          Expanded(
                            child: _Side(
                              label: '退租时',
                              dotColor: Z.violet,
                              photo: outPhoto,
                              onPick: () => _choose(
                                context,
                                repository,
                                property,
                                current,
                                false,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _judgement(inPhoto, outPhoto),
                    ],
                  ),
                ),
                const ZSectionTitle(
                  title: '对比说明（可编辑）',
                  icon: Icons.description_outlined,
                ),
                ZCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _noteFor(current),
                        maxLines: 5,
                        style: ZText.body.copyWith(fontSize: 13, height: 1.6),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          hintText: '补充对比说明',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ZTag(label: '引用法条', tone: ZTone.brand),
                          ZTag(label: '插入模板'),
                          ZTag(label: '一键复制'),
                        ],
                      ),
                    ],
                  ),
                ),
                const ZSectionTitle(
                  title: '综合说明',
                  icon: Icons.edit_note_outlined,
                ),
                ZCard(
                  child: TextField(
                    controller: _conclusion,
                    maxLines: 4,
                    style: ZText.body.copyWith(fontSize: 13, height: 1.6),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hintText: '例如：以上问题均为入住时已存在的瑕疵，有入住取证照片为证。',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _judgement(EvidencePhoto? inPhoto, EvidencePhoto? outPhoto) {
    if (inPhoto == null || outPhoto == null) {
      return ZHintBar(
        text: outPhoto == null
            ? '系统判定：等待退租取证 —— 补拍同一位置后自动比对'
            : '系统判定：缺少入住照片 —— 无法证明瑕疵在入住前已存在',
        tone: ZTone.warn,
        icon: Icons.hourglass_empty_rounded,
      );
    }
    final same = inPhoto.issueType == outPhoto.issueType;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: same ? const Color(0x1712A150) : const Color(0x1FE08600),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            same
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded,
            size: 16,
            color: same ? Z.ok : Z.warnDeep,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  same ? '系统判定：非租户造成' : '系统判定：需人工核对',
                  style: ZText.label.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: same ? Z.okDeep : Z.warnDeep,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  same ? '两期问题类型一致，可主张合理损耗不扣押金' : '两期问题类型不一致，请核对是否为新增损坏',
                  style: ZText.small.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  EvidencePhoto? _pick(List<EvidencePhoto> photos, String? id) {
    if (photos.isEmpty) return null;
    if (id == null) return photos.first;
    for (final photo in photos) {
      if (photo.id == id) return photo;
    }
    return photos.first;
  }

  Future<void> _choose(
    BuildContext context,
    Repository repository,
    Property property,
    String room,
    bool isMoveIn,
  ) async {
    final photos = repository.photosOf(
      property.id,
      phase: isMoveIn ? PhotoPhase.moveIn : PhotoPhase.moveOut,
      room: room,
    );
    if (photos.isEmpty) {
      zToast(context, isMoveIn ? '该房间还没有入住照片' : '该房间还没有退租照片');
      return;
    }
    final picked = await showModalBottomSheet<EvidencePhoto>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            Text(
              isMoveIn ? '选择入住照片' : '选择退租照片',
              style: ZText.title3.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 10),
            for (final photo in photos)
              ListTile(
                leading: ZPhoto(ref: photo.thumbRef, width: 48, height: 48),
                title: Text(
                  '${photo.issueType.emoji} ${photo.issueType.label}',
                  style: ZText.label.copyWith(fontSize: 13),
                ),
                subtitle: Text(
                  fmtDateTime(photo.timestamp),
                  style: ZText.small.copyWith(fontSize: 11),
                ),
                onTap: () => Navigator.of(ctx).pop(photo),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isMoveIn) {
        _moveIn[room] = picked.id;
      } else {
        _moveOut[room] = picked.id;
      }
    });
  }

  Future<void> _export(
    BuildContext context,
    Repository repository,
    Property property,
    List<String> rooms,
  ) async {
    setState(() => _busy = true);
    try {
      final pairs = <PdfComparePair>[];
      for (final room in rooms) {
        final inPhoto = _pick(
          repository.photosOf(
            property.id,
            phase: PhotoPhase.moveIn,
            room: room,
          ),
          _moveIn[room],
        );
        final outPhoto = _pick(
          repository.photosOf(
            property.id,
            phase: PhotoPhase.moveOut,
            room: room,
          ),
          _moveOut[room],
        );
        if (inPhoto == null && outPhoto == null) continue;
        pairs.add(
          PdfComparePair(
            room: room,
            issue:
                inPhoto?.issueType.label ?? outPhoto?.issueType.label ?? '房屋现状',
            moveInImage: inPhoto == null
                ? null
                : await repository.readMedia(inPhoto.thumbRef),
            moveInCaption: inPhoto == null
                ? '未拍摄'
                : '${fmtDate(inPhoto.timestamp)} · '
                      '${inPhoto.description.isEmpty ? inPhoto.issueType.label : inPhoto.description}',
            moveOutImage: outPhoto == null
                ? null
                : await repository.readMedia(outPhoto.thumbRef),
            moveOutCaption: outPhoto == null
                ? '未拍摄'
                : '${fmtDate(outPhoto.timestamp)} · '
                      '${outPhoto.description.isEmpty ? outPhoto.issueType.label : outPhoto.description}',
            note: _noteFor(room).text.trim(),
          ),
        );
      }
      final bytes = await PdfService.buildCompareReport(
        property: property,
        pairs: pairs,
        conclusion: _conclusion.text.trim(),
      );
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: '${property.name}_退租对比报告.pdf',
      );
    } catch (error) {
      if (context.mounted) zToast(context, '生成失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Side extends StatelessWidget {
  const _Side({
    required this.label,
    required this.dotColor,
    required this.photo,
    required this.onPick,
  });

  final String label;
  final Color dotColor;
  final EvidencePhoto? photo;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ZDot(color: dotColor, size: 6),
              const SizedBox(width: 4),
              Text(label, style: ZText.small.copyWith(fontSize: 11.5)),
              const Spacer(),
              InkWell(
                onTap: onPick,
                child: Text(
                  '换一张',
                  style: ZText.small.copyWith(fontSize: 11, color: Z.brand),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            photo == null ? '未拍摄' : fmtDate(photo!.timestamp),
            style: ZText.mono.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 110,
            child: photo == null
                ? Container(
                    decoration: BoxDecoration(
                      color: Z.line3,
                      borderRadius: BorderRadius.circular(Z.rSm),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      size: 18,
                      color: Z.ink4,
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(Z.rSm),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ZPhoto(ref: photo!.thumbRef, radius: 0),
                        CustomPaint(
                          painter: AnnotationPainter(
                            shapes: photo!.annotations,
                          ),
                        ),
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: ZWatermarkBar(
                            compact: true,
                            lines: [
                              '${photo!.issueType.emoji} ${photo!.issueType.label}',
                              photo!.description.isEmpty
                                  ? photo!.issueType.examples
                                  : photo!.description,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            photo == null
                ? '—'
                : (photo!.description.isEmpty
                      ? photo!.issueType.examples
                      : photo!.description),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ZText.small.copyWith(fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }
}
