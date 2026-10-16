import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';
import '../media.dart';
import '../pickers.dart';

class RulesPage extends StatelessWidget {
  const RulesPage({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final rules = repository.rulesOf(propertyId);
    // 编辑房源时填的「特殊条款」也属于房东要求：一并摆出来，
    // 不然用户以为写进合同就自动生效了
    final property = repository.propertyById(propertyId);
    final specialTerms = property?.contract.specialTerms.trim() ?? '';
    final hasAny = rules.isNotEmpty || specialTerms.isNotEmpty;
    // 已退租 / 纠纷中的房子只读：能翻要求，但不能加、不能改
    final editable = property != null && canEditProperty(property);

    return ZScreen(
      child: Column(
        children: [
          ZAppBar(
            leading: const ZBackButton(),
            title: '房东要求',
            actions: [
              if (editable)
                ZIconButton(
                  icon: Icons.add_rounded,
                  color: Z.brand,
                  tooltip: '添加要求',
                  onTap: () => _edit(context, repository, propertyId),
                ),
            ],
          ),
          Expanded(
            child: !hasAny
                ? ZEmpty(
                    icon: Icons.rule_folder_outlined,
                    title: '还没有记录房东要求',
                    message: '把房东的“特殊约定”写下来，退租时才不会被翻旧账。',
                    actionLabel: editable ? '添加要求' : null,
                    onAction: editable
                        ? () => _edit(context, repository, propertyId)
                        : null,
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      if (specialTerms.isNotEmpty) ...[
                        ZCard(
                          color: Z.brandTint,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.description_outlined,
                                    size: ZIcon.s,
                                    color: Z.brand,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '合同里的特殊条款',
                                    style: ZText.labelStrong.copyWith(
                                      color: Z.brand,
                                    ),
                                  ),
                                  const Spacer(),
                                  const ZTag(
                                    label: '来自合同',
                                    tone: ZTone.brand,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                specialTerms,
                                style: ZText.body.copyWith(
                                  fontSize: 13.5,
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '摘自「编辑房源 → 特殊条款」，改了房源信息这里会跟着变',
                                style: ZText.small.copyWith(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      const ZHintBar(
                        // 这是「怎么用」的说明，不是警告：换成中性提示，
                        // 与下面那张列表要表达的意思保持一致
                        text: '点右上角「+」添加要求：7 条常见要求可一键勾选，'
                            '并标注来源（合同 / 口头 / 聊天记录）。',
                        icon: Icons.info_outline_rounded,
                      ),
                      const SizedBox(height: 14),
                      for (final rule in rules)
                        _RuleCard(
                          rule: rule,
                          onTap: editable
                              ? () => _edit(
                                  context,
                                  repository,
                                  propertyId,
                                  rule: rule,
                                )
                              : null,
                        ),
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
    String propertyId, {
    LandlordRule? rule,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RuleSheet(
        propertyId: propertyId,
        repository: repository,
        existing: rule,
      ),
    );
  }
}

/// 一条房东要求。
///
/// 之前每条前面挂了个红叉：红叉是「被否决 / 删除」的意思，
/// 挂在「退租需提前 30 天通知」这类要求前面会让人误会。
/// 现在改成中性的「要求」标记，内容当主角，来源 / 时间 / 证据排在下面。
class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.rule, this.onTap});

  final LandlordRule rule;

  /// 只读时传 null：卡片照旧展示，只是点不动
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 三种来源给三种颜色，之前「合同」和「聊天记录」撞成同一种蓝
    final tone = switch (rule.source) {
      RuleSource.contract => ZTone.brand,
      RuleSource.verbal => ZTone.warn,
      RuleSource.chat => ZTone.violet,
    };

    return ZCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Z.brandTint,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.rule_rounded,
                  size: 15,
                  color: Z.brand,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  rule.content,
                  style: ZText.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.edit_outlined, size: 13, color: Z.ink4),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ZTag(label: rule.source.label, tone: tone),
              const SizedBox(width: 8),
              Text(
                fmtDate(rule.createdAt),
                style: ZText.small.copyWith(fontSize: 11),
              ),
              const Spacer(),
              if (rule.evidenceRefs.isNotEmpty) ...[
                Icon(
                  Icons.photo_library_outlined,
                  size: 12,
                  color: Z.ink4,
                ),
                const SizedBox(width: 4),
                Text(
                  '${rule.evidenceRefs.length} 张证据',
                  style: ZText.small.copyWith(fontSize: 11),
                ),
              ],
            ],
          ),
          if (rule.evidenceRefs.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: rule.evidenceRefs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => InkWell(
                  onTap: () => showPhoto(
                    context,
                    rule.evidenceRefs[i],
                    title: '约定证据',
                  ),
                  child: ZPhoto(
                    ref: rule.evidenceRefs[i],
                    width: 56,
                    height: 56,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RuleSheet extends StatefulWidget {
  const _RuleSheet({
    required this.propertyId,
    required this.repository,
    this.existing,
  });

  final String propertyId;
  final Repository repository;
  final LandlordRule? existing;

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  late final TextEditingController _content = TextEditingController(
    text: widget.existing?.content ?? '',
  );
  late RuleSource _source = widget.existing?.source ?? RuleSource.contract;
  late final List<String> _evidence = List<String>.from(
    widget.existing?.evidenceRefs ?? const [],
  );

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
            Text(
              widget.existing == null ? '添加房东要求' : '编辑房东要求',
              style: ZText.title3.copyWith(fontSize: 17),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in LandlordRule.presets)
                  ActionChip(
                    label: Text(preset),
                    onPressed: () => setState(() => _content.text = preset),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            ZField(
              label: '要求内容',
              child: TextField(
                controller: _content,
                maxLines: 3,
                decoration: const InputDecoration(hintText: '如：退租需提前 30 天通知'),
              ),
            ),
            ZField(
              label: '来源',
              child: ZChips<RuleSource>(
                options: RuleSource.values,
                value: _source,
                emphasize: true,
                padding: EdgeInsets.zero,
                labelOf: (value) => value.label,
                onChanged: (value) => setState(() => _source = value),
              ),
            ),
            ZField(
              label: '证据截图',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final ref in _evidence)
                    Stack(
                      children: [
                        ZPhoto(ref: ref, width: 68, height: 68),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: InkWell(
                            onTap: () => setState(() => _evidence.remove(ref)),
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
                    onTap: _addEvidence,
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
            const SizedBox(height: 10),
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

  Future<void> _addEvidence() async {
    final bytes = await pickImage(context);
    if (bytes == null) return;
    final ref = await widget.repository.saveMedia(
      bytes,
      folder: widget.propertyId,
      name: 'rule_${newId('r')}.jpg',
    );
    if (mounted) setState(() => _evidence.add(ref));
  }

  Future<void> _save() async {
    final content = _content.text.trim();
    if (content.isEmpty) {
      zToast(context, '请填写要求内容');
      return;
    }
    final existing = widget.existing;
    await widget.repository.saveRule(
      existing == null
          ? LandlordRule(
              id: newId('rule'),
              propertyId: widget.propertyId,
              content: content,
              source: _source,
              evidenceRefs: _evidence,
              createdAt: DateTime.now(),
            )
          : existing.copyWith(
              content: content,
              source: _source,
              evidenceRefs: _evidence,
            ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    zToast(context, '已保存');
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    await widget.repository.deleteRule(existing.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
