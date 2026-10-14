import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/tokens.dart';

/// 照片 / 头图上的实心状态胶囊色（保持三种房源状态一致）
Color statusPillColor(PropertyStatus status) => switch (status) {
  PropertyStatus.active => Z.statusPillActive,
  PropertyStatus.ended => Z.statusPillEnded,
  PropertyStatus.dispute => Z.statusPillDispute,
};

/// 页面外框：统一底色、内容宽度与安全区。
class ZScreen extends StatelessWidget {
  const ZScreen({
    super.key,
    required this.child,
    this.floatingActionButton,
    this.bottomBar,
    this.backgroundColor,
  });

  final Widget child;
  final Widget? floatingActionButton;
  final Widget? bottomBar;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    // 用实际可用宽度判断，而不是窗口宽度：
    // 页面被嵌进外壳的手机框里时不会再多套一层「手机壳」
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > Z.contentMaxWidth + 48;
        // 顶部：内容不进状态栏（安卓/iOS 刘海与状态栏都不会压到标题上）；
        // 底部交给 ZBottomBar 自己补内边距，这样底栏能铺到底、内容仍安全
        final content = SafeArea(
          top: true,
          bottom: false,
          child: Column(
            children: [
              Expanded(child: child),
              ?bottomBar,
            ],
          ),
        );
        return Scaffold(
          backgroundColor: backgroundColor ?? Z.page,
          body: isWide
              ? Center(
                  child: Container(
                    width: Z.contentMaxWidth,
                    margin: const EdgeInsets.symmetric(vertical: Z.s5),
                    decoration: BoxDecoration(
                      color: Z.card,
                      borderRadius: Z.radiusSheet,
                      boxShadow: Z.e2,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: content,
                  ),
                )
              : content,
          floatingActionButton: floatingActionButton,
        );
      },
    );
  }
}

/// 顶部标题栏 —— 对应设计稿 .ab
class ZAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ZAppBar({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.onDark = false,
    this.gradient,
    this.border = true,
    this.centerTitle = true,
  });

  final String? title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final bool onDark;
  final Gradient? gradient;
  final bool border;

  /// 标题居中（默认居中，全项目统一）
  final bool centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final color = onDark ? Colors.white : Z.ink;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? (onDark ? null : Z.page) : null,
        border: border && gradient == null
            ? Border(bottom: BorderSide(color: Z.line2))
            : null,
      ),
      // 标题用 Stack 真正居中（左返回键 / 右操作不参与居中计算），
      // 左右各留出 44 让位，标题过长时省略而不是压到按钮上
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                left: centerTitle ? 44 : (leading == null ? 0 : 40),
                right: centerTitle ? 44 : 0,
              ),
              child: Column(
                crossAxisAlignment: centerTitle
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: centerTitle ? TextAlign.center : TextAlign.start,
                      style: ZText.title2.copyWith(color: color),
                    ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: centerTitle ? TextAlign.center : TextAlign.start,
                      style: ZText.small.copyWith(
                        color: onDark ? const Color(0xB3FFFFFF) : Z.ink4,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              ?leading,
              const Spacer(),
              ...actions,
            ],
          ),
        ],
      ),
    );
  }
}

class ZBackButton extends StatelessWidget {
  const ZBackButton({super.key, this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return _IconAction(
      icon: Icons.arrow_back_ios_new_rounded,
      size: 18,
      color: onDark ? Colors.white : Z.ink,
      onTap: () => Navigator.of(context).maybePop(),
    );
  }
}

class ZIconButton extends StatelessWidget {
  const ZIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.color,
    this.size = 19,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return _IconAction(
      icon: icon,
      size: size,
      color: color,
      onTap: onTap,
      tooltip: tooltip,
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.size,
    required this.color,
    this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final double size;
  final Color? color;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = InkResponse(
      onTap: onTap,
      radius: 22,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        child: Icon(icon, size: size, color: color),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// 底部弹层的标题行：标题 + 右上角关闭键（各弹层不要再各写一遍）
class ZSheetHeader extends StatelessWidget {
  const ZSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onClose,
  });

  final String title;
  final String? subtitle;

  /// 不传时默认 pop 当前弹层
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: ZText.title3.copyWith(fontSize: 17)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: ZText.small),
              ],
            ],
          ),
        ),
        ZIconButton(
          icon: Icons.close_rounded,
          tooltip: '关闭',
          color: Z.ink3,
          onTap: onClose ?? () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// 页面底部操作条：统一「卡片底 + 上边线 + 内边距」，
/// 各页不要再手写这一坨 BoxDecoration。
class ZBottomBar extends StatelessWidget {
  const ZBottomBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    // 底部操作条自己吃下安全区（手势条 / 虚拟导航），内容不会被挡住
    padding: padding.add(
      EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
    ),
    decoration: BoxDecoration(
      color: Z.card,
      border: Border(top: BorderSide(color: Z.line)),
    ),
    child: child,
  );
}

/// 白色卡片 —— 对应设计稿 .pc
class ZCard extends StatelessWidget {
  const ZCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Z.s4),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.color,
    this.gradient,
    this.border,
    this.radius = Z.rLg,
    this.shadow = Z.e1,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final BoxBorder? border;
  final double radius;
  final List<BoxShadow> shadow;

  @override
  Widget build(BuildContext context) {
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? Z.card) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: border ?? (gradient == null ? Border.all(color: Z.line) : null),
        boxShadow: shadow,
      ),
      // 卡片是「有底色的面」，里面再放 ListTile / 带水波纹的行时，
      // 需要一个 Material 祖先，否则会触发「水波纹可能不可见」的调试断言
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );
    return Padding(
      padding: margin,
      child: onTap == null
          ? content
          : InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: onTap,
              child: content,
            ),
    );
  }
}

/// 区块标题 —— 对应设计稿 .sec-t
class ZSectionTitle extends StatelessWidget {
  const ZSectionTitle({
    super.key,
    required this.title,
    this.icon,
    this.iconColor,
    this.moreLabel,
    this.onMore,
    this.titleColor,
    this.margin = const EdgeInsets.only(top: 18, bottom: 10),
  });

  final String title;
  final IconData? icon;
  final Color? iconColor;
  final String? moreLabel;
  final VoidCallback? onMore;
  final Color? titleColor;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: iconColor ?? Z.ink3),
            const SizedBox(width: 7),
          ],
          Text(title, style: ZText.title4.copyWith(color: titleColor ?? Z.ink)),
          const Spacer(),
          if (moreLabel != null)
            // 只有真的能点时（onMore 不为空）才画箭头，避免出现「看着能点却没反应」
            onMore == null
                ? Text(moreLabel!, style: ZText.caption)
                : InkWell(
                    onTap: onMore,
                    child: Row(
                      children: [
                        Text(moreLabel!, style: ZText.caption),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 15,
                          color: Z.ink4,
                        ),
                      ],
                    ),
                  ),
        ],
      ),
    );
  }
}

/// 状态标签 —— 对应设计稿 .st
class ZTag extends StatelessWidget {
  const ZTag({
    super.key,
    required this.label,
    this.tone = ZTone.neutral,
    this.icon,
  });

  final String label;
  final ZTone tone;
  final IconData? icon;

  static (Color bg, Color fg) paletteOf(ZTone tone) => switch (tone) {
    ZTone.ok => (const Color(0x1C12A150), Z.okDeep),
    ZTone.warn => (const Color(0x1FE08600), Z.warnDeep),
    ZTone.danger => (const Color(0x1AE04145), Z.dangerDeep),
    ZTone.brand => (const Color(0x1A2F6BFF), const Color(0xFF1B4BD0)),
    ZTone.violet => (const Color(0x1A6C4BD8), Z.violet),
    ZTone.neutral => (Z.surfaceMuted, Z.ink3),
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = paletteOf(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(color: bg, borderRadius: Z.radiusTag),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: ZIcon.xs, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: ZText.micro.copyWith(fontSize: 11.5, color: fg, height: 1.2),
          ),
        ],
      ),
    );
  }
}

/// 小徽标 —— 对应设计稿 .pill-lg
class ZPill extends StatelessWidget {
  const ZPill({
    super.key,
    required this.label,
    this.background,
    this.foreground,
    this.icon,
    this.gradient,
  });

  final String label;
  final Color? background;
  final Color? foreground;
  final IconData? icon;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: gradient == null ? (background ?? Z.line3) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: foreground ?? Z.ink3),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: Z.font,
              fontFamilyFallback: Z.fallback,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: foreground ?? Z.ink3,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// 按钮 —— 对应设计稿 .btn（主要 / 次要 / 深色主 CTA）
enum ZButtonStyle { primary, ghost, dark }

class ZButton extends StatelessWidget {
  const ZButton({
    super.key,
    required this.label,
    this.onTap,
    this.style = ZButtonStyle.primary,
    this.icon,
    this.height = 48,
    this.expand = true,
    this.width,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onTap;
  final ZButtonStyle style;
  final IconData? icon;
  final double height;
  final bool expand;
  final double? width;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final (
      Gradient? gradient,
      Color? bg,
      Color fg,
      List<BoxShadow> shadow,
    ) = switch (style) {
      ZButtonStyle.primary =>
        danger
            ? (
                const LinearGradient(colors: [Z.danger, Z.dangerDeep]),
                null,
                Colors.white,
                Z.brandGlow,
              )
            : (Z.brandGradient, null, Colors.white, Z.brandGlow),
      ZButtonStyle.dark => (Z.darkCtaGradient, null, Colors.white, Z.e1),
      ZButtonStyle.ghost => (null, Z.card, Z.ink2, const []),
    };

    final child = Container(
      height: height,
      width: width ?? (expand ? double.infinity : null),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: disabled ? null : gradient,
        color: disabled ? Z.line2 : (gradient == null ? bg : null),
        borderRadius: BorderRadius.circular(12),
        border: style == ZButtonStyle.ghost && !disabled
            ? Border.all(color: Z.line)
            : null,
        boxShadow: disabled ? const [] : shadow,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: disabled ? Z.ink4 : fg),
            const SizedBox(width: 6),
          ],
          // 按钮宽度不够时省略文案，而不是抛 RenderFlex 溢出
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: Z.font,
                fontFamilyFallback: Z.fallback,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: disabled ? Z.ink4 : fg,
              ),
            ),
          ),
        ],
      ),
    );

    if (disabled) return child;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: child,
    );
  }
}

/// 列表行 —— 对应设计稿 .lrow
class ZListRow extends StatelessWidget {
  const ZListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconTile,
    this.leading,
    this.trailing,
    this.onTap,
    this.divider = true,
    this.titleColor,
    this.chevron = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? iconTile;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;
  final Color? titleColor;

  /// 右箭头：null = 有 onTap 就自动给（各页不用再手写）；
  /// true / false = 强制有 / 强制没有（例如整张卡可点、行内自己没有 onTap）
  final bool? chevron;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          if (iconTile != null) ...[
            iconTile!,
            const SizedBox(width: 10),
          ] else if (icon != null) ...[
            Icon(icon, size: ZIcon.m, color: Z.ink3),
            const SizedBox(width: 10),
          ] else if (leading != null) ...[
            leading!,
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: ZText.bodyStrong.copyWith(color: titleColor ?? Z.ink),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: ZText.caption.copyWith(height: 1.45)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ] else if ((chevron ?? (onTap != null))) ...[
            const SizedBox(width: 10),
            Icon(Icons.chevron_right_rounded, size: 16, color: Z.ink4),
          ],
        ],
      ),
    );

    return Column(
      children: [
        onTap == null ? row : InkWell(onTap: onTap, child: row),
        if (divider) Divider(height: 1, color: Z.line2),
      ],
    );
  }
}

/// 键值行 —— 对应设计稿 .kv
class ZKv extends StatelessWidget {
  const ZKv({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.mono = false,
    this.divider = true,
    this.valueWidget,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool mono;
  final bool divider;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: ZText.label),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child:
                      valueWidget ??
                      Text(
                        value,
                        textAlign: TextAlign.right,
                        style: mono
                            ? ZText.mono.copyWith(color: valueColor ?? Z.ink)
                            : ZText.labelStrong.copyWith(
                                color: valueColor ?? Z.ink,
                              ),
                      ),
                ),
              ),
            ],
          ),
        ),
        if (divider)
          SizedBox(height: 1, child: DashedLine(color: Z.line2)),
      ],
    );
  }
}

class DashedLine extends StatelessWidget {
  const DashedLine({super.key, this.color, this.height = 1});

  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: CustomPaint(painter: _DashedPainter(color: color ?? Z.line)),
  );
}

class _DashedPainter extends CustomPainter {
  _DashedPainter({required this.color});

  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color ?? Z.line
      ..strokeWidth = size.height;
    const dash = 4.0;
    const gap = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + dash).clamp(0, size.width), size.height / 2),
        paint,
      );
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter oldDelegate) => false;
}

/// 横向选项条 —— 对应设计稿 .ctr
class ZChips<T> extends StatelessWidget {
  const ZChips({
    super.key,
    required this.options,
    required this.value,
    required this.labelOf,
    required this.onChanged,
    this.emphasize = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<T> options;
  final T value;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  /// true 时选中态使用品牌色浅底（.onb），否则使用深色实底（.on）
  final bool emphasize;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final option = options[index];
          final selected = option == value;
          return InkWell(
            borderRadius: BorderRadius.circular(100),
            onTap: () => onChanged(option),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: selected
                    ? (emphasize ? Z.brandTint : Z.ink)
                    : Z.card,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: selected
                      ? (emphasize ? const Color(0x472F6BFF) : Z.ink)
                      : Z.line,
                ),
              ),
              child: Text(
                labelOf(option),
                style: TextStyle(
                  fontFamily: Z.font,
                  fontFamilyFallback: Z.fallback,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? (emphasize ? Z.brand : Z.page)
                      : Z.ink3,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 表单字段 —— 对应设计稿 .field
class ZField extends StatelessWidget {
  const ZField({
    super.key,
    required this.label,
    this.child,
    this.required = false,
    this.trailing,
  });

  final String label;
  final Widget? child;
  final bool required;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: ZText.caption),
              if (required) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x17E04145),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    '必填',
                    style: TextStyle(
                      fontFamily: Z.font,
                      fontFamilyFallback: Z.fallback,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Z.dangerDeep,
                    ),
                  ),
                ),
              ],
              if (trailing != null) ...[const Spacer(), trailing!],
            ],
          ),
          const SizedBox(height: 6),
          ?child,
        ],
      ),
    );
  }
}

/// 空状态
class ZEmpty extends StatelessWidget {
  const ZEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Z.brandTint,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: Z.brand),
            ),
            const SizedBox(height: 16),
            Text(title, style: ZText.title4),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: ZText.caption.copyWith(height: 1.6),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 200,
                child: ZButton(label: actionLabel!, onTap: onAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 四步进度条 —— 对应设计稿取证流程
class ZSteps extends StatelessWidget {
  const ZSteps({super.key, required this.steps, required this.current});

  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(top: 11),
                color: i <= current ? Z.brand : Z.line,
              ),
            ),
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i < current
                      ? Z.brand
                      : (i == current ? Z.card : Z.line2),
                  shape: BoxShape.circle,
                  border: i == current
                      ? Border.all(color: Z.brand, width: 2)
                      : null,
                  boxShadow: i == current
                      ? const [
                          BoxShadow(color: Color(0x1F2F6BFF), spreadRadius: 3),
                        ]
                      : null,
                ),
                child: i < current
                    ? const Icon(
                        Icons.check_rounded,
                        size: 12,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(height: 5),
              Text(
                steps[i],
                style: TextStyle(
                  fontFamily: Z.font,
                  fontFamilyFallback: Z.fallback,
                  fontSize: 11,
                  fontWeight: i <= current ? FontWeight.w600 : FontWeight.w400,
                  color: i <= current ? Z.brand : Z.ink4,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 提示条（信息 / 警告）
class ZHintBar extends StatelessWidget {
  const ZHintBar({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.tone = ZTone.brand,
    this.trailing,
  });

  final String text;
  final IconData icon;
  final ZTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      ZTone.ok => Z.ok,
      ZTone.warn => Z.warn,
      ZTone.danger => Z.danger,
      ZTone.violet => Z.violet,
      _ => Z.brand,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [color.withValues(alpha: 0.09), Z.card],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: ZText.caption.copyWith(height: 1.5, color: Z.ink2),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 小圆点
class ZDot extends StatelessWidget {
  const ZDot({super.key, required this.color, this.size = 7});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

OverlayEntry? _zToastEntry;

/// 顶部轻提示：替代底部 SnackBar —— 提示落在视线所在的上方，也不挡底部按钮。
/// 200ms 滑入，停 2.4 秒后自动淡出，点一下可以立刻收掉。
void zToast(BuildContext context, String message, {ZTone tone = ZTone.neutral}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  // 同一时刻只留一条，避免连点时叠一摞
  _zToastEntry?.remove();
  _zToastEntry = null;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ZTopToast(
      message: message,
      tone: tone,
      onDismissed: () {
        if (identical(_zToastEntry, entry)) _zToastEntry = null;
        entry.remove();
      },
    ),
  );
  _zToastEntry = entry;
  overlay.insert(entry);
}

/// 顶部轻提示本体（可以点掉，也会自己消失）
class _ZTopToast extends StatefulWidget {
  const _ZTopToast({
    required this.message,
    required this.tone,
    required this.onDismissed,
  });

  final String message;
  final ZTone tone;
  final VoidCallback onDismissed;

  @override
  State<_ZTopToast> createState() => _ZTopToastState();
}

class _ZTopToastState extends State<_ZTopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    reverseDuration: const Duration(milliseconds: 160),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(const Duration(milliseconds: 2400), _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.tone) {
      ZTone.danger => Z.danger,
      ZTone.warn => Z.warn,
      ZTone.ok => Z.ok,
      _ => Z.brand,
    };
    final icon = switch (widget.tone) {
      ZTone.danger => Icons.error_outline_rounded,
      ZTone.warn => Icons.info_outline_rounded,
      ZTone.ok => Icons.check_circle_outline_rounded,
      _ => Icons.info_outline_rounded,
    };
    final top = MediaQuery.paddingOf(context).top + 10;

    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: SlideTransition(
          position: Tween(
            begin: const Offset(0, -0.6),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
          ),
          child: FadeTransition(
            opacity: _controller,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: Z.contentMaxWidth - 32,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _dismiss,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: Z.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Z.line),
                        boxShadow: Z.e3,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 16, color: color),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              widget.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: ZText.body.copyWith(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ),
    );
  }
}

Future<bool> zConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelText, style: TextStyle(color: Z.ink3)),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: Z.danger)
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<T?> zPush<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => page));
