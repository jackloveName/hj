import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update.dart';
import '../theme/tokens.dart';
import 'kit.dart';

enum AppUpdateDialogResult { dismissed, opened }

/// 版本更新弹窗。视觉与交互参考 jianzhirj：
/// 普通更新可稍后，强制更新（updateType=2）有下载地址时不可关闭。
class AppUpdateDialog extends StatelessWidget {
  const AppUpdateDialog({
    super.key,
    required this.info,
    required this.currentVersion,
  });

  final AppUpdateInfo info;
  final String currentVersion;

  bool get _canCancel => !info.blocking;

  @override
  Widget build(BuildContext context) {
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_canCancel) {
          _dismiss(context);
        } else {
          zToast(context, '请先完成版本更新');
        }
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_canCancel) {
                    _dismiss(context);
                  } else {
                    zToast(context, '请先完成版本更新');
                  }
                },
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: const ColoredBox(color: Color(0x8A19221D)),
                ),
              ),
            ),
            SafeArea(
              minimum: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 370),
                    child: _UpdateCard(
                      info: info,
                      currentVersion: currentVersion,
                      canCancel: _canCancel,
                      isIos: isIos,
                      onCancel: () => _dismiss(context),
                      onOpen: () => _open(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _dismiss(BuildContext context) {
    Navigator.of(context).pop(AppUpdateDialogResult.dismissed);
  }

  /// 优先用系统浏览器 / App Store 打开；打不开就复制地址作为退路。
  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(info.url);
    var launched = false;
    if (uri != null) {
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        launched = false;
      }
    }
    if (!context.mounted) return;
    if (!launched) {
      await Clipboard.setData(ClipboardData(text: info.url));
      if (!context.mounted) return;
    }
    Navigator.of(context).pop(AppUpdateDialogResult.opened);
    if (!launched) {
      zToast(context, '下载地址已复制，可粘贴到浏览器打开');
    }
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({
    required this.info,
    required this.currentVersion,
    required this.canCancel,
    required this.isIos,
    required this.onCancel,
    required this.onOpen,
  });

  final AppUpdateInfo info;
  final String currentVersion;
  final bool canCancel;
  final bool isIos;
  final VoidCallback onCancel;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final notes = info.notes.trim().isEmpty
        ? '优化使用体验并修复已知问题。'
        : info.notes.trim();
    final (badgeBg, badgeFg) = ZTag.paletteOf(
      info.force ? ZTone.danger : ZTone.brand,
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Z.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Z.card.withValues(alpha: 0.8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x47121F19),
            blurRadius: 55,
            offset: Offset(0, 19),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _UpdateHero(
            info: info,
            currentVersion: currentVersion,
            canCancel: canCancel,
            onCancel: onCancel,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              children: [
                _VersionRow(
                  info: info,
                  badgeBackground: badgeBg,
                  badgeForeground: badgeFg,
                ),
                const SizedBox(height: 14),
                _NotesBlock(notes: notes),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (canCancel) ...[
                      Expanded(
                        child: _ActionButton(label: '稍后更新', onTap: onCancel),
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (info.url.isNotEmpty)
                      Expanded(
                        child: _ActionButton(
                          label: isIos ? '前往 App Store' : '立即更新',
                          icon: Icons.download_rounded,
                          primary: true,
                          onTap: onOpen,
                        ),
                      ),
                    if (info.url.isEmpty && info.force)
                      Expanded(
                        child: _ActionButton(
                          label: '更新地址暂未配置',
                          onTap: () => zToast(context, '请联系管理员配置更新地址'),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 13),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_outlined, size: 15, color: Z.ink3),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '更新由官方版本配置提供，数据仍保存在你的账号下',
                        textAlign: TextAlign.center,
                        style: ZText.small.copyWith(
                          fontSize: 10.5,
                          height: 1.4,
                          color: Z.ink3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateHero extends StatelessWidget {
  const _UpdateHero({
    required this.info,
    required this.currentVersion,
    required this.canCancel,
    required this.onCancel,
  });

  final AppUpdateInfo info;
  final String currentVersion;
  final bool canCancel;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Z.card, Z.page, Z.brandTint],
          stops: const [0, 0.58, 1],
        ),
      ),
      child: CustomPaint(
        painter: _UpdateGridPainter(),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(21, 22, 21, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AppMark(logoUrl: info.logoUrl),
                  const SizedBox(height: 15),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Z.card.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: Z.brand.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          size: 13,
                          color: Z.brand,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '版本更新',
                          style: ZText.micro.copyWith(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Z.brandDeep,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('应用有新版本了', style: ZText.display),
                  const SizedBox(height: 7),
                  Text(
                    '当前 $currentVersion · 最新 ${info.version}',
                    style: ZText.caption.copyWith(fontSize: 12, height: 1.35),
                  ),
                ],
              ),
            ),
            if (canCancel)
              Positioned(
                top: 14,
                right: 14,
                child: Material(
                  color: Z.card.withValues(alpha: 0.82),
                  shape: CircleBorder(side: BorderSide(color: Z.line)),
                  child: IconButton(
                    tooltip: '稍后更新',
                    onPressed: onCancel,
                    icon: const Icon(Icons.close_rounded, size: 19),
                    color: Z.brand,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.info,
    required this.badgeBackground,
    required this.badgeForeground,
  });

  final AppUpdateInfo info;
  final Color badgeBackground;
  final Color badgeForeground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Z.card.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Z.line2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '版本 ${info.version}',
                  style: ZText.title4.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  info.force ? '需要更新后继续使用' : '更新后体验更稳定',
                  style: ZText.caption.copyWith(fontSize: 11.5, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: badgeBackground,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              info.force ? '必须更新' : '新版本',
              style: ZText.micro.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: badgeForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotesBlock extends StatelessWidget {
  const _NotesBlock({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Z.page,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Z.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, size: 17, color: Z.brand),
              const SizedBox(width: 6),
              Text(
                '本次更新',
                style: ZText.labelStrong.copyWith(
                  color: Z.brandDeep,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Text(
                notes,
                style: ZText.caption.copyWith(fontSize: 12.5, height: 1.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? null : Z.card,
      borderRadius: BorderRadius.circular(99),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        height: 46,
        decoration: BoxDecoration(
          gradient: primary ? Z.brandGradient : null,
          borderRadius: BorderRadius.circular(99),
          border: primary ? null : Border.all(color: Z.line),
          boxShadow: primary ? Z.brandGlow : null,
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: Colors.white),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZText.labelStrong.copyWith(
                      color: primary ? Colors.white : Z.ink3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppMark extends StatelessWidget {
  const _AppMark({required this.logoUrl});

  final String logoUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        gradient: Z.logoGradient,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2B2F6BFF),
            blurRadius: 22,
            offset: Offset(0, 9),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: logoUrl.isEmpty
          ? const Icon(
              Icons.verified_user_rounded,
              size: 28,
              color: Colors.white,
            )
          : Image.network(
              logoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.verified_user_rounded,
                size: 28,
                color: Colors.white,
              ),
            ),
    );
  }
}

class _UpdateGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Z.ink.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const gap = 27.0;
    for (var x = 0.0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 展示更新弹窗。调用方负责判断版本是否更新。
Future<AppUpdateDialogResult> showAppUpdateDialog({
  required BuildContext context,
  required AppUpdateInfo info,
  required String currentVersion,
}) async {
  final result = await showGeneralDialog<AppUpdateDialogResult>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    barrierLabel: '版本更新',
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) =>
        AppUpdateDialog(info: info, currentVersion: currentVersion),
    transitionBuilder: (_, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
  return result ?? AppUpdateDialogResult.dismissed;
}
