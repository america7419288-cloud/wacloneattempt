import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'twallpaper_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WallpaperType — what kind of background the user has chosen
// ─────────────────────────────────────────────────────────────────────────────
enum WallpaperType {
  animatedGradient,
  solidColor,
  staticImage,
  none,
}

// ─────────────────────────────────────────────────────────────────────────────
// PatternType — optional dot/line pattern overlaid on top of the wallpaper
// ─────────────────────────────────────────────────────────────────────────────
enum PatternType {
  none,
  dots,
  grid,
  diagonal,
  circles,
  waves,
  hexagons,
}

// ─────────────────────────────────────────────────────────────────────────────
// WallpaperConfig
// ─────────────────────────────────────────────────────────────────────────────
class WallpaperConfig {
  final WallpaperType type;
  final List<String> gradientColors;
  final String solidColor;
  final String imagePath;
  final String svgPatternAsset;
  final PatternType pattern;
  final double patternOpacity;
  final bool animateGradient;

  const WallpaperConfig({
    this.type = WallpaperType.none,
    this.gradientColors = const ['#dbddbb', '#6ba587', '#d5d88d', '#88b884'],
    this.solidColor = '#EDF0F2',
    this.imagePath = '',
    this.svgPatternAsset = '',
    this.pattern = PatternType.none,
    this.patternOpacity = 0.08,
    this.animateGradient = true,
  });

  static const WallpaperConfig defaultConfig = WallpaperConfig();

  static const WallpaperConfig telegramGreen = WallpaperConfig(
    type: WallpaperType.animatedGradient,
    gradientColors: ['#dbddbb', '#6ba587', '#d5d88d', '#88b884'],
    pattern: PatternType.dots,
    patternOpacity: 0.07,
  );

  static const WallpaperConfig telegramBlue = WallpaperConfig(
    type: WallpaperType.animatedGradient,
    gradientColors: ['#7FA381', '#FFF5C5', '#336F55', '#FBE37D'],
    pattern: PatternType.none,
    patternOpacity: 0.0,
  );

  static const WallpaperConfig purple = WallpaperConfig(
    type: WallpaperType.animatedGradient,
    gradientColors: ['#e2d2f9', '#b5c6f5', '#d9bff8', '#c0d4f7'],
    pattern: PatternType.circles,
    patternOpacity: 0.06,
  );

  static const WallpaperConfig warm = WallpaperConfig(
    type: WallpaperType.animatedGradient,
    gradientColors: ['#f8c8a0', '#f5a0b8', '#fce4c8', '#f0b8d0'],
    pattern: PatternType.waves,
    patternOpacity: 0.08,
  );

  static const WallpaperConfig midnight = WallpaperConfig(
    type: WallpaperType.animatedGradient,
    gradientColors: ['#1a1a2e', '#16213e', '#0f3460', '#533483'],
    pattern: PatternType.hexagons,
    patternOpacity: 0.12,
  );

  static const WallpaperConfig rose = WallpaperConfig(
    type: WallpaperType.animatedGradient,
    gradientColors: ['#f9a8d4', '#fda4af', '#fdba74', '#fcd34d'],
    pattern: PatternType.diagonal,
    patternOpacity: 0.06,
  );

  static const WallpaperConfig ocean = WallpaperConfig(
    type: WallpaperType.animatedGradient,
    gradientColors: ['#164e63', '#0e7490', '#155e75', '#0891b2'],
    pattern: PatternType.waves,
    patternOpacity: 0.10,
  );

  static const WallpaperConfig spaceDoodle = WallpaperConfig(
    type: WallpaperType.staticImage,
    imagePath: 'assets/wallpapers/space_doodle.jpg',
    pattern: PatternType.none,
    patternOpacity: 0.0,
  );

  static const WallpaperConfig mint = WallpaperConfig(
    type: WallpaperType.animatedGradient,
    gradientColors: ['#a7f3d0', '#6ee7b7', '#d1fae5', '#a7f3d0'],
    pattern: PatternType.grid,
    patternOpacity: 0.07,
  );

  Map<String, dynamic> toJson() => {
        'type': type.index,
        'gradientColors': gradientColors,
        'solidColor': solidColor,
        'imagePath': imagePath,
        'svgPatternAsset': svgPatternAsset,
        'pattern': pattern.index,
        'patternOpacity': patternOpacity,
        'animateGradient': animateGradient,
      };

  factory WallpaperConfig.fromJson(Map<String, dynamic> json) =>
      WallpaperConfig(
        type: WallpaperType.values[json['type'] as int? ?? 0],
        gradientColors: (json['gradientColors'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            ['#dbddbb', '#6ba587', '#d5d88d', '#88b884'],
        solidColor: json['solidColor'] as String? ?? '#EDF0F2',
        imagePath: json['imagePath'] as String? ?? '',
        svgPatternAsset: json['svgPatternAsset'] as String? ?? '',
        pattern: PatternType.values[json['pattern'] as int? ?? 0],
        patternOpacity: (json['patternOpacity'] as num?)?.toDouble() ?? 0.08,
        animateGradient: json['animateGradient'] as bool? ?? true,
      );

  WallpaperConfig copyWith({
    WallpaperType? type,
    List<String>? gradientColors,
    String? solidColor,
    String? imagePath,
    String? svgPatternAsset,
    PatternType? pattern,
    double? patternOpacity,
    bool? animateGradient,
  }) =>
      WallpaperConfig(
        type: type ?? this.type,
        gradientColors: gradientColors ?? this.gradientColors,
        solidColor: solidColor ?? this.solidColor,
        imagePath: imagePath ?? this.imagePath,
        svgPatternAsset: svgPatternAsset ?? this.svgPatternAsset,
        pattern: pattern ?? this.pattern,
        patternOpacity: patternOpacity ?? this.patternOpacity,
        animateGradient: animateGradient ?? this.animateGradient,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// WallpaperService — app-wide singleton
// ─────────────────────────────────────────────────────────────────────────────
class WallpaperService extends ChangeNotifier {
  WallpaperService._();
  static final WallpaperService instance = WallpaperService._();

  static const String _prefsKey = 'wallpaper_config_v1';

  WallpaperConfig _config = WallpaperConfig.defaultConfig;
  WallpaperConfig get config => _config;

  /// The currently active wallpaper controller (set by ChatWallpaperBackground)
  TWallpaperController? _activeController;
  TWallpaperController? get activeController => _activeController;
  set activeController(TWallpaperController? ctrl) => _activeController = ctrl;

  /// Trigger a single animation event on the active wallpaper
  void triggerAnimation() => _activeController?.animateEvent();

  /// Returns an accent color derived from the current wallpaper's lightest gradient color.
  /// Used to tint outgoing bubbles, icons, and interactive UI elements.
  /// Falls back to systemBlue when the wallpaper has no gradient.
  Color accentColor({bool dark = false}) {
    final cfg = _config;
    if (cfg.type == WallpaperType.animatedGradient && cfg.gradientColors.isNotEmpty) {
      // Pick the most saturated color from the gradient (highest chroma)
      final colors = cfg.gradientColors.map(_hexToColor).toList();
      return colors.reduce((a, b) => _chroma(a) >= _chroma(b) ? a : b);
    }
    if (cfg.type == WallpaperType.solidColor && cfg.solidColor.isNotEmpty) {
      return _hexToColor(cfg.solidColor);
    }
    return dark ? const Color(0xFF4FC3F7) : CupertinoColors.systemBlue;
  }

  static double _chroma(Color c) {
    final r = c.red / 255.0, g = c.green / 255.0, b = c.blue / 255.0;
    final max = [r, g, b].reduce((a, b) => a > b ? a : b);
    final min = [r, g, b].reduce((a, b) => a < b ? a : b);
    return max - min;
  }

  static Color _hexToColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        _config = WallpaperConfig.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        _config = WallpaperConfig.defaultConfig;
      }
    }
    notifyListeners();
  }

  Future<void> apply(WallpaperConfig config) async {
    _config = config;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(config.toJson()));
  }

  Future<void> reset() => apply(WallpaperConfig.defaultConfig);
}
