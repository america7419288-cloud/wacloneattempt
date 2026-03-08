import 'dart:math';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'wallpaper_service.dart';
import 'twallpaper_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ChatWallpaperBackground — place as first child of a Stack in chat screen
// ─────────────────────────────────────────────────────────────────────────────
class ChatWallpaperBackground extends StatefulWidget {
  const ChatWallpaperBackground({super.key});

  @override
  State<ChatWallpaperBackground> createState() =>
      _ChatWallpaperBackgroundState();
}

class _ChatWallpaperBackgroundState extends State<ChatWallpaperBackground>
    with TickerProviderStateMixin {
  TWallpaperController? _wallpaperCtrl;
  bool _isDark = false;

  // Parallax tilt offset (max ±32 px)
  static const double _maxMotion = 32.0;
  double _parallaxX = 0;
  double _parallaxY = 0;

  @override
  void initState() {
    super.initState();
    WallpaperService.instance.addListener(_onConfigChanged);
    _applyConfig(WallpaperService.instance.config);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    if (isDark != _isDark) {
      _isDark = isDark;
      _applyConfig(WallpaperService.instance.config);
    }
  }

  @override
  void dispose() {
    WallpaperService.instance.removeListener(_onConfigChanged);
    WallpaperService.instance.activeController = null;
    _wallpaperCtrl?.dispose();
    super.dispose();
  }

  void _onConfigChanged() {
    _applyConfig(WallpaperService.instance.config);
  }

  /// Darken hex colors by a factor for dark mode (local transform, not saved)
  List<String> _darkenColors(List<String> colors, double factor) {
    return colors.map((hex) {
      final c = _hexToColor(hex);
      final r = (c.red * factor).round().clamp(0, 255);
      final g = (c.green * factor).round().clamp(0, 255);
      final b = (c.blue * factor).round().clamp(0, 255);
      final result = Color.fromARGB(255, r, g, b);
      return '#${result.red.toRadixString(16).padLeft(2,'0')}${result.green.toRadixString(16).padLeft(2,'0')}${result.blue.toRadixString(16).padLeft(2,'0')}';
    }).toList();
  }

  Color _lightestGradientColor(List<String> hexColors) {
    if (hexColors.isEmpty) return const Color(0xFFFFFFFF);
    return hexColors
        .map((h) => _hexToColor(h))
        .reduce((a, b) => a.computeLuminance() >= b.computeLuminance() ? a : b);
  }

  void _applyConfig(WallpaperConfig config) {
    _wallpaperCtrl?.dispose();
    _wallpaperCtrl = null;
    WallpaperService.instance.activeController = null;

    if (config.type == WallpaperType.animatedGradient) {
      final colors = _isDark ? _darkenColors(config.gradientColors, 0.55) : config.gradientColors;
      _wallpaperCtrl = TWallpaperController(vsync: this)
        ..updateColors(colors);
      if (config.animateGradient) {
        _wallpaperCtrl!.startAnimation();
      }
      WallpaperService.instance.activeController = _wallpaperCtrl;
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final config = WallpaperService.instance.config;

    // Apply parallax transform
    return Transform.translate(
      offset: Offset(
        _parallaxX.clamp(-_maxMotion, _maxMotion),
        _parallaxY.clamp(-_maxMotion, _maxMotion),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: _buildBase(config)),
          if (config.svgPatternAsset.isNotEmpty)
            Positioned.fill(
              child: Opacity(
                opacity: config.patternOpacity.clamp(0.0, 1.0),
                child: SvgPicture.asset(
                  config.svgPatternAsset,
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    _lightestGradientColor(config.gradientColors),
                    BlendMode.srcIn,
                  ),
                ),
              ),
            )
          else if (config.pattern != PatternType.none)
            Positioned.fill(
              child: Opacity(
                opacity: config.patternOpacity.clamp(0.0, 1.0),
                child: CustomPaint(
                  painter: PatternPainter(config.pattern, isDark: _isDark),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBase(WallpaperConfig config) {
    switch (config.type) {
      case WallpaperType.animatedGradient:
        if (_wallpaperCtrl != null) {
          return TWallpaperWidget(controller: _wallpaperCtrl!);
        }
        return Container(color: const Color(0xFFDBDDBB));

      case WallpaperType.solidColor:
        return Container(color: _hexToColor(config.solidColor));

      case WallpaperType.staticImage:
        if (config.imagePath.isNotEmpty) {
          return Image.asset(
            config.imagePath,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
        }
        return Container(color: const Color(0xFFEFEBE0));

      case WallpaperType.none:
        return Container(
          color: CupertinoDynamicColor.resolve(
            const CupertinoDynamicColor.withBrightness(
              color: Color(0xFFEFEBE0),
              darkColor: Color(0xFF0D1117),
            ),
            context,
          ),
        );
    }
  }

  Color _hexToColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PatternPainter — draws repeating patterns onto the canvas
// ─────────────────────────────────────────────────────────────────────────────
class PatternPainter extends CustomPainter {
  final PatternType pattern;
  final bool isDark;
  PatternPainter(this.pattern, {this.isDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000)
      ..style = PaintingStyle.fill
      ..strokeWidth = 1.0;

    switch (pattern) {
      case PatternType.dots:
        _drawDots(canvas, size, paint);
      case PatternType.grid:
        _drawGrid(canvas, size, paint);
      case PatternType.diagonal:
        _drawDiagonal(canvas, size, paint);
      case PatternType.circles:
        _drawCircles(canvas, size, paint);
      case PatternType.waves:
        _drawWaves(canvas, size, paint);
      case PatternType.hexagons:
        _drawHexagons(canvas, size, paint);
      case PatternType.none:
        break;
    }
  }

  void _drawDots(Canvas canvas, Size size, Paint paint) {
    const spacing = 22.0;
    for (double x = spacing / 2; x < size.width; x += spacing) {
      for (double y = spacing / 2; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.5, paint);
      }
    }
  }

  void _drawGrid(Canvas canvas, Size size, Paint paint) {
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 0.5;
    const spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawDiagonal(Canvas canvas, Size size, Paint paint) {
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 0.6;
    const spacing = 20.0;
    final total = size.width + size.height;
    for (double offset = -size.height; offset < total; offset += spacing) {
      canvas.drawLine(
        Offset(offset, 0),
        Offset(offset + size.height, size.height),
        paint,
      );
    }
  }

  void _drawCircles(Canvas canvas, Size size, Paint paint) {
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 0.6;
    const spacing = 36.0;
    const radius = 14.0;
    for (double x = spacing / 2; x < size.width + radius; x += spacing) {
      for (double y = spacing / 2; y < size.height + radius; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  void _drawWaves(Canvas canvas, Size size, Paint paint) {
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.0;
    const waveHeight = 6.0;
    const waveLength = 24.0;
    const rowSpacing = 18.0;

    for (double y = rowSpacing; y < size.height + rowSpacing; y += rowSpacing) {
      final path = Path();
      path.moveTo(0, y);
      for (double x = 0; x < size.width + waveLength; x += waveLength) {
        path.relativeQuadraticBezierTo(
            waveLength / 4, -waveHeight, waveLength / 2, 0);
        path.relativeQuadraticBezierTo(
            waveLength / 4, waveHeight, waveLength / 2, 0);
      }
      canvas.drawPath(path, paint);
    }
  }

  void _drawHexagons(Canvas canvas, Size size, Paint paint) {
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 0.7;
    const r = 16.0;
    final w = r * 2;
    final h = sqrt(3) * r;

    for (double row = 0; row * h < size.height + h; row++) {
      final xOffset = (row % 2 == 0) ? 0.0 : w * 0.75;
      for (double col = 0; col * w * 1.5 < size.width + w; col++) {
        final cx = col * w * 1.5 + r + xOffset;
        final cy = row * h + r;
        _drawHex(canvas, Offset(cx, cy), r, paint);
      }
    }
  }

  void _drawHex(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (pi / 3) * i - pi / 6;
      final p = Offset(center.dx + r * cos(angle), center.dy + r * sin(angle));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(PatternPainter old) => old.pattern != pattern || old.isDark != isDark;
}
