import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../content/templates.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../services/pdf_service.dart';
import '../../theme/tokens.dart';
import '../kit.dart';

/// 页面 20 · 维权文书模板
class TemplatesPage extends StatelessWidget {
  const TemplatesPage({super.key, this.property});

  final Property? property;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final active = property ?? repository.currentProperty;

    return ZScreen(
      child: Column(
        children: [
          const ZAppBar(title: '维权文书模板', leading: ZBackButton()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                const ZHintBar(
                  text: '建议先协商、再调解、最后诉讼。每一步都保留书面记录，配合退租对比报告使用效果最好。',
                  tone: ZTone.warn,
                  icon: Icons.tips_and_updates_outlined,
                ),
                const ZSectionTitle(
                  title: '文书模板',
                  icon: Icons.description_outlined,
                ),
                for (final template in docTemplates)
                  ZCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    onTap: () => zPush(
                      context,
                      TemplateFormPage(template: template, property: active),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Z.brandTint,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            template.emoji,
                            style: const TextStyle(fontSize: 17),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                template.name,
                                style: ZText.label.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                template.description,
                                style: ZText.small.copyWith(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 17,
                          color: Z.ink4,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TemplateFormPage extends StatefulWidget {
  const TemplateFormPage({super.key, required this.template, this.property});

  final DocTemplate template;
  final Property? property;

  @override
  State<TemplateFormPage> createState() => _TemplateFormPageState();
}

class _TemplateFormPageState extends State<TemplateFormPage> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final field in widget.template.fields) {
      _controllers[field.key] = TextEditingController(
        text: _prefill(field.key),
      );
    }
  }

  String _prefill(String key) {
    final property = widget.property;
    if (property == null) return '';
    return switch (key) {
      'landlord' => property.landlord.name,
      'address' => property.address,
      'deposit' => _amount(property.contract.deposit),
      'deadline' => '7',
      'landlordInfo' =>
        '${property.landlord.name}'
            '${property.landlord.phone.isEmpty ? '' : '  ${property.landlord.phone}'}',
      _ => '',
    };
  }

  String _amount(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final values = {
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim(),
    };
    final preview = renderTemplate(widget.template.id, values);

    return ZScreen(
      child: Column(
        children: [
          ZAppBar(
            leading: const ZBackButton(),
            title: widget.template.name,
            subtitle: widget.property == null
                ? '未关联房源，部分信息需手动填写'
                : '已自动带入「${widget.property!.name}」',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                for (final field in widget.template.fields)
                  ZField(
                    label: field.label,
                    child: TextField(
                      controller: _controllers[field.key],
                      maxLines: field.key == 'fact' ? 4 : 1,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(hintText: field.hint),
                    ),
                  ),
                const ZSectionTitle(
                  title: '文书预览',
                  icon: Icons.preview_outlined,
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Z.card,
                    borderRadius: BorderRadius.circular(Z.rLg),
                    border: Border.all(color: Z.line),
                  ),
                  child: SelectableText(
                    preview,
                    style: ZText.body.copyWith(fontSize: 13, height: 1.8),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ZButton(
                        label: '复制全文',
                        style: ZButtonStyle.ghost,
                        icon: Icons.copy_all_outlined,
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(text: preview));
                          if (context.mounted) zToast(context, '文书已复制到剪贴板');
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ZButton(
                        label: _busy ? '生成中…' : '导出 PDF',
                        icon: Icons.picture_as_pdf_outlined,
                        onTap: _busy ? null : () => _export(preview),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(String text) async {
    setState(() => _busy = true);
    try {
      final paragraphs = text
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
      final bytes = await PdfService.buildDocument(
        title: widget.template.name,
        paragraphs: paragraphs,
      );
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: '${widget.template.name}.pdf',
      );
    } catch (error) {
      if (mounted) zToast(context, '导出失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
