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
                ? const _DepositView()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      for (final block in article!.blocks)
                        _BlockCard(block: block),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          legalDisclaimer,
                          style: ZText.small.copyWith(
                            fontSize: 11,
                            height: 1.6,
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
}

class _DepositView extends StatelessWidget {
  const _DepositView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
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
                  children: [
                    TextSpan(
                      text: lawQuoteText.substring(0, 12),
                      style: ZText.body.copyWith(fontSize: 13, height: 1.7),
                    ),
                    TextSpan(
                      text: lawQuoteText.substring(12),
                      style: ZText.body.copyWith(
                        fontSize: 13,
                        height: 1.7,
                        fontWeight: FontWeight.w600,
                        color: Z.brand,
                      ),
                    ),
                  ],
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
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == 0
                            ? Z.brand
                            : (i == disputeSteps.length - 1
                                  ? const Color(0x1AE04145)
                                  : Z.brandTint),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${disputeSteps[i].index}',
                        style: TextStyle(
                          fontFamily: Z.font,
                          fontFamilyFallback: Z.fallback,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: i == 0
                              ? Colors.white
                              : (i == disputeSteps.length - 1
                                    ? Z.dangerDeep
                                    : Z.brand),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        disputeSteps[i].title,
                        style: ZText.label.copyWith(fontSize: 13),
                      ),
                    ),
                    if (disputeSteps[i].tag != null)
                      ZTag(
                        label: disputeSteps[i].tag!,
                        tone: i == disputeSteps.length - 1
                            ? ZTone.danger
                            : ZTone.brand,
                      )
                    else if (disputeSteps[i].note != null)
                      Text(
                        disputeSteps[i].note!,
                        style: ZText.small.copyWith(fontSize: 11),
                      ),
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
        Text(
          legalDisclaimer,
          style: ZText.small.copyWith(fontSize: 11, height: 1.6),
        ),
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

  @override
  Widget build(BuildContext context) {
    return ZCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (block.heading != null)
            Text(
              block.heading!,
              style: ZText.label.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (block.text != null) ...[
            const SizedBox(height: 8),
            Text(
              block.text!,
              style: ZText.body.copyWith(fontSize: 13, height: 1.75),
            ),
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
                      child: Text(
                        bullet,
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
