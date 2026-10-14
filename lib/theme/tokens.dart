import 'package:flutter/material.dart';

/// 语义色标签（与设计稿「状态标签 Status」一一对应）
enum ZTone { ok, warn, danger, brand, violet, neutral }

/// 设计令牌 —— 与设计稿「02 设计令牌」一一对应。
class Z {
  Z._();

  // ---------- 文本中性色 ----------
  static const Color _inkLight = Color(0xFF0E1F3D);
  static const Color _inkDark = Color(0xFFE8EDF7);
  static Color get ink => _isDark ? _inkDark : _inkLight;

  static bool _isDark = false;

  /// 由主题层在构建时调用：切换明暗后所有语义色、文字样式立即生效
  static void applyBrightness(Brightness brightness) =>
      _isDark = brightness == Brightness.dark;

  /// 当前是否深色：少数「明暗需要两套画法」的地方（照片占位、遮罩）用它分支
  static bool get isDark => _isDark;

  static const Color _ink2Light = Color(0xFF33456B);
  static const Color _ink2Dark = Color(0xFFC4CEE1);
  static Color get ink2 => _isDark ? _ink2Dark : _ink2Light;
  static const Color _ink3Light = Color(0xFF6B7A99);
  static const Color _ink3Dark = Color(0xFF94A2BB);
  static Color get ink3 => _isDark ? _ink3Dark : _ink3Light;
  static const Color _ink4Light = Color(0xFF9AA5BC);
  static const Color _ink4Dark = Color(0xFF6F7E97);
  static Color get ink4 => _isDark ? _ink4Dark : _ink4Light;

  // ---------- 线条 / 背景 ----------
  static const Color _lineLight = Color(0xFFE4E8F0);
  static const Color _lineDark = Color(0xFF2B3546);
  static Color get line => _isDark ? _lineDark : _lineLight;
  static const Color _line2Light = Color(0xFFEFF2F7);
  static const Color _line2Dark = Color(0xFF232D3C);
  static Color get line2 => _isDark ? _line2Dark : _line2Light;
  static const Color _line3Light = Color(0xFFF7F9FC);
  static const Color _line3Dark = Color(0xFF1C2533);
  static Color get line3 => _isDark ? _line3Dark : _line3Light;
  static const Color _pageLight = Color(0xFFF5F7FB);
  static const Color _pageDark = Color(0xFF101725);
  static Color get page => _isDark ? _pageDark : _pageLight;
  static const Color _cardLight = Color(0xFFFFFFFF);
  static const Color _cardDark = Color(0xFF1A2231);
  static Color get card => _isDark ? _cardDark : _cardLight;
  static const Color _shellLight = Color(0xFFE9EDF5);
  static const Color _shellDark = Color(0xFF0A1017);
  static Color get shell => _isDark ? _shellDark : _shellLight;

  // ---------- 品牌色 ----------
  static const Color brand = Color(0xFF2F6BFF); // 品牌蓝
  static const Color brandDeep = Color(0xFF1740B8);
  static const Color brandInk = Color(0xFF0F2E86); // 深海军
  static const Color navy = Color(0xFF0E2A5E); // 主色阶
  static const Color navy2 = Color(0xFF123A7E);
  static const Color _brandTintLight = Color(0xFFEAF0FF);
  static const Color _brandTintDark = Color(0xFF1B2A4A);
  static Color get brandTint => _isDark ? _brandTintDark : _brandTintLight;

  // ---------- 语义色 ----------
  static const Color ok = Color(0xFF12A150); // 已付绿
  static const Color okDeep = Color(0xFF0C7C3D);
  static const Color warn = Color(0xFFE08600); // 待付
  static const Color warnDeep = Color(0xFFA96600);
  static const Color danger = Color(0xFFE04145); // 逾期 / 纠纷
  static const Color dangerDeep = Color(0xFFC0292D);
  static const Color gold = Color(0xFFF0A81E); // 押金金
  static const Color goldLight = Color(0xFFFFD479);
  static const Color goldDeep = Color(0xFFE9A63A);
  static const Color violet = Color(0xFF6C4BD8); // 退租阶段
  static const Color violetDeep = Color(0xFF4A2CA8);
  static const Color violetInk = Color(0xFF1B1150);

  // ---------- 取证相机（深色沉浸） ----------
  static const Color camera = Color(0xFF0A0F1A);
  static const Color cameraText = Color(0xFF8A97AF);
  static const Color cameraChip = Color(0xFFE5EAF3);
  static const Color cameraAnnotate = Color(0xFFFF4D4F);

  // ---------- 圆角 ----------
  static const double rSm = 8;
  static const double rMd = 12;
  static const double rLg = 16;
  static const double rXl = 24;

  // ---------- 间距 ----------
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;

  /// 页面内容横向内边距（对应设计稿 .body 的 14px × 1.25）
  static const double pagePadding = 16;

  /// Web / 桌面端的内容最大宽度：按手机稿居中呈现
  static const double contentMaxWidth = 460;

  // ---------- 深色底上的文字与覆盖层（首页头图 / 取证相机 / 退租对比） ----------
  /// 深色卡片里的副文字
  static const Color onDarkMuted = Color(0xFF9FB6DC);

  /// 深色底上的小字号标签（比 onDarkMuted 更亮，保证对比度）
  static const Color onDarkSoft = Color(0xE0FFFFFF);

  /// 深色底上的浅色胶囊
  static const Color onDarkChip = Color(0x1CFFFFFF);

  /// 深色底上的分隔线
  static const Color onDarkLine = Color(0x21FFFFFF);

  /// 照片上的深色徽标（如「还有 N 天到期」）
  static const Color scrimNavy = Color(0xB80A1730);

  /// 照片上的中性黑色遮罩（缩略图上的关闭按钮、照片角标底）
  static const Color photoScrim = Color(0x8A000000);

  /// 照片 / 头图上的实心状态胶囊
  static const Color statusPillActive = Color(0xEB12A150);
  static const Color statusPillEnded = Color(0xE69AA5BC);
  static const Color statusPillDispute = Color(0xEBE04145);

  // ---------- 浅色辅助面 ----------
  /// 次级灰色底（胶囊、只读块）
  static const Color _surfaceMutedLight = Color(0xFFF1F5F9);
  static const Color _surfaceMutedDark = Color(0xFF202A38);
  static Color get surfaceMuted => _isDark ? _surfaceMutedDark : _surfaceMutedLight;

  /// 虚线「添加」框的描边
  static const Color _dashedLight = Color(0xFFC7D4E8);
  static const Color _dashedDark = Color(0xFF37435A);
  static Color get dashed => _isDark ? _dashedDark : _dashedLight;

  /// 品牌色淡水洗（卡片顶部渐变起点、统计卡底色）
  static const Color brandWash = Color(0x0F2F6BFF);

  // ---------- 交互蒙层（Web 悬停 / 按下 / 焦点） ----------
  static const Color overlayHover = Color(0x0D0E1F3D);
  static const Color overlayPress = Color(0x140E1F3D);
  static const Color overlayFocus = Color(0x1A2F6BFF);

  // 常用 borderRadius 简写
  static const BorderRadius radiusTag = BorderRadius.all(Radius.circular(rSm));
  static const BorderRadius radiusField = BorderRadius.all(
    Radius.circular(rMd),
  );
  static const BorderRadius radiusCard = BorderRadius.all(Radius.circular(rLg));
  static const BorderRadius radiusSheet = BorderRadius.all(
    Radius.circular(rXl),
  );

  // ---------- 渐变 ----------
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2F6BFF), Color(0xFF1740B8)],
  );
  static const LinearGradient logoGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4E86FF), Color(0xFF1B47C4)],
  );
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment(-0.6, -1.0),
    end: Alignment(0.6, 1.0),
    colors: [Color(0xFF0F2A5E), Color(0xFF17427F)],
  );
  static const LinearGradient navyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0E2A5E), Color(0xFF17427F)],
  );
  static const LinearGradient darkCtaGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0E2A5E), Color(0xFF123A7E)],
  );
  static const LinearGradient violetGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B1150), Color(0xFF4A2CA8)],
  );
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFD479), Color(0xFFE9A63A)],
  );
  static const LinearGradient healthGradient = LinearGradient(
    colors: [Color(0xFF2F6BFF), Color(0xFF12A150)],
  );

  // ---------- 阴影 e1 / e2 / e3 ----------
  static const List<BoxShadow> e1 = [
    BoxShadow(color: Color(0x0D0E1F3D), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> e2 = [
    BoxShadow(
      color: Color(0x1A0E1F3D),
      blurRadius: 20,
      spreadRadius: -4,
      offset: Offset(0, 6),
    ),
  ];
  static const List<BoxShadow> e3 = [
    BoxShadow(
      color: Color(0x330E1F3D),
      blurRadius: 46,
      spreadRadius: -12,
      offset: Offset(0, 18),
    ),
  ];
  static const List<BoxShadow> brandGlow = [
    BoxShadow(
      color: Color(0x8C2F6BFF),
      blurRadius: 14,
      spreadRadius: -4,
      offset: Offset(0, 6),
    ),
  ];

  // ---------- 字体族 ----------
  static const String font = 'Outfit';
  static const String cjk = 'NotoSansSC';
  static const String mono = 'JetBrainsMono';
  static const List<String> fallback = <String>[cjk];
  static const List<String> monoFallback = <String>[cjk, font];
}

/// 图标尺寸阶梯：全项目只用这 5 档，避免 13/14/16/18/19/21 混用。
class ZIcon {
  ZIcon._();

  static const double xs = 13;
  static const double s = 15;
  static const double m = 17;
  static const double l = 20;
  static const double xl = 22;
}

/// 文字层级 —— 对应设计稿「字体层级」。
class ZText {
  ZText._();

  static TextStyle get display => TextStyle(
    fontFamily: Z.font,
    fontFamilyFallback: Z.fallback,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.9,
    height: 1.15,
    color: Z.ink,
  );

  static TextStyle get title1 => TextStyle(
    fontFamily: Z.font,
    fontFamilyFallback: Z.fallback,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    color: Z.ink,
  );

  /// 页面标题栏 / 卡片主标题
  static TextStyle get title2 => TextStyle(
    fontFamily: Z.font,
    fontFamilyFallback: Z.fallback,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: Z.ink,
  );

  static TextStyle get title3 => TextStyle(
    fontFamily: Z.font,
    fontFamilyFallback: Z.fallback,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Z.ink,
  );

  /// 区块标题 / 卡片主标题
  static TextStyle get title4 => TextStyle(
    fontFamily: Z.font,
    fontFamilyFallback: Z.fallback,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: Z.ink,
  );

  static TextStyle get body => TextStyle(
    fontFamily: Z.font,
    fontFamilyFallback: Z.fallback,
    fontSize: 14,
    color: Z.ink,
  );

  /// 强调正文（金额、要点）
  static TextStyle get bodyStrong => TextStyle(
    fontFamily: Z.font,
    fontFamilyFallback: Z.fallback,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Z.ink,
  );

  static TextStyle get caption => TextStyle(
    fontFamily: Z.font,
    fontFamilyFallback: Z.fallback,
    fontSize: 12,
    color: Z.ink3,
  );

  static TextStyle get label => TextStyle(
    fontFamily: Z.font,
    fontFamilyFallback: Z.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: Z.ink2,
  );

  /// 列表行主标题
  static TextStyle get labelStrong => TextStyle(
    fontFamily: Z.font,
    fontFamilyFallback: Z.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: Z.ink,
  );

  /// 键值行的值
  static TextStyle get captionStrong => TextStyle(
    fontFamily: Z.font,
    fontFamilyFallback: Z.fallback,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Z.ink,
  );

  /// 徽标 / 标签文字
  static TextStyle get micro => TextStyle(
    fontFamily: Z.font,
    fontFamilyFallback: Z.fallback,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: Z.ink3,
  );

  static TextStyle get small => TextStyle(
    fontFamily: Z.font,
    fontFamilyFallback: Z.fallback,
    fontSize: 11.5,
    color: Z.ink4,
  );

  /// 数字 / 日期等宽字体
  static TextStyle get mono => TextStyle(
    fontFamily: Z.mono,
    fontFamilyFallback: Z.monoFallback,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: Z.ink3,
  );

  /// 小号等宽（日期、备注）
  static TextStyle get monoSmall => TextStyle(
    fontFamily: Z.mono,
    fontFamilyFallback: Z.monoFallback,
    fontSize: 10.5,
    fontWeight: FontWeight.w500,
    color: Z.ink4,
  );

  /// 强调数字（抄表读数、用量等需要对齐的数）
  static TextStyle get monoStrong => TextStyle(
    fontFamily: Z.mono,
    fontFamilyFallback: Z.monoFallback,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: Z.ink,
  );
}
