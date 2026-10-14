import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../media.dart';

/// 在照片上叠加手绘标注（圆圈 / 箭头 / 矩形 / 自由线 / 文字）。
class AnnotationPainter extends CustomPainter {
  AnnotationPainter({required this.shapes});

  final List<AnnotationShape> shapes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final shape in shapes) {
      final paint = Paint()
        ..color = shape.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = (shape.strokeWidth * size.width).clamp(1.6, 12)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final points = shape.points
          .map((p) => Offset(p.dx * size.width, p.dy * size.height))
          .toList();
      if (points.isEmpty) continue;

      switch (shape.type) {
        case 'circle':
          if (points.length >= 2) {
            canvas.drawCircle(
              points.first,
              (points.last - points.first).distance,
              paint,
            );
          }
        case 'rect':
          if (points.length >= 2) {
            canvas.drawRect(Rect.fromPoints(points.first, points.last), paint);
          }
        case 'arrow':
          if (points.length >= 2) {
            final start = points.first;
            final end = points.last;
            canvas.drawLine(start, end, paint);
            final angle = (end - start).direction;
            final head = (size.width * 0.035).clamp(10.0, 28.0);
            canvas.drawLine(
              end,
              end - Offset.fromDirection(angle - 0.5, head),
              paint,
            );
            canvas.drawLine(
              end,
              end - Offset.fromDirection(angle + 0.5, head),
              paint,
            );
          }
        case 'free':
          if (points.length >= 2) {
            final path = Path()..moveTo(points.first.dx, points.first.dy);
            for (final point in points.skip(1)) {
              path.lineTo(point.dx, point.dy);
            }
            canvas.drawPath(path, paint);
          }
        case 'text':
          final painter = TextPainter(
            text: TextSpan(
              text: shape.text,
              style: TextStyle(
                color: shape.color,
                fontFamily: Z.cjk,
                fontFamilyFallback: Z.fallback,
                fontSize: (size.width * 0.035).clamp(11.0, 24.0),
                fontWeight: FontWeight.w700,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: size.width * 0.8);
          painter.paint(canvas, points.first);
        default:
          break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter oldDelegate) =>
      oldDelegate.shapes != shapes;
}

/// 带标注的定尺寸照片画布（宽高比与原图一致，标注坐标为归一化值）
class AnnotatedPhoto extends StatelessWidget {
  const AnnotatedPhoto({
    super.key,
    required this.photo,
    this.extra = const [],
    this.overlay,
    this.child,
  });

  final EvidencePhoto photo;
  final List<AnnotationShape> extra;
  final Widget? overlay;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final ratio = photo.width > 0 && photo.height > 0
        ? photo.width / photo.height
        : 4 / 3;
    return AspectRatio(
      aspectRatio: ratio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PhotoLayer(photo: photo),
          CustomPaint(
            painter: AnnotationPainter(
              shapes: [...photo.annotations, ...extra],
            ),
          ),
          ?overlay,
          ?child,
        ],
      ),
    );
  }
}

/// 单张照片（已烧录水印）
class PhotoLayer extends StatelessWidget {
  const PhotoLayer({super.key, required this.photo});

  final EvidencePhoto photo;

  @override
  Widget build(BuildContext context) =>
      ZPhoto(ref: photo.imageRef, fit: BoxFit.cover, radius: 0);
}
