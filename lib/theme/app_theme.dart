import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

class ZTheme {
  ZTheme._();

  static ThemeData light() => _theme(Brightness.light);

  static ThemeData dark() => _theme(Brightness.dark);

  /// 明暗共用一套装配：进来先切令牌的明暗，再按当前亮度取色
  static ThemeData _theme(Brightness brightness) {
    // 注意：这里**不能**顺手改全局令牌。明暗两套主题会在同一次 build 里
    // 各构造一次（theme + darkTheme），后构造的那个会把令牌写死，
    // 谁先谁后是巧合，不是逻辑。令牌统一由 ZudunApp 在 build 前设定。
    final scheme =
        ColorScheme.fromSeed(seedColor: Z.brand, brightness: brightness)
            .copyWith(
              primary: Z.brand,
              onPrimary: Colors.white,
              secondary: Z.violet,
              surface: Z.card,
              onSurface: Z.ink,
              error: Z.danger,
              outline: Z.line,
              outlineVariant: Z.line2,
              surfaceContainerHighest: Z.line3,
            );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: Z.font,
      fontFamilyFallback: Z.fallback,
      scaffoldBackgroundColor: Z.page,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Z.page,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Z.ink,
        toolbarHeight: 56,
        titleTextStyle: TextStyle(
          fontFamily: Z.font,
          fontFamilyFallback: Z.fallback,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: Z.ink,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: Z.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Z.rLg),
          side: BorderSide(color: Z.line),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Z.line2,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Z.card,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 14,
        ),
        hintStyle: TextStyle(
          fontFamily: Z.font,
          fontFamilyFallback: Z.fallback,
          fontSize: 14,
          color: Z.ink4,
        ),
        border: _border(Z.line),
        enabledBorder: _border(Z.line),
        focusedBorder: _border(Z.brand, width: 1.5),
        errorBorder: _border(Z.danger),
        focusedErrorBorder: _border(Z.danger, width: 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          backgroundColor: Z.brand,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Z.rMd),
          ),
          textStyle: const TextStyle(
            fontFamily: Z.font,
            fontFamilyFallback: Z.fallback,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          foregroundColor: Z.ink2,
          side: BorderSide(color: Z.line),
          backgroundColor: Z.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Z.rMd),
          ),
          textStyle: const TextStyle(
            fontFamily: Z.font,
            fontFamilyFallback: Z.fallback,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Z.brand,
          textStyle: const TextStyle(
            fontFamily: Z.font,
            fontFamilyFallback: Z.fallback,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Z.card,
        selectedColor: Z.ink,
        side: BorderSide(color: Z.line),
        labelStyle: TextStyle(
          fontFamily: Z.font,
          fontFamilyFallback: Z.fallback,
          fontSize: 13,
          color: Z.ink3,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: Z.font,
          fontFamilyFallback: Z.fallback,
          fontSize: 13,
          color: Z.page,
        ),
        shape: StadiumBorder(side: BorderSide(color: Z.line)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        showCheckmark: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Z.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Z.rXl),
        ),
        titleTextStyle: ZText.title3,
        contentTextStyle: ZText.body.copyWith(color: Z.ink2, height: 1.6),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Z.card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Z.rXl)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Z.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Z.rMd),
        ),
        contentTextStyle: TextStyle(
          fontFamily: Z.font,
          fontFamilyFallback: Z.fallback,
          fontSize: 13,
          color: Z.page,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: Z.brand),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Z.brand : Z.ink4,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Z.brandTint : Z.line2,
        ),
      ),
      // ---------- 交互反馈：Web 上悬停 / 按下 / 焦点都要有可见变化 ----------
      hoverColor: Z.overlayHover,
      highlightColor: Z.overlayPress,
      splashColor: Z.overlayPress,
      focusColor: Z.overlayFocus,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: Z.brand,
        selectionColor: Z.brand.withValues(alpha: 0.18),
        selectionHandleColor: Z.brand,
      ),
      // 页面切换：统一使用 iOS 风格的横向推入，符合设计稿「iOS 浅色」定位
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
        },
      ),
      // 滚动条：细、低干扰、悬停时才明显
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? 8 : 4,
        ),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? Z.ink3.withValues(alpha: 0.45)
              : Z.ink3.withValues(alpha: 0.25),
        ),
        trackColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        crossAxisMargin: 2,
      ),
    );
  }

  static OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: Z.radiusField,
        borderSide: BorderSide(color: color, width: width),
      );
}

/// 滚动行为：桌面 / Web 支持鼠标拖动，并去掉 Android 风格的边缘光晕。
class ZScrollBehavior extends MaterialScrollBehavior {
  const ZScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final isDesktop =
        kIsWeb ||
        switch (defaultTargetPlatform) {
          TargetPlatform.windows ||
          TargetPlatform.macOS ||
          TargetPlatform.linux => true,
          _ => false,
        };
    return isDesktop
        ? child
        : super.buildOverscrollIndicator(context, child, details);
  }
}

/// 常用映射：业务状态 → 设计稿语义色。
Color statusColorOf(String tone) => switch (tone) {
  'ok' => Z.ok,
  'warn' => Z.warn,
  'danger' => Z.danger,
  'brand' => Z.brand,
  'violet' => Z.violet,
  _ => Z.ink3,
};
