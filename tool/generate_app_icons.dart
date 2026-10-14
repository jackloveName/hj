// 生成「租盾」应用图标与各平台所需尺寸。
//
// 为什么用代码画：图标是几何图形（盾牌 + 房子），代码画可复现、任意尺寸都清晰，
// 也方便日后改色。图形按 4 倍超采样再缩小，边缘自带抗锯齿。
//
// 运行：dart run tool/generate_app_icons.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

// 品牌渐变（与 lib/theme/tokens.dart 的 Z.logoGradient 一致）
const int _topR = 0x4E, _topG = 0x86, _topB = 0xFF; // #4E86FF
const int _botR = 0x17, _botG = 0x40, _botB = 0xB8; // #1740B8
const int _houseR = 0x11, _houseG = 0x32, _houseB = 0x7F; // #11327F

void main() {
  // Android：传统图标（5 档）+ 自适应图标前景
  const androidSizes = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  androidSizes.forEach((density, size) {
    _write('android/app/src/main/res/mipmap-$density/ic_launcher.png',
        _icon(size));
    // 自适应图标：前景只画盾牌，四周留白交给背景层
    _write(
      'android/app/src/main/res/mipmap-$density/ic_launcher_foreground.png',
      _shapeOnly(size, scale: 0.42),
    );
  });

  // iOS：整套 AppIcon（含 1024 上架图；iOS 不接受透明，底色铺满）
  const iosIcons = {
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
  };
  iosIcons.forEach((name, size) {
    _write('ios/Runner/Assets.xcassets/AppIcon.appiconset/$name', _icon(size));
  });

  // Web：PWA 图标（maskable 要留安全边距）+ favicon
  _write('web/icons/Icon-192.png', _icon(192));
  _write('web/icons/Icon-512.png', _icon(512));
  _write('web/icons/Icon-maskable-192.png', _icon(192, scale: 0.5));
  _write('web/icons/Icon-maskable-512.png', _icon(512, scale: 0.5));
  _write('web/favicon.png', _icon(64));

  // 主图与圆角版（给预览 / 设计稿用）
  _write('assets/icon/app_icon_1024.png', _icon(1024));
  _write('assets/icon/app_icon_1024_rounded.png', _icon(1024, radius: 0.22));

  _selfCheck(_icon(1024));
}

/// 完整图标：品牌渐变底 + 白色盾牌 + 盾内房子
img.Image _icon(int size, {double radius = 0, double scale = 0.66}) {
  final background = _gradient(size);
  if (radius > 0) _roundCorners(background, radius);
  final shape = _shapeOnly(size, scale: scale);
  return img.compositeImage(
    background,
    shape,
    blend: img.BlendMode.alpha,
    linearBlend: true,
  );
}

/// 只要图形（透明底）：放 4 倍画再缩回来，边缘就顺了
img.Image _shapeOnly(int size, {required double scale}) {
  final factor = size <= 256 ? 4 : 2;
  final big = _drawShape(size * factor, scale);
  return img.copyResize(
    big,
    width: size,
    height: size,
    interpolation: img.Interpolation.cubic,
  );
}

/// 品牌渐变底
img.Image _gradient(int size) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final t = ((x / size) * 0.35 + (y / size) * 0.65).clamp(0.0, 1.0);
      image.setPixelRgba(
        x,
        y,
        _lerp(_topR, _botR, t).round(),
        _lerp(_topG, _botG, t).round(),
        _lerp(_topB, _botB, t).round(),
        255,
      );
    }
  }
  return image;
}

/// 透明底上画白色盾牌 + 深蓝房子 + 白门
img.Image _drawShape(int size, double scale) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));

  final box = size * scale;
  final left = (size - box) / 2;
  final top = (size - box) / 2;
  img.Point p(double x, double y) =>
      img.Point(left + box * x, top + box * y);

  // 盾牌轮廓：上部两角圆滑，两侧直下，底部收成尖角
  final shield = <img.Point>[];
  for (var i = 0; i <= 12; i++) {
    final t = i / 12;
    shield.add(
      p(0.5 - 0.44 * math.sin(t * math.pi / 2), 0.06 + 0.10 * math.cos(t * math.pi / 2)),
    );
  }
  for (var i = 0; i <= 12; i++) {
    final t = i / 12;
    shield.add(
      p(0.5 + 0.44 * math.sin(t * math.pi / 2), 0.16 - 0.10 * math.cos(t * math.pi / 2)),
    );
  }
  shield.add(p(0.94, 0.60));
  for (var i = 1; i <= 14; i++) {
    final t = i / 14;
    shield.add(p(0.94 - 0.44 * math.sin(t * math.pi / 2), 0.60 + 0.36 * math.sin(t * math.pi / 2)));
  }
  for (var i = 14; i >= 0; i--) {
    final t = i / 14;
    shield.add(p(0.06 + 0.44 * (1 - math.sin(t * math.pi / 2)), 0.60 + 0.36 * math.sin(t * math.pi / 2)));
  }
  img.fillPolygon(
    image,
    vertices: shield,
    color: img.ColorRgba8(255, 255, 255, 255),
  );

  // 房子：屋顶（三角）+ 房身，深蓝
  img.fillPolygon(
    image,
    vertices: [
      p(0.50, 0.33),
      p(0.25, 0.53),
      p(0.75, 0.53),
    ],
    color: img.ColorRgba8(_houseR, _houseG, _houseB, 255),
  );
  img.fillRect(
    image,
    x1: (left + box * 0.33).round(),
    y1: (top + box * 0.51).round(),
    x2: (left + box * 0.67).round(),
    y2: (top + box * 0.78).round(),
    color: img.ColorRgba8(_houseR, _houseG, _houseB, 255),
  );
  // 门：白色小方块，小尺寸下也能认出是房子
  img.fillRect(
    image,
    x1: (left + box * 0.45).round(),
    y1: (top + box * 0.61).round(),
    x2: (left + box * 0.55).round(),
    y2: (top + box * 0.78).round(),
    color: img.ColorRgba8(255, 255, 255, 255),
  );
  return image;
}

/// 圆角（用于预览版主图；上架图标保持方角由系统裁切）
void _roundCorners(img.Image image, double radius) {
  final size = image.width;
  final r = size * radius;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = x < r ? r - x : (x > size - r ? x - (size - r) : 0);
      final dy = y < r ? r - y : (y > size - r ? y - (size - r) : 0);
      if (dx == 0 || dy == 0) continue;
      if (math.sqrt(dx * dx + dy * dy) > r) {
        image.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
}

double _lerp(num a, num b, double t) => a + (b - a) * t;

void _write(String path, img.Image image) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('写入 $path (${image.width}x${image.height})');
}

/// 自检：盾牌中心是白的、四角是品牌蓝、房子是深蓝
void _selfCheck(img.Image image) {
  final center = image.getPixel(image.width ~/ 2, (image.height * 0.72).round());
  final corner = image.getPixel(6, 6);
  final house = image.getPixel(image.width ~/ 2, (image.height * 0.45).round());
  stdout.writeln(
    '自检：房子 $house，盾牌下缘 $center，左上角 $corner',
  );
  if (house.b < 90 || house.r > 90) {
    throw StateError('盾牌里的房子应该是深蓝（拿到 $house）');
  }
  if (center.r < 200 || center.g < 200 || center.b < 200) {
    throw StateError('盾牌主体应该是白色（拿到 $center）');
  }
  if (corner.b < 150 || corner.r > 120) {
    throw StateError('四角应该是品牌蓝（拿到 $corner）');
  }
}
