import 'package:flutter/material.dart';

import '../../content/legal.dart';
import '../../theme/tokens.dart';
import '../kit.dart';

/// SCREEN 09 · 租房法规指南
class LegalGuidePage extends StatefulWidget {
  const LegalGuidePage({super.key});

  @override
  State<LegalGuidePage> createState() => _LegalGuidePageState();
}

class _LegalGuidePageState extends State<LegalGuidePage> {
  static const List<(String, String?)> _tabs = [
    ('押金', 'deposit'),
    ('房东义务', 'landlord'),
    ('我的权利', 'tenant'),
    ('纠纷流程', 'process'),
    ('文书', 'docs'),
  ];

  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final articleId = _tabs[_tab].$2;
    final article = articleId == null
        ? null
        : legalArticles.firstWhere((item) => item.id == articleId);

    return ZScreen(
      child: Column(
        children: [
          const ZAppBar(title: '维权指南', leading: ZBackButton()),
          // tab 与头部之间留出呼吸感，别贴着标题
          const SizedBox(height: 10),
          ZChips<int>(
            options: List<int>.generate(_tabs.length, (index) => index),
            value: _tab,
            emphasize: true,
            labelOf: (index) => _tabs[index].$1,
            onChanged: (value) => setState(() => _tab = value),
          ),
          Expanded(
            child: _tab == 0
                ? _DepositView(summary: article?.summary ?? '')
                : _ArticleList(article: article!),
          ),
        ],
      ),
    );
  }
}

/// 非押金 tab 的正文：一句导语 + 若干段落卡 + 免责声明
class _ArticleList extends StatelessWidget {
  const _ArticleList({required this.article});

  final LegalArticle article;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
    children: [
      _Lead(text: article.summary),
      for (final block in article.blocks) _BlockCard(block: block),
      const _Disclaimer(),
    ],
  );
}

class _DepositView extends StatelessWidget {
  const _DepositView({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        _Lead(text: summary),
        ZCard(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0x122F6BFF), Z.card],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lawQuoteTitle,
                style: ZText.small.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Z.brand,
                ),
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  // 按句子分段：第一句铺前提，后面的才是结论。
                  // 原来这里用 substring(0, 12) 硬切，加粗正好落在半句话中间。
                  children: _quoteSpans(lawQuoteText),
                ),
              ),
            ],
          ),
        ),
        const ZSectionTitle(
          title: '房东不可扣除押金',
          icon: Icons.check_circle_outline_rounded,
          iconColor: Z.ok,
          titleColor: Z.okDeep,
        ),
        const _LawList(items: cannotDeduct, good: true),
        const ZSectionTitle(
          title: '房东可依法扣除',
          icon: Icons.cancel_outlined,
          iconColor: Z.danger,
          titleColor: Z.dangerDeep,
        ),
        const _LawList(items: canDeduct, good: false),
        const ZSectionTitle(title: '纠纷处理 5 步', icon: Icons.balance_outlined),
        ZCard(
          child: Column(
            children: [
              for (var i = 0; i < disputeSteps.length; i++) ...[
                Row(
                  children: [
                    _StepBadge(
                      index: disputeSteps[i].index,
                      total: disputeSteps.length,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        disputeSteps[i].title,
                        style: ZText.label.copyWith(fontSize: 13),
                      ),
                    ),
                    ?_stepChip(i + 1),
                  ],
                ),
                if (i != disputeSteps.length - 1)
                  Container(
                    margin: const EdgeInsets.only(left: 9.5),
                    width: 1.5,
                    height: 12,
                    alignment: Alignment.centerLeft,
                    color: Z.line,
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _Disclaimer(),
      ],
    );
  }
}

class _LawList extends StatelessWidget {
  const _LawList({required this.items, required this.good});

  final List<LawItem> items;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good ? Z.ok : Z.danger;
    return ZCard(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            ZListRow(
              leading: Container(
                width: 19,
                height: 19,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  good ? Icons.check_rounded : Icons.close_rounded,
                  size: 12,
                  color: color,
                ),
              ),
              title: items[i].title,
              subtitle: items[i].sub,
              divider: i != items.length - 1,
            ),
        ],
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.block});

  final LegalBlock block;

  /// 「第 1 步 · 与房东协商」这种小标题：序号拆出来给圆形徽标，标题只留后半截
  static final RegExp _step = RegExp(r'^第\s*(\d+)\s*步\s*·\s*(.+)$');

  @override
  Widget build(BuildContext context) {
    final step = block.heading == null
        ? null
        : _step.firstMatch(block.heading!);
    final stepIndex = step == null ? 0 : int.parse(step.group(1)!);
    final heading = step == null ? block.heading : step.group(2);

    return ZCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stepIndex > 0) ...[
                  _StepBadge(index: stepIndex),
                  const SizedBox(width: 8),
                ],
                Expanded(child: Text(heading, style: ZText.title4)),
                ?_stepChip(stepIndex),
              ],
            ),
          if (block.text != null) ...[
            const SizedBox(height: 8),
            _ClauseText(text: block.text!),
          ],
          if (block.bullets.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final bullet in block.bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 7),
                      child: ZDot(color: Z.brand, size: 5),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ClauseText(
                        text: bullet,
                        style: ZText.body.copyWith(fontSize: 13, height: 1.7),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 每屏开头的一句导语。
///
/// [LegalArticle.summary] 之前一直没被用到：光看 tab 名（「我的权利」）
/// 看不出这一屏到底回答什么问题。
class _Lead extends StatelessWidget {
  const _Lead({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: ZText.caption.copyWith(height: 1.5)),
  );
}

/// 正文里凡是《民法典》第 XXX 条这类引用都染成品牌色。
///
/// 这一页的价值就在「哪一条」，整段都是同一种灰字等于让用户自己去数。
class _ClauseText extends StatelessWidget {
  const _ClauseText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  static final RegExp _clause = RegExp('《[^》]{1,24}》');

  @override
  Widget build(BuildContext context) {
    final base = style ?? ZText.body.copyWith(fontSize: 13, height: 1.75);
    final matches = _clause.allMatches(text).toList();
    if (matches.isEmpty) return Text(text, style: base);

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(text: text.substring(cursor, match.start), style: base),
        );
      }
      spans.add(
        TextSpan(
          text: match[0],
          style: base.copyWith(color: Z.brand, fontWeight: FontWeight.w600),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: base));
    }
    return Text.rich(TextSpan(children: spans));
  }
}

/// 步骤序号圆标：押金屏的 5 步清单和纠纷流程的步骤卡共用一套画法
class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.index, this.total = 5});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final last = index == total;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: index == 1
            ? Z.brand
            : (last ? const Color(0x1AE04145) : Z.brandTint),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$index',
        style: TextStyle(
          fontFamily: Z.font,
          fontFamilyFallback: Z.fallback,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: index == 1 ? Colors.white : (last ? Z.dangerDeep : Z.brand),
        ),
      ),
    );
  }
}

/// 步骤右侧的标注（免费 / 7×24h / 小额诉讼…）：数据在纠纷流程那份里，
/// 押金屏和纠纷流程屏都从同一处取，免得两边写不一样
Widget? _stepChip(int index) {
  if (index < 1 || index > disputeSteps.length) return null;
  final step = disputeSteps[index - 1];
  final last = index == disputeSteps.length;
  if (step.tag != null) {
    return ZTag(label: step.tag!, tone: last ? ZTone.danger : ZTone.brand);
  }
  if (step.note != null) {
    return Text(step.note!, style: ZText.small.copyWith(fontSize: 11));
  }
  return null;
}

/// 页脚免责声明
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      legalDisclaimer,
      style: ZText.small.copyWith(fontSize: 11, height: 1.6),
    ),
  );
}

/// 法条按句拆 span：第一句讲前提，后面的才是结论
List<TextSpan> _quoteSpans(String quote) {
  final body = ZText.body.copyWith(fontSize: 13, height: 1.7);
  final strong = body.copyWith(
    fontWeight: FontWeight.w600,
    color: Z.brand,
  );
  final sentences = quote
      .split('。')
      .where((sentence) => sentence.isNotEmpty)
      .toList();
  return [
    for (var i = 0; i < sentences.length; i++)
      TextSpan(text: '${sentences[i]}。', style: i == 0 ? body : strong),
  ];
}
