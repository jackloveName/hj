import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/models.dart';
import '../utils/font_charset.dart';
import '../utils/format.dart';

class PdfPhotoItem {
  const PdfPhotoItem({
    required this.image,
    required this.title,
    required this.subtitle,
    required this.meta,
  });

  final Uint8List? image;
  final String title;
  final String subtitle;
  final String meta;
}

class PdfSection {
  const PdfSection({required this.room, required this.items});

  final String room;
  final List<PdfPhotoItem> items;
}

class PdfComparePair {
  const PdfComparePair({
    required this.room,
    required this.issue,
    required this.moveInImage,
    required this.moveInCaption,
    required this.moveOutImage,
    required this.moveOutCaption,
    required this.note,
  });

  final String room;
  final String issue;
  final Uint8List? moveInImage;
  final String moveInCaption;
  final Uint8List? moveOutImage;
  final String moveOutCaption;
  final String note;
}

/// 报告生成：全部在本地完成，不联网。
/// 所有文字都经过 sanitizeForPdf 兜底，避免生僻字导致生成失败。
class PdfService {
  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<void> ensureFont() async {
    if (_regular != null && _bold != null) return;
    // dart_pdf 只能内嵌 TrueType(glyf) 字体。
    // 这里用**全量**中文字体（GB2312 全覆盖）：报告是证据材料，
    // 房东姓名、地址里的生僻字不能变成 □。
    // 它放在 assets/fonts/pdf/ 下、且界面字体家族不引用它，
    // 所以 Web 上只有「真的导出 PDF」时才会去下载这 2MB。
    _regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/pdf/NotoSansSC-Regular.ttf'),
    );
    _bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/pdf/NotoSansSC-Bold.ttf'),
    );
  }

  static pw.TextStyle _style({
    double size = 10,
    PdfColor? color,
    bool bold = false,
  }) => pw.TextStyle(
    font: bold ? _bold : _regular,
    fontSize: size,
    color: color ?? const PdfColor.fromInt(0xFF33456B),
  );

  static String _t(String value) => sanitizeForPdf(value);

  static pw.Widget _footer() => pw.Container(
    alignment: pw.Alignment.centerRight,
    child: pw.Text(
      _t('本报告由「租盾」生成 · 数据仅保存在用户设备本地'),
      style: _style(size: 8, color: const PdfColor.fromInt(0xFF9AA5BC)),
    ),
  );

  static pw.Widget _infoBox(Property property, String photoLine) {
    final rows = <List<String>>[
      ['房源', property.name],
      ['地址', property.address],
      ['房东', '${property.landlord.name}  ${property.landlord.phone}'],
      [
        '月租 / 押金',
        '${fmtMoney(property.contract.monthlyRent)} / ${fmtMoney(property.contract.deposit)}',
      ],
      [
        '租期',
        '${fmtDate(property.contract.moveInDate)} 至 ${fmtDate(property.contract.contractEnd)}',
      ],
      ['照片', photoLine],
    ];
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFE4E8F0)),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          for (final row in rows)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 72,
                    child: pw.Text(
                      _t(row[0]),
                      style: _style(
                        size: 9,
                        color: const PdfColor.fromInt(0xFF6B7A99),
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(_t(row[1]), style: _style(size: 9.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 取证清单
  // -------------------------------------------------------------------------

  static Future<Uint8List> buildChecklist({
    required Property property,
    required List<PdfSection> sections,
  }) async {
    await ensureFont();
    final total = sections.fold<int>(0, (sum, s) => sum + s.items.length);
    final document = pw.Document(title: _t('${property.name} 取证清单'));

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
        footer: (_) => _footer(),
        build: (context) => [
          pw.Text(
            _t('房屋现状取证清单'),
            style: _style(
              size: 20,
              bold: true,
              color: const PdfColor.fromInt(0xFF0E1F3D),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            _t('生成时间：${fmtDateTime(DateTime.now())}'),
            style: _style(size: 9, color: const PdfColor.fromInt(0xFF6B7A99)),
          ),
          pw.SizedBox(height: 16),
          _infoBox(property, '$total 张'),
          pw.SizedBox(height: 18),
          for (final section in sections) ...[
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFEAF0FF),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    _t(section.room),
                    style: _style(size: 12, bold: true),
                  ),
                  pw.Text(
                    _t('${section.items.length} 张'),
                    style: _style(
                      size: 10,
                      color: const PdfColor.fromInt(0xFF2F6BFF),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final item in section.items)
                  pw.Container(
                    width: 158,
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: const PdfColor.fromInt(0xFFE4E8F0),
                      ),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (item.image != null)
                          pw.ClipRRect(
                            horizontalRadius: 4,
                            verticalRadius: 4,
                            child: pw.Image(
                              pw.MemoryImage(item.image!),
                              height: 106,
                              fit: pw.BoxFit.cover,
                            ),
                          ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          _t(item.title),
                          style: _style(size: 9, bold: true),
                        ),
                        pw.Text(_t(item.subtitle), style: _style(size: 8)),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          _t(item.meta),
                          style: _style(
                            size: 7,
                            color: const PdfColor.fromInt(0xFF9AA5BC),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            pw.SizedBox(height: 16),
          ],
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF7F9FC),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              _t(
                '说明：以上照片均由「租盾」在拍摄时自动添加时间水印，原始照片保存于本机，未经修改。'
                '本清单可作为入住时房屋状况的客观记录，用于退租时对比。',
              ),
              style: _style(size: 9),
            ),
          ),
        ],
      ),
    );
    return document.save();
  }

  // -------------------------------------------------------------------------
  // 退租对比报告
  // -------------------------------------------------------------------------

  static Future<Uint8List> buildCompareReport({
    required Property property,
    required List<PdfComparePair> pairs,
    String conclusion = '',
  }) async {
    await ensureFont();
    final document = pw.Document(title: _t('${property.name} 退租对比报告'));

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
        footer: (_) => _footer(),
        build: (context) => [
          pw.Text(
            _t('退租对比报告'),
            style: _style(
              size: 20,
              bold: true,
              color: const PdfColor.fromInt(0xFF0E1F3D),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            _t('入住取证 ⇄ 退租取证 对照 · 生成时间：${fmtDateTime(DateTime.now())}'),
            style: _style(size: 9, color: const PdfColor.fromInt(0xFF6B7A99)),
          ),
          pw.SizedBox(height: 14),
          _infoBox(property, '${pairs.length} 组对比'),
          pw.SizedBox(height: 18),
          for (var i = 0; i < pairs.length; i++) ...[
            pw.Text(
              _t('${i + 1}. ${pairs[i].room} · ${pairs[i].issue}'),
              style: _style(size: 13, bold: true),
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _compareCell(
                    '入住时',
                    pairs[i].moveInImage,
                    pairs[i].moveInCaption,
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _compareCell(
                    '退租时',
                    pairs[i].moveOutImage,
                    pairs[i].moveOutCaption,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFFFFBEB),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                _t('说明：${pairs[i].note.isEmpty ? '待补充说明' : pairs[i].note}'),
                style: _style(size: 9),
              ),
            ),
            pw.SizedBox(height: 16),
          ],
          if (conclusion.isNotEmpty) ...[
            pw.Text(_t('综合说明'), style: _style(size: 13, bold: true)),
            pw.SizedBox(height: 6),
            pw.Text(_t(conclusion), style: _style(size: 10)),
            pw.SizedBox(height: 12),
          ],
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF7F9FC),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              _t(
                '依据《民法典》第七百一十条、第七百一十四条：承租人按照约定的方法或者根据租赁物的性质'
                '使用租赁物，致使租赁物受到损耗的，不承担赔偿责任。自然磨损、入住时已有的瑕疵'
                '不应从押金中扣除。',
              ),
              style: _style(size: 9),
            ),
          ),
        ],
      ),
    );
    return document.save();
  }

  static pw.Widget _compareCell(
    String label,
    Uint8List? image,
    String caption,
  ) => pw.Container(
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: const PdfColor.fromInt(0xFFE4E8F0)),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(_t(label), style: _style(size: 10, bold: true)),
        pw.SizedBox(height: 4),
        if (image != null)
          pw.ClipRRect(
            horizontalRadius: 4,
            verticalRadius: 4,
            child: pw.Image(
              pw.MemoryImage(image),
              height: 148,
              fit: pw.BoxFit.cover,
            ),
          )
        else
          pw.Container(
            height: 148,
            alignment: pw.Alignment.center,
            color: const PdfColor.fromInt(0xFFF1F4F9),
            child: pw.Text(
              _t('暂无照片'),
              style: _style(size: 9, color: const PdfColor.fromInt(0xFF9AA5BC)),
            ),
          ),
        pw.SizedBox(height: 4),
        pw.Text(_t(caption), style: _style(size: 8)),
      ],
    ),
  );

  // -------------------------------------------------------------------------
  // 维权文书
  // -------------------------------------------------------------------------

  static Future<Uint8List> buildDocument({
    required String title,
    required List<String> paragraphs,
  }) async {
    await ensureFont();
    final document = pw.Document(title: _t(title));
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 34),
        footer: (_) => _footer(),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              _t(title),
              style: _style(
                size: 18,
                bold: true,
                color: const PdfColor.fromInt(0xFF0E1F3D),
              ),
            ),
          ),
          pw.SizedBox(height: 22),
          for (final paragraph in paragraphs)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                _t(paragraph),
                style: _style(size: 11),
                textAlign: pw.TextAlign.justify,
              ),
            ),
        ],
      ),
    );
    return document.save();
  }
}
