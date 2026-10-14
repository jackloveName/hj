import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../theme/tokens.dart';

class MediaCache {
  /// 缓存上限：超过后按「最久未使用」淘汰，避免长时间浏览相册时内存无限增长。
  static const int maxEntries = 60;

  static final Map<String, Future<Uint8List?>> _futures =
      <String, Future<Uint8List?>>{};

  static Future<Uint8List?> load(Repository repository, String ref) {
    if (ref.isEmpty) return Future<Uint8List?>.value(null);
    final cached = _futures.remove(ref);
    if (cached != null) {
      // 命中后移到队尾，保持 LRU 顺序
      _futures[ref] = cached;
      return cached;
    }
    final future = repository.readMedia(ref);
    _futures[ref] = future;
    while (_futures.length > maxEntries) {
      _futures.remove(_futures.keys.first);
    }
    return future;
  }

  static void evict(String ref) => _futures.remove(ref);

  static void clear() => _futures.clear();

  static int get size => _futures.length;
}

/// 照片容器：有图显示图，无图显示与设计稿一致的柔和占位。
class ZPhoto extends StatelessWidget {
  const ZPhoto({
    super.key,
    required this.ref,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.radius = Z.rSm,
    this.watermark,
    this.overlay,
    this.child,
    this.placeholderIcon = Icons.photo_camera_back_outlined,
  });

  final String? ref;
  final double? height;
  final double? width;
  final BoxFit fit;
  final double radius;

  /// 水印文案（第一行加粗，其余为说明）
  final List<String>? watermark;
  final Widget? overlay;
  final Widget? child;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final reference = ref ?? '';
    final content = FutureBuilder<Uint8List?>(
      future: MediaCache.load(context.read<Repository>(), reference),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          // 按显示尺寸解码：列表里 46px 的缩略图没必要把 720×540 的原图整张读进内存
          final ratio = MediaQuery.devicePixelRatioOf(context);
          final boxWidth = width;
          final boxHeight = height;
          return Image.memory(
            bytes,
            fit: fit,
            width: boxWidth,
            height: boxHeight,
            cacheWidth: boxWidth == null ? null : (boxWidth * ratio).round(),
            cacheHeight: boxWidth != null || boxHeight == null
                ? null
                : (boxHeight * ratio).round(),
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _placeholder(),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return _placeholder(showSpinner: true);
        }
        // 有引用却读不到文件：明确提示「文件缺失」，避免被误认为正常照片
        return reference.isEmpty ? _placeholder() : _missingFile();
      },
    );

    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            ?overlay,
            if (watermark != null && watermark!.isNotEmpty)
              Align(
                alignment: Alignment.bottomLeft,
                child: ZWatermarkBar(lines: watermark!),
              ),
            ?child,
          ],
        ),
      ),
    );
  }

  Widget _placeholder({bool showSpinner = false}) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        // 浅色下是暖米色占位；深色下换成中性深色，避免整块亮色
        colors: Z.isDark
            ? [Z.surfaceMuted, Z.line3]
            : const [Color(0xFFC3BBAE), Color(0xFF9A8259)],
      ),
    ),
    child: Center(
      child: showSpinner
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            )
          : Icon(
              placeholderIcon,
              size: 22,
              color: Colors.white.withValues(alpha: 0.55),
            ),
    ),
  );

  /// 照片文件丢失（例如浏览器存储被清理、换机恢复只导入了 JSON）
  Widget _missingFile() => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxHeight.isFinite && constraints.maxHeight < 54;
      return Container(
        color: Z.danger.withValues(alpha: 0.10),
        alignment: Alignment.center,
        child: compact
            ? const Icon(
                Icons.report_gmailerrorred_outlined,
                size: 16,
                color: Z.danger,
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.report_gmailerrorred_outlined,
                    size: 20,
                    color: Z.danger,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '文件缺失',
                    style: ZText.small.copyWith(
                      fontSize: 11,
                      color: Z.danger,
                    ),
                  ),
                ],
              ),
      );
    },
  );
}

/// 照片底部水印条 —— 对应设计稿 .wm
class ZWatermarkBar extends StatelessWidget {
  const ZWatermarkBar({
    super.key,
    required this.lines,
    this.compact = false,
    this.burnStyle = false,
  });

  final List<String> lines;
  final bool compact;

  /// true 时使用与「实际烧录到照片上」一致的黑底 + 品牌色描边样式
  final bool burnStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: burnStyle
          ? const BoxDecoration(
              color: Color(0x99000000),
              border: Border(
                top: BorderSide(color: Color(0xCC2563EB), width: 2.5),
              ),
            )
          : const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0x9E000000)],
              ),
            ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 9,
        vertical: compact ? 5 : 7,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < lines.length; i++)
            Text(
              lines[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: Z.cjk,
                fontFamilyFallback: Z.fallback,
                fontSize: compact ? 9 : (i == 0 ? 11 : 10),
                height: 1.45,
                fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                color: i == 0 ? Colors.white : const Color(0xDFFFFFFF),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> showPhoto(
  BuildContext context,
  String ref, {
  String? title,
  String? caption,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (context, animation, secondary) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: title == null ? null : Text(title),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: ZPhoto(ref: ref, fit: BoxFit.contain, radius: 0),
                ),
              ),
            ),
            if (caption != null && caption.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Z.photoScrim,
                child: Text(
                  caption,
                  style: const TextStyle(
                    fontFamily: Z.cjk,
                    fontFamilyFallback: Z.fallback,
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
      transitionsBuilder: (context, animation, secondary, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}
