import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// 对比度工具：用于校验「文字色 / 底色」在明暗两套令牌下都够清晰。
///
/// 参照 WCAG 2.1：正文要求 ≥ 4.5，大字号（≥18pt 或 ≥14pt 加粗）要求 ≥ 3.0。
double relativeLuminance(Color color) {
  double channel(double value) =>
      value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// 两色对比度，范围 1 ~ 21
double contrastRatio(Color foreground, Color background) {
  final a = relativeLuminance(foreground);
  final b = relativeLuminance(background);
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

/// 是否达到 WCAG AA：正文 4.5，大字 3.0
bool meetsContrast(Color foreground, Color background, {bool large = false}) =>
    contrastRatio(foreground, background) >= (large ? 3.0 : 4.5);
