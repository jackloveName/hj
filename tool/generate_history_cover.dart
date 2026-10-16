// 生成「历史租住」卡片的固定封面：黄昏天际线 + 落日 + 亮着的窗。
// 浅色 + 暗色两版。
//
// 跑法：dart run tool/generate_history_cover.dart
// 产物：assets/images/history_cover.png、assets/images/history_cover_dark.png
//       （480×480 方图，列表里按 72 显示）
//
// 为什么用代码画：和 property_cover / photo_missing 一个路子 ——
// 配色跟着令牌走、随时可重生成、不引入来源不明的图片版权。
// 用暖色（黄昏）和「在租」那张夜色封面区分开：那是现在，这是过去。
// 暗色那版整体压暗、窗光调低，压在深色卡片上不发亮。
import 'dart:io';

import 'package:image/image.dart' as img;

const int _size = 480;
const int _horizon = 366; // 地平线：上面天空，下面地面

/// 一版配色
class _Palette {
  const _Palette({
    required this.name,
    required this.skyTop,
    required this.skyMid,
    required this.skyWarm,
    required this.ground,
    required this.city,
    required this.window,
    required this.sun,
  });

  final String name;
  final List<int> skyTop;
  final List<int> skyMid;
  final List<int> skyWarm;
  final List<int> ground;
  final List<int> city;
  final List<int> window;
  final List<int> sun;
}

const _palettes = <_Palette>[
  _Palette(
    name: 'history_cover',
    skyTop: [0x14, 0x1F, 0x3A],
    skyMid: [0x3B, 0x36, 0x63],
    skyWarm: [0xC9, 0x7A, 0x2B],
    ground: [0x0E, 0x17, 0x2B],
    city: [0x0A, 0x13, 0x28],
    window: [0xFF, 0xD1, 0x74],
    sun: [0xF5, 0xB1, 0x5A],
  ),
  // 暗色：天空更沉、落日压成暗橙、窗光是暖白而不是亮黄
  _Palette(
    name: 'history_cover_dark',
    skyTop: [0x0C, 0x13, 0x24],
    skyMid: [0x24, 0x21, 0x40],
    skyWarm: [0x6E, 0x44, 0x1C],
    ground: [0x08, 0x0D, 0x18],
    city: [0x06, 0x0B, 0x16],
    window: [0xD8, 0xB4, 0x74],
    sun: [0x8A, 0x63, 0x2F],
  ),
];

void main() {
  for (final palette in _palettes) {
    final image = img.Image(width: _size, height: _size);
    _paintSky(image, palette);
    _paintSun(image, palette);
    _paintSkyline(image, palette);
    _paintGround(image, palette);
    final file = File('assets/images/${palette.name}.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(image));
    stdout.writeln('已生成 ${file.path}');
  }
}

void _paintSky(img.Image image, _Palette palette) {
  for (var y = 0; y < _horizon; y++) {
    final t = y / (_horizon - 1);
    final color = t < 0.55
        ? _lerp(palette.skyTop, palette.skyMid, t / 0.55)
        : _lerp(palette.skyMid, palette.skyWarm, (t - 0.55) / 0.45);
    for (var x = 0; x < _size; x++) {
      image.setPixelRgb(x, y, color[0], color[1], color[2]);
    }
  }
}

void _paintSun(img.Image image, _Palette palette) {
  _fillCircle(image, 176, _horizon - 16, 44, palette.sun);
}

/// 天际线：几栋高低错落的楼，窗户点几盏灯
void _paintSkyline(img.Image image, _Palette palette) {
  // 高度相对地平线：这样调整构图时窗口不用跟着一个个改
  const buildings = <(int x, int width, int height)>[
    (12, 58, 132),
    (84, 46, 82),
    (144, 62, 168),
    (220, 44, 96),
    (276, 66, 128),
    (356, 52, 68),
    (420, 48, 112),
  ];
  for (final (x, width, height) in buildings) {
    _fillRect(
      image,
      x,
      _horizon - height,
      x + width - 1,
      _horizon + 24,
      palette.city,
    );
  }

  // 窗户：位置写成「离地平线多高」，固定不变（不用随机，每次生成一致）
  for (final (x, up) in <(int, int)>[
    (24, 106),
    (24, 74),
    (46, 106),
    (92, 58),
    (112, 58),
    (92, 28),
    (158, 144),
    (180, 144),
    (158, 112),
    (232, 72),
    (232, 40),
    (288, 104),
    (310, 104),
    (288, 72),
    (332, 104),
    (366, 44),
    (388, 44),
    (366, 14),
    (432, 88),
    (432, 56),
  ]) {
    final top = _horizon - up;
    _fillRect(image, x, top, x + 9, top + 12, palette.window);
  }
}

void _paintGround(img.Image image, _Palette palette) {
  _fillRect(image, 0, _horizon, _size - 1, _size - 1, palette.ground);
  // 城市在路面上的倒影：一条更深的压暗带
  for (var y = _horizon; y < _horizon + 26; y++) {
    final t = (y - _horizon) / 26;
    final color = _lerp(palette.city, palette.ground, t);
    for (var x = 0; x < _size; x++) {
      image.setPixelRgb(x, y, color[0], color[1], color[2]);
    }
  }
}

void _fillRect(
  img.Image image,
  int left,
  int top,
  int right,
  int bottom,
  List<int> color,
) {
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
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

void _set(img.Image image, int x, int y, List<int> color) {
  if (x < 0 || y < 0 || x >= _size || y >= _size) return;
  image.setPixelRgb(x, y, color[0], color[1], color[2]);
}

List<int> _lerp(List<int> a, List<int> b, double t) => [
  (a[0] + (b[0] - a[0]) * t).round(),
  (a[1] + (b[1] - a[1]) * t).round(),
  (a[2] + (b[2] - a[2]) * t).round(),
];
