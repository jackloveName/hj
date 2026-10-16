// 生成「照片文件缺失 / 没有照片」的固定占位图：浅色 + 暗色两版。
//
// 跑法：dart run tool/generate_photo_missing.dart
// 产物：assets/images/photo_missing.png
//       assets/images/photo_missing_dark.png
//
// 用法和 property_cover 一样：配色跟着设计令牌走、随时可重生成、
// 不引入来源不明的图片版权。相框 + 山 + 太阳，一看就知道「这里本该有张图」，
// 但不像红字「文件缺失」那样像个错误。暗色那版对齐 tokens 里的
// card / line3 / ink 系，压在深色卡片上不会发白发亮。
import 'dart:io';

import 'package:image/image.dart' as img;

const int _size = 480;

/// 一版配色
class _Palette {
  const _Palette({
    required this.name,
    required this.bgTop,
    required this.bgBottom,
    required this.frame,
    required this.sun,
    required this.hill,
    required this.hillBack,
  });

  final String name;
  final List<int> bgTop;
  final List<int> bgBottom;
  final List<int> frame;
  final List<int> sun;
  final List<int> hill;
  final List<int> hillBack;
}

// 浅色：暖米灰（现在的样子）；暗色：深蓝灰（_cardDark / _line3Dark 一档）
const _palettes = <_Palette>[
  _Palette(
    name: 'photo_missing',
    bgTop: [0xED, 0xF1, 0xF7],
    bgBottom: [0xD8, 0xDF, 0xEA],
    frame: [0xB6, 0xC1, 0xD2],
    sun: [0xC9, 0xD3, 0xE2],
    hill: [0xA9, 0xB6, 0xC9],
    hillBack: [0xC0, 0xCA, 0xDA],
  ),
  _Palette(
    name: 'photo_missing_dark',
    bgTop: [0x24, 0x2E, 0x3D],
    bgBottom: [0x1A, 0x22, 0x31],
    frame: [0x3D, 0x4D, 0x64],
    sun: [0x33, 0x42, 0x5C],
    hill: [0x2C, 0x3A, 0x4F],
    hillBack: [0x36, 0x45, 0x5C],
  ),
];

void main() {
  for (final palette in _palettes) {
    final image = img.Image(width: _size, height: _size);
    _paintBackground(image, palette);
    _paintPhoto(image, palette);
    final file = File('assets/images/${palette.name}.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(image));
    stdout.writeln('已生成 ${file.path}');
  }
}

void _paintBackground(img.Image image, _Palette palette) {
  for (var y = 0; y < _size; y++) {
    final t = y / (_size - 1);
    final color = _lerp(palette.bgTop, palette.bgBottom, t);
    for (var x = 0; x < _size; x++) {
      image.setPixelRgb(x, y, color[0], color[1], color[2]);
    }
  }
}

/// 「照片」：圆角相框（描边）+ 框里的太阳和山
void _paintPhoto(img.Image image, _Palette palette) {
  const left = 108;
  const top = 128;
  const right = 372;
  const bottom = 352;
  const radius = 26;
  const stroke = 5;

  // 相框描边：画一个圆角矩形的边（外圈填描边色，内圈挖回背景）
  _fillRoundRect(image, left, top, right, bottom, radius, palette.frame);
  _fillRoundRect(
    image,
    left + stroke,
    top + stroke,
    right - stroke,
    bottom - stroke,
    radius - stroke,
    palette.bgBottom,
  );

  // 太阳
  _fillCircle(image, 214, 196, 20, palette.sun);
  // 远山
  _fillTriangle(image, 140, 318, 236, 214, 300, 318, palette.hillBack);
  // 近山（压住相框下沿一点点，做出「照片」的层次）
  _fillTriangle(image, 196, 330, 288, 232, 352, 330, palette.hill);
}

void _fillRoundRect(
  img.Image image,
  int left,
  int top,
  int right,
  int bottom,
  int radius,
  List<int> color,
) {
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      final dx = x < left + radius
          ? left + radius - x
          : (x > right - radius ? x - (right - radius) : 0);
      final dy = y < top + radius
          ? top + radius - y
          : (y > bottom - radius ? y - (bottom - radius) : 0);
      if (dx * dx + dy * dy > radius * radius) continue;
      _set(image, x, y, color);
    }
  }
}

void _fillCircle(img.Image image, int cx, int cy, int r, List<int> color) {
  for (var y = cy - r; y <= cy + r; y++) {
    for (var x = cx - r; x <= cx + r; x++) {
      final dx = x - cx;
      final dy = y - cy;
      if (dx * dx + dy * dy > r * r) continue;
      _set(image, x, y, color);
    }
  }
}

void _fillTriangle(
  img.Image image,
  int x1,
  int y1,
  int x2,
  int y2,
  int x3,
  int y3,
  List<int> color,
) {
  final minX = [x1, x2, x3].reduce((a, b) => a < b ? a : b);
  final maxX = [x1, x2, x3].reduce((a, b) => a > b ? a : b);
  final minY = [y1, y2, y3].reduce((a, b) => a < b ? a : b);
  final maxY = [y1, y2, y3].reduce((a, b) => a > b ? a : b);
  final area = (x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1);
  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final w1 = ((x2 - x) * (y3 - y) - (x3 - x) * (y2 - y)) / area;
      final w2 = ((x3 - x) * (y1 - y) - (x1 - x) * (y3 - y)) / area;
      final w3 = ((x1 - x) * (y2 - y) - (x2 - x) * (y1 - y)) / area;
      if (w1 < 0 || w2 < 0 || w3 < 0) continue;
      _set(image, x, y, color);
    }
  }
}

void _set(img.Image image, int x, int y, List<int> color) {
  if (x < 0 || y < 0 || x >= _size || y >= _size) return;
  image.setPixelRgb(x, y, color[0], color[1], color[2]);
}

List<int> _lerp(List<int> a, List<int> b, double t) => [
  (a[0] + (b[0] - a[0]) * t).round(),
  (a[1] + (b[1] - a[1]) * t).round(),
  (a[2] + (b[2] - a[2]) * t).round(),
];
