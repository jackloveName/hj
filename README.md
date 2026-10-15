# 租盾（ZuDun）

## 快速开始

```bash
flutter pub get

flutter run -d chrome     # Web（浏览器）
flutter run -d android    # Android（只用于本机调试，不上架）
flutter run -d ios        # iOS（需 macOS，发布目标）

flutter build web --release
```

发布只走 iOS：安卓不做市场发布与合规打包，`android/` 目录仅用于本机调试。
