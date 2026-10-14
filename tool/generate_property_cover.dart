// 生成租住页房源卡片的默认底图（没有封面照片时用）。
//
// 跑法：dart run tool/generate_property_cover.dart
// 产物：assets/images/property_cover.png
//
// 为什么用代码画而不是贴一张照片：项目里图标也是这么生成的
// （tool/generate_app_icons.dart），好处是配色跟着令牌走、随时可重生成、
// 不引入来源不明的图片版权。
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

const int _w = 1200;
const int _h = 600;
const int _horizon = 392; // 地平线：上面是夜色天空，下面是地面

// 与 theme/tokens.dart 的品牌色对齐
const _skyTop = [0x0B, 0x18, 0x36];
const _skyMid = [0x1E, 0x3E, 0x74];
const _skyWarm = [0x4C, 0x5A, 0x8C];
const _glow = [0xF0, 0xA8, 0x1E];
const _building = [0x0A, 0x1A, 0x33];
const _buildingLit = [0x14, 0x2E, 0x54];
const _window = [0xFF, 0xD4, 0x79];
const _ground = [0x07, 0x10, 0x22];

void main() {
  final image = img.Image(width: _w, height: _h);
  final rnd = Random(20261014); // 固定种子：每次生成结果一致

  _paintSky(image);
  _paintStars(image, rnd);
  _paintGlow(image);
  _paintSkyline(image, rnd);
  _paintHouse(image);
  _paintGround(image);

  final file = File('assets/images/property_cover.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image, level: 6));
  stdout.writeln('已生成 ${file.path}（$_w x $_h，${file.lengthSync() ~/ 1024}KB）');
}

List<int> _mix(List<int> a, List<int> b, double t) => [
  (a[0] + (b[0] - a[0]) * t).round(),
  (a[1] + (b[1] - a[1]) * t).round(),
  (a[2] + (b[2] - a[2]) * t).round(),
];

void _px(img.Image image, int x, int y, List<int> color) {
  if (x < 0 || y < 0 || x >= _w || y >= _h) return;
  image.setPixelRgb(x, y, color[0], color[1], color[2]);
}

void _rect(img.Image image, int x, int y, int w, int h, List<int> color) {
  for (var i = 0; i < w; i++) {
    for (var j = 0; j < h; j++) {
      _px(image, x + i, y + j, color);
    }
  }
}

/// 垂直渐变：夜空（深蓝）过渡到地平线附近（偏暖的暮色）
void _paintSky(img.Image image) {
  for (var y = 0; y < _horizon; y++) {
    final t = y / _horizon;
    final color = t < 0.62
        ? _mix(_skyTop, _skyMid, t / 0.62)
        : _mix(_skyMid, _skyWarm, (t - 0.62) / 0.38);
    for (var x = 0; x < _w; x++) {
      _px(image, x, y, color);
    }
  }
}

void _paintStars(img.Image image, Random rnd) {
  for (var i = 0; i < 90; i++) {
    final x = rnd.nextInt(_w);
    final y = rnd.nextInt((_horizon * 0.55).round());
    final base = _mix(_skyTop, _skyMid, y / _horizon);
    _px(image, x, y, _mix(base, [255, 255, 255], 0.35 + rnd.nextDouble() * 0.3));
  }
}

/// 地平线右侧一团暖光：像落日 / 城市灯火
void _paintGlow(img.Image image) {
  const cx = 980;
  const cy = _horizon - 26;
  const radius = 210;
  for (var y = cy - radius; y < cy + radius; y++) {
    for (var x = cx - radius; x < cx + radius; x++) {
      if (x < 0 || y < 0 || x >= _w || y >= _horizon) continue;
      final d = sqrt(pow(x - cx, 2) + pow(y - cy, 2)) / radius;
      if (d >= 1) continue;
      final strength = (1 - d) * (1 - d) * 0.55;
      final base =
          _mix(_skyMid, _skyWarm, ((y / _horizon) - 0.62).clamp(0, 1) / 0.38);
      _px(image, x, y, _mix(base, _glow, strength));
    }
  }
}

/// 远景楼群：高矮不一的深色方块 + 零星亮着的窗
void _paintSkyline(img.Image image, Random rnd) {
  var x = -20;
  while (x < _w) {
    final w = 54 + rnd.nextInt(70);
    final h = 90 + rnd.nextInt(180);
    final top = _horizon - h;
    final tone = _mix(_building, _buildingLit, rnd.nextDouble() * 0.6);
    _rect(image, x, top, w, h, tone);

    // 窗户：竖向排列的小灯，约四成亮着
    for (var wy = top + 14; wy < _horizon - 12; wy += 26) {
      for (var wx = x + 10; wx < x + w - 10; wx += 20) {
        if (rnd.nextDouble() < 0.42) {
          _rect(image, wx, wy, 8, 12, _mix(_window, tone, 0.1));
        }
      }
    }
    x += w + 10 + rnd.nextInt(18);
  }
}

/// 前景一栋带坡屋顶的家：灯光亮着，呼应「租住 / 家」
void _paintHouse(img.Image image) {
  const left = 610;
  const bodyW = 330;
  const bodyTop = 236;
  const bodyH = _horizon - bodyTop;
  const roofH = 84;
  const body = [0x16, 0x30, 0x5C];

  _rect(image, left, bodyTop, bodyW, bodyH, body);

  // 坡屋顶（逐行收窄的三角形）
  for (var i = 0; i < roofH; i++) {
    final y = bodyTop - roofH + i;
    final inset = ((1 - i / roofH) * (bodyW / 2 + 26)).round();
    _rect(image, left - 26 + inset, y, bodyW + 52 - inset * 2, 1, body);
  }

  // 亮着的窗（暖黄）与门
  _rect(image, left + 52, bodyTop + 62, 74, 66, _window);
  _rect(image, left + 52, bodyTop + 62 + 32, 74, 2, body);
  _rect(image, left + 52 + 36, bodyTop + 62, 2, 66, body);
  _rect(image, left + bodyW - 128, bodyTop + 62, 74, 66, _window);
  _rect(image, left + bodyW - 128, bodyTop + 62 + 32, 74, 2, body);
  _rect(image, left + bodyW - 128 + 36, bodyTop + 62, 2, 66, body);
  _rect(image, left + bodyW ~/ 2 - 34, bodyTop + 176, 68, bodyH - 176, _window);
}

void _paintGround(img.Image image) {
  for (var y = _horizon; y < _h; y++) {
    final t = (y - _horizon) / (_h - _horizon);
    for (var x = 0; x < _w; x++) {
      _px(image, x, y, _mix(_ground, _building, t * 0.5));
    }
  }
}
