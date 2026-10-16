// 生成应用图标与各平台所需尺寸。
//
// 图标美术稿是设计给的位图（默认 assets/icon/app_icon_source.jpg），这个脚本只做
// 两件事：按各平台要求的尺寸缩放、把 iOS 上架图去掉 alpha 通道。
// （早期版本是用代码画盾牌图形的，换成美术稿之后那段绘制代码就删了。）
//
// 注意：美术稿可能是 JPEG，哪怕扩展名写成 .png —— 一律用 image 包解码，
// 输出统一写成真 PNG。
//
// 运行：dart run tool/generate_app_icons.dart [源图路径]
// 产物：
//   ios/Runner/Assets.xcassets/AppIcon.appiconset/   ← 上架用，15 个尺寸
//   android/app/src/main/res/mipmap-*/               ← 仅本机调试用
//   web/icons/、web/favicon.png                      ← PWA / 网页版
//   assets/icon/app_icon_1024*.png                   ← 预览 / 设计稿素材
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// 美术稿：正方形，越大越好（现在这份是 2048×2048）
const String _defaultSource = 'assets/icon/app_icon_source.jpg';

void main(List<String> args) {
  final sourcePath = args.isEmpty ? _defaultSource : args.first;
  final file = File(sourcePath);
  if (!file.existsSync()) {
    stderr.writeln('找不到图标源图：$sourcePath');
    exit(1);
  }
  final decoded = img.decodeImage(file.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('源图解析失败（不是图片，或者格式不支持）：$sourcePath');
    exit(1);
  }
  if (decoded.width != decoded.height) {
    stderr.writeln('图标源图必须是正方形，当前是 ${decoded.width}x${decoded.height}');
    exit(1);
  }
  stdout.writeln('源图 $sourcePath（${decoded.width}x${decoded.height}）');

  // Android：传统图标（5 档）+ 自适应图标前景（留白交给背景层）
  const androidSizes = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  androidSizes.forEach((density, size) {
    _write(
      'android/app/src/main/res/mipmap-$density/ic_launcher.png',
      _scaled(decoded, size),
    );
    _write(
      'android/app/src/main/res/mipmap-$density/ic_launcher_foreground.png',
      _padded(decoded, size, scale: 0.62),
    );
  });

  // iOS：整套 AppIcon（含 1024 上架图）。
  // 上架硬要求：图标**不能带 alpha 通道**，否则上传报
  // "Invalid Image … can't have an alpha channel"，所以转成 3 通道再写。
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
    _write(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/$name',
      _scaled(decoded, size).convert(numChannels: 3),
    );
  });

  // Web：PWA 图标（maskable 也按满幅给 —— 美术稿四周本来就是蓝底，
  // 被遮罩裁掉边缘之后图形仍然完整）+ favicon
  _write('web/icons/Icon-192.png', _scaled(decoded, 192));
  _write('web/icons/Icon-512.png', _scaled(decoded, 512));
  _write('web/icons/Icon-maskable-192.png', _scaled(decoded, 192));
  _write('web/icons/Icon-maskable-512.png', _scaled(decoded, 512));
  _write('web/favicon.png', _scaled(decoded, 64));

  // 预览 / 设计稿素材（这两张不进安装包：pubspec 没有声明 assets/icon/）
  _write('assets/icon/app_icon_1024.png', _scaled(decoded, 1024));
  _write(
    'assets/icon/app_icon_1024_rounded.png',
    _rounded(_scaled(decoded, 1024), 0.22),
  );

  _selfCheck(decoded, iosIcons);
}

/// 缩放：先逐级折半再收尾，避免 2048 → 20 一步缩出锯齿
img.Image _scaled(img.Image source, int size) {
  var current = source;
  while (current.width >= size * 2) {
    current = img.copyResize(
      current,
      width: current.width ~/ 2,
      height: current.height ~/ 2,
      interpolation: img.Interpolation.cubic,
    );
  }
  if (current.width == size) return current;
  return img.copyResize(
    current,
    width: size,
    height: size,
    interpolation: img.Interpolation.cubic,
  );
}

/// 缩到 [scale] 大小、放在透明底正中（自适应图标前景这类要留边距的场合）
img.Image _padded(img.Image source, int size, {required double scale}) {
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  final inner = math.max(1, (size * scale).round());
  return img.compositeImage(
    canvas,
    _scaled(source, inner),
    dstX: (size - inner) ~/ 2,
    dstY: (size - inner) ~/ 2,
    blend: img.BlendMode.alpha,
    linearBlend: true,
  );
}

/// 圆角（只给预览素材用；上架图标保持方角，圆角由系统裁切）
img.Image _rounded(img.Image image, double radius) {
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
  return image;
}

void _write(String path, img.Image image) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('写入 $path (${image.width}x${image.height})');
}

/// 自检：每个 iOS 尺寸都要对得上，且**不能带 alpha 通道**（上架硬要求）
void _selfCheck(img.Image source, Map<String, int> iosIcons) {
  const dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  iosIcons.forEach((name, size) {
    final decoded = img.decodePng(File('$dir/$name').readAsBytesSync());
    if (decoded == null) throw StateError('$name 写出来不是合法的 PNG');
    if (decoded.width != size || decoded.height != size) {
      throw StateError(
        '$name 尺寸不对：${decoded.width}x${decoded.height}，应该是 $size',
      );
    }
    if (decoded.numChannels != 3) {
      throw StateError(
        '$name 带了 alpha 通道（${decoded.numChannels} 通道），iOS 上架会被拒',
      );
    }
  });
  stdout.writeln(
    '自检通过：iOS ${iosIcons.length} 个尺寸都对、都没有 alpha 通道'
    '（源图 ${source.width}x${source.height}）',
  );
}
