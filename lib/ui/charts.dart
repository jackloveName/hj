import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../utils/format.dart';

/// 一条趋势线：名称 + 颜色 + 每月数值（null 表示这个月没有记录）
class ChartSeries {
  const ChartSeries({
    required this.name,
    required this.color,
    required this.values,
  });

  final String name;
  final Color color;
  final List<double?> values;

  /// 最后一个有记录的月份的值（图例里展示）
  double? get latest {
    for (var i = values.length - 1; i >= 0; i--) {
      if (values[i] != null) return values[i];
    }
    return null;
  }
}

/// 多指标趋势图：多条彩色折线共用横轴，顶部图例、底部月份。
///
/// 各条线共用一套纵轴刻度（便于横向比较）；没有记录的月份断开，不当作 0。
class MultiTrendChart extends StatelessWidget {
  const MultiTrendChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 118,
  });

  final List<String> labels;
  final List<ChartSeries> series;
  final double height;

  bool get _hasData =>
      series.any((item) => item.values.any((value) => value != null));

  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('还没有抄表记录，记一笔就能看到趋势', style: ZText.small),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [for (final item in series) _legend(item)],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _MultiTrendPainter(series: series),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: ZText.monoSmall.copyWith(
                    fontWeight: i == labels.length - 1
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: i == labels.length - 1 ? Z.ink2 : Z.ink4,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _legend(ChartSeries item) {
    final latest = item.latest;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(item.name, style: ZText.caption),
        const SizedBox(width: 4),
        Text(
          latest == null ? '—' : fmtMoney(latest),
          style: ZText.monoSmall.copyWith(
            color: Z.ink2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MultiTrendPainter extends CustomPainter {
  _MultiTrendPainter({required this.series});

  final List<ChartSeries> series;

  @override
  void paint(Canvas canvas, Size size) {
    const topPadding = 12.0;
    const bottomPadding = 4.0;
    const horizontalInset = 6.0;
    final chartHeight = size.height - topPadding - bottomPadding;
    final chartWidth = size.width - horizontalInset * 2;
    if (chartHeight <= 0 || chartWidth <= 0) return;

    // 三条横向网格线
    final grid = Paint()
      ..color = Z.line2
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = topPadding + chartHeight * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final values = [
      for (final item in series)
        for (final value in item.values) ?value,
    ];
    if (values.isEmpty) return;
    final maxValue = values.reduce(math.max);
    final span = maxValue <= 0 ? 1.0 : maxValue;
    final pointCount = series.first.values.length;

    double xOf(int index) => pointCount <= 1
        ? horizontalInset + chartWidth / 2
        : horizontalInset + chartWidth * index / (pointCount - 1);
    double yOf(double value) =>
        topPadding + chartHeight * (1 - (value / span).clamp(0.0, 1.0));

    final baseline = chartHeight + topPadding;
    // 先把所有渐变都铺好，再画折线，避免后一条的填充盖住前一条的线
    for (final item in series) {
      var points = <Offset>[];
      for (var i = 0; i < item.values.length; i++) {
        final value = item.values[i];
        if (value == null) {
          _fillArea(canvas, points, item.color, baseline, size.width);
          points = <Offset>[];
          continue;
        }
        points.add(Offset(xOf(i), yOf(value)));
      }
      _fillArea(canvas, points, item.color, baseline, size.width);
    }

    for (final item in series) {
      final line = Paint()
        ..color = item.color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      Offset? previous;
      Offset? lastPoint;
      for (var i = 0; i < item.values.length; i++) {
        final value = item.values[i];
        if (value == null) {
          previous = null;
          continue;
        }
        final point = Offset(xOf(i), yOf(value));
        if (previous != null) canvas.drawLine(previous, point, line);
        previous = point;
        lastPoint = point;
      }
      if (lastPoint != null) {
        canvas.drawCircle(
          lastPoint,
          3.4,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          lastPoint,
          3.4,
          Paint()
            ..color = item.color
            ..strokeWidth = 2.2
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MultiTrendPainter oldDelegate) =>
      oldDelegate.series != series;

  /// 折线下方到 X 轴的渐变填充（没有两个点就不画）
  void _fillArea(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double baseline,
    double width,
  ) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, baseline);
    for (final point in points) {
      path.lineTo(point.dx, point.dy);
    }
    path
      ..lineTo(points.last.dx, baseline)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.02),
          ],
          stops: const [0, 1],
        ).createShader(
          Rect.fromLTRB(
            0,
            points.map((point) => point.dy).reduce(math.min),
            width,
            baseline,
          ),
        ),
    );
  }
}
