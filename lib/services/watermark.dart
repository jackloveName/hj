import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import '../theme/tokens.dart';

class ProcessedPhoto {
  const ProcessedPhoto({
    required this.image,
    required this.thumb,
    required this.width,
    required this.height,
  });

  final Uint8List image;
  final Uint8List thumb;
  final int width;
  final int height;
}

/// 水印合成：用 dart:ui 绘制文字（含中文），再压成 JPEG。
/// 拍摄瞬间即烧录，不依赖后处理，符合设计稿「不可编辑」的取证约定。
class WatermarkService {
  static Future<ProcessedPhoto> process({
    required Uint8List source,
    required List<String> lines,
    bool watermark = true,
    int maxDimension = 1600,
    int thumbDimension = 420,
    int quality = 85,
  }) async {
    final main = await _render(
      source: source,
      lines: lines,
      watermark: watermark,
      maxDimension: maxDimension,
      quality: quality,
    );
    final thumb = await _render(
      source: source,
      lines: const <String>[],
      watermark: false,
      maxDimension: thumbDimension,
      quality: 70,
    );
    return ProcessedPhoto(
      image: main.bytes,
      thumb: thumb.bytes,
      width: main.width,
      height: main.height,
    );
  }

  static Future<_Rendered> _render({
    required Uint8List source,
    required List<String> lines,
    required bool watermark,
    required int maxDimension,
    required int quality,
  }) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(source);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final sourceWidth = descriptor.width;
    final sourceHeight = descriptor.height;

    var targetWidth = sourceWidth;
    var targetHeight = sourceHeight;
    final longest = sourceWidth > sourceHeight ? sourceWidth : sourceHeight;
    if (longest > maxDimension && longest > 0) {
      final scale = maxDimension / longest;
      targetWidth = (sourceWidth * scale).round().clamp(1, 100000);
      targetHeight = (sourceHeight * scale).round().clamp(1, 100000);
    }

    final codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final decoded = (await codec.getNextFrame()).image;

    final width = targetWidth.toDouble();
    final height = targetHeight.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, width, height));
    canvas.drawImageRect(
      decoded,
      ui.Rect.fromLTWH(
        0,
        0,
        decoded.width.toDouble(),
        decoded.height.toDouble(),
      ),
      ui.Rect.fromLTWH(0, 0, width, height),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    if (watermark && lines.isNotEmpty) {
      _drawWatermark(canvas, width, height, lines);
    }

    final picture = recorder.endRecording();
    final composed = await picture.toImage(targetWidth, targetHeight);
    final byteData = await composed.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );

    Uint8List jpeg;
    if (byteData == null) {
      jpeg = source;
    } else {
      final rgba = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      final frame = img.Image.fromBytes(
        width: targetWidth,
        height: targetHeight,
        bytes: rgba.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      jpeg = Uint8List.fromList(img.encodeJpg(frame, quality: quality));
    }

    decoded.dispose();
    composed.dispose();
    picture.dispose();
    descriptor.dispose();
    buffer.dispose();
    return _Rendered(jpeg, targetWidth, targetHeight);
  }

  static void _drawWatermark(
    ui.Canvas canvas,
    double width,
    double height,
    List<String> lines,
  ) {
    final fontSize = (width * 0.030).clamp(14.0, 54.0);
    final lineHeight = fontSize * 1.42;
    final padding = (width * 0.022).clamp(10.0, 38.0);
    final barHeight = lineHeight * lines.length + padding * 1.6;

    canvas.drawRect(
      ui.Rect.fromLTWH(0, height - barHeight, width, barHeight),
      ui.Paint()..color = const ui.Color(0x99000000),
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(0, height - barHeight, width, fontSize * 0.12),
      ui.Paint()..color = ui.Color(Z.brand.toARGB32()),
    );

    for (var i = 0; i < lines.length; i++) {
      final isTitle = i == 0;
      final builder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontFamily: Z.cjk,
                fontSize: fontSize,
                maxLines: 1,
                ellipsis: '…',
              ),
            )
            ..pushStyle(
              ui.TextStyle(
                color: const ui.Color(0xFFFFFFFF),
                fontSize: fontSize,
                fontFamily: Z.cjk,
                fontWeight: isTitle ? ui.FontWeight.w700 : ui.FontWeight.normal,
                height: 1.2,
              ),
            )
            ..addText(lines[i]);
      final paragraph = builder.build()
        ..layout(ui.ParagraphConstraints(width: width - padding * 2));
      canvas.drawParagraph(
        paragraph,
        ui.Offset(padding, height - barHeight + padding * 0.8 + lineHeight * i),
      );
    }
  }
}

class _Rendered {
  const _Rendered(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}
