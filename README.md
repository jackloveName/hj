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

### iOS Release 混淆

```bash
./tool/build_ios_release.sh
```

脚本会执行 Dart AOT 混淆，并把符号文件写到 `build/symbols/ios/`。
发布前必须单独备份该目录，后续分析线上崩溃需要用它还原堆栈。
不要直接用 Xcode 的 Archive 代替这个脚本，否则不会带 Flutter 的混淆参数。
