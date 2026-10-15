import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../services/export_service.dart';
import '../../services/pdf_service.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../compare/compare_page.dart';
import '../kit.dart';

/// 页面 18 · 报告预览 / 导出
class EvidenceExportPage extends StatefulWidget {
  const EvidenceExportPage({
    super.key,
    required this.propertyId,
    required this.phase,
  });

  final String propertyId;
  final PhotoPhase phase;

  @override
  State<EvidenceExportPage> createState() => _EvidenceExportPageState();
}

class _EvidenceExportPageState extends State<EvidenceExportPage> {
  bool _busy = false;
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final property = repository.propertyById(widget.propertyId);
    if (property == null) return const ZScreen(child: SizedBox.shrink());
    final photos = repository.photosOf(property.id, phase: widget.phase);

    return ZScreen(
      child: Column(
        children: [
          const ZAppBar(title: '导出取证材料', leading: ZBackButton()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                ZCard(
                  child: Column(
                    children: [
                      ZKv(label: '房源', value: property.name),
                      ZKv(label: '阶段', value: widget.phase.label),
                      ZKv(label: '照片', value: '${photos.length} 张'),
                      const ZKv(
                        label: '报告说明行',
                        value: '不含水印',
                        valueColor: Z.okDeep,
                        divider: false,
                      ),
                    ],
                  ),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                if (_status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _status,
                      style: ZText.caption.copyWith(fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 16),
                _ExportTile(
                  icon: Icons.picture_as_pdf_outlined,
                  title: '取证清单 PDF',
                  subtitle: '按房间罗列照片、时间与问题说明',
                  onTap: _busy ? null : _exportChecklist,
                ),
                _ExportTile(
                  icon: Icons.folder_zip_outlined,
                  title: '照片包 ZIP',
                  subtitle: '导出全部原始照片 + 取证清单文本',
                  onTap: _busy ? null : _exportZip,
                ),
                _ExportTile(
                  icon: Icons.compare_arrows_rounded,
                  title: '退租对比报告',
                  subtitle: '入住 vs 退租左右对照，维权核心材料',
                  onTap: () =>
                      zPush(context, ComparePage(propertyId: property.id)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportChecklist() async {
    final repository = context.read<Repository>();
    final property = repository.propertyById(widget.propertyId)!;
    final photos = repository.photosOf(property.id, phase: widget.phase);
    if (photos.isEmpty) {
      zToast(context, '当前阶段还没有取证照片');
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在生成取证清单…';
    });
    try {
      final sections = <PdfSection>[];
      for (final room in property.allRooms) {
        final roomPhotos = photos.where((p) => p.room == room).toList();
        if (roomPhotos.isEmpty) continue;
        final items = <PdfPhotoItem>[];
        for (final photo in roomPhotos) {
          items.add(
            PdfPhotoItem(
              image: await repository.readMedia(photo.thumbRef),
              title: photo.issueType.label,
              subtitle: photo.description.isEmpty ? '无补充说明' : photo.description,
              meta: fmtDateTime(photo.timestamp),
            ),
          );
        }
        sections.add(PdfSection(room: room, items: items));
      }
      final bytes = await PdfService.buildChecklist(
        property: property,
        sections: sections,
      );
      if (!mounted) return;
      setState(() => _status = '已生成，正在打开预览…');
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: '${property.name}_取证清单.pdf',
      );
      if (mounted) setState(() => _status = '取证清单已生成');
    } catch (error) {
      if (mounted) {
        setState(() => _status = '生成失败：$error');
        zToast(context, '生成失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportZip() async {
    final repository = context.read<Repository>();
    final property = repository.propertyById(widget.propertyId)!;
    setState(() {
      _busy = true;
      _status = '正在打包照片…';
    });
    try {
      final bundle = await ExportService(repository).buildPhotoZip(property);
      final ref = await repository.saveMedia(
        bundle.bytes,
        folder: 'exports',
        name: bundle.fileName,
      );
      if (!mounted) return;
      setState(() => _status = '已导出：$ref');
      zToast(context, '照片包已导出');
    } catch (error) {
      if (mounted) setState(() => _status = '打包失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ExportTile extends StatelessWidget {
  const _ExportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Z.brandTint,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: Z.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: ZText.label.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: ZText.small.copyWith(fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 17, color: Z.ink4),
        ],
      ),
    );
  }
}
