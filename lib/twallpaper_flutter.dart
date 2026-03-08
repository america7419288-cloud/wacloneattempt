import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

// ─────────────────────────────────────────────────────────────────────────────
// _GradientParams — isolate-safe message for compute()
// ─────────────────────────────────────────────────────────────────────────────
class _GradientParams {
  final int width, height;
  final List<double> posXs, posYs; // position X/Y for each color
  final List<double> rs, gs, bs;   // pre-extracted float channels 0.0–1.0

  const _GradientParams({
    required this.width,
    required this.height,
    required this.posXs,
    required this.posYs,
    required this.rs,
    required this.gs,
    required this.bs,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// generateTelegramGradient — ported from Telegram iOS Swift source
// Called via compute() in an isolate
// ─────────────────────────────────────────────────────────────────────────────
Uint8List generateTelegramGradient(_GradientParams p) {
  final w = p.width, h = p.height;
  final pixels = Uint8List(w * h * 4);

  for (int y = 0; y < h; y++) {
    final directPixelY = y / h;
    final centerDistanceY = directPixelY - 0.5;
    final centerDistanceY2 = centerDistanceY * centerDistanceY;

    for (int x = 0; x < w; x++) {
      final directPixelX = x / w;
      final centerDistanceX = directPixelX - 0.5;
      final centerDistance =
          math.sqrt(centerDistanceX * centerDistanceX + centerDistanceY2);

      final swirlFactor = 0.35 * centerDistance;
      final theta = swirlFactor * swirlFactor * 0.8 * 8.0;
      final sinTheta = math.sin(theta);
      final cosTheta = math.cos(theta);

      final pixelX = (0.5 + centerDistanceX * cosTheta - centerDistanceY * sinTheta)
          .clamp(0.0, 1.0);
      final pixelY = (0.5 + centerDistanceX * sinTheta + centerDistanceY * cosTheta)
          .clamp(0.0, 1.0);

      double r = 0, g = 0, b = 0, distanceSum = 0;

      for (int i = 0; i < p.posXs.length; i++) {
        final colorX = p.posXs[i];
        final colorY = 1.0 - p.posYs[i]; // Y is flipped vs Swift
        final dx = pixelX - colorX;
        final dy = pixelY - colorY;
        var distance =
            math.max(0.0, 0.92 - math.sqrt(dx * dx + dy * dy));
        distance = distance * distance * distance;
        distanceSum += distance;
        r += distance * p.rs[i];
        g += distance * p.gs[i];
        b += distance * p.bs[i];
      }

      if (distanceSum < 0.00001) distanceSum = 0.00001;

      final idx = (y * w + x) * 4;
      pixels[idx]     = (r / distanceSum * 255).clamp(0, 255).round();
      pixels[idx + 1] = (g / distanceSum * 255).clamp(0, 255).round();
      pixels[idx + 2] = (b / distanceSum * 255).clamp(0, 255).round();
      pixels[idx + 3] = 255;
    }
  }

  _applySaturation(pixels, 1.7);
  return pixels;
}

// ─────────────────────────────────────────────────────────────────────────────
// _applySaturation — 1.7× boost from adjustSaturationInContext (Swift)
// ─────────────────────────────────────────────────────────────────────────────
void _applySaturation(Uint8List pixels, double s) {
  const rwgt = 0.3086, gwgt = 0.6094, bwgt = 0.0820;
  final a  = (1 - s) * rwgt + s;
  final b_ = (1 - s) * rwgt;
  final c  = (1 - s) * rwgt;
  final d  = (1 - s) * gwgt;
  final e  = (1 - s) * gwgt + s;
  final f  = (1 - s) * gwgt;
  final g  = (1 - s) * bwgt;
  final h  = (1 - s) * bwgt;
  final ii = (1 - s) * bwgt + s;
  for (int i = 0; i < pixels.length; i += 4) {
    final rr = pixels[i] / 255.0;
    final gr = pixels[i + 1] / 255.0;
    final bl = pixels[i + 2] / 255.0;
    pixels[i]     = ((a * rr + d * gr + g * bl) * 255).clamp(0, 255).round();
    pixels[i + 1] = ((b_ * rr + e * gr + h * bl) * 255).clamp(0, 255).round();
    pixels[i + 2] = ((c * rr + f * gr + ii * bl) * 255).clamp(0, 255).round();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 8 base positions — from Telegram iOS Swift source
// ─────────────────────────────────────────────────────────────────────────────
const _basePositions = <Offset>[
  Offset(0.80, 0.10),
  Offset(0.60, 0.20),
  Offset(0.35, 0.25),
  Offset(0.25, 0.60),
  Offset(0.20, 0.90),
  Offset(0.40, 0.80),
  Offset(0.65, 0.75),
  Offset(0.75, 0.40),
];

/// Shift base positions left by `phase % 8`, then gather indices 0,2,4,6
List<Offset> _getPositions(int phase) {
  final shifted = List<Offset>.from(_basePositions);
  final offset = phase % 8;
  for (int i = 0; i < offset; i++) {
    shifted.add(shifted.removeAt(0));
  }
  return [shifted[0], shifted[2], shifted[4], shifted[6]];
}

const int _kRenderSize = 80; // Telegram renders at 80×80

// ─────────────────────────────────────────────────────────────────────────────
// TWallpaperController — drives the Telegram-style animated gradient
// ─────────────────────────────────────────────────────────────────────────────
class TWallpaperController {
  final TickerProvider vsync;

  List<Color> _colors = [];
  List<Color> get colors => _colors;
  
  int _phase = 0;
  bool _disposed = false;

  /// The rendered gradient image. Widgets listen to this.
  final ValueNotifier<ui.Image?> imageNotifier = ValueNotifier(null);

  /// Cache of generated initial frames so returning to chat is instant
  static final Map<String, ui.Image> _firstFrameCache = {};
  
  Ticker? _loopTicker;
  bool _loopRunning = false;
  Duration _loopElapsed = Duration.zero;

  TWallpaperController({required this.vsync});

  // ── Public API ─────────────────────────────────────────────────────────

  /// Set or update the 4 gradient colors. Regenerates immediately.
  void updateColors(List<String> hexColors) {
    _colors = hexColors.map(_hexToColor).toList();
    while (_colors.length < 4) {
      _colors.add(_colors.last);
    }
    
    final cacheKey = hexColors.join(',');
    if (_firstFrameCache.containsKey(cacheKey)) {
      imageNotifier.value = _firstFrameCache[cacheKey];
    }
    
    _regenerate(_getPositions(_phase), cacheKey: cacheKey);
  }

  /// Trigger a single animation event (phase shift with interpolation).
  /// Called on message send or user tap.
  void animateEvent() {
    if (_disposed || _colors.isEmpty) return;

    final oldPositions = _getPositions(_phase);
    _phase = (_phase - 1) % 8;
    if (_phase < 0) _phase += 8;
    final newPositions = _getPositions(_phase);

    _animateTransition(oldPositions, newPositions);
  }

  /// Start continuous slow animation: shifts phase every 3 seconds.
  void startAnimation() {
    if (_loopRunning || _disposed) return;
    _loopRunning = true;
    _loopElapsed = Duration.zero;
    _loopTicker?.dispose();
    _loopTicker = vsync.createTicker((elapsed) {
      if (_disposed) return;
      final delta = elapsed - _loopElapsed;
      if (delta.inMilliseconds >= 3000) {
        _loopElapsed = elapsed;
        animateEvent();
      }
    });
    _loopTicker!.start();
  }

  /// Stop continuous animation.
  void stopAnimation() {
    _loopRunning = false;
    _loopTicker?.stop();
    _loopTicker?.dispose();
    _loopTicker = null;
  }

  void dispose() {
    _disposed = true;
    stopAnimation();
    _animTicker?.stop();
    _animTicker?.dispose();
    _animTicker = null;
    imageNotifier.dispose();
  }

  // ── Internals ──────────────────────────────────────────────────────────

  Ticker? _animTicker;
  int _animFrame = 0;
  static const int _kAnimFrames = 12;

  void _animateTransition(List<Offset> from, List<Offset> to) {
    _animTicker?.stop();
    _animTicker?.dispose();
    _animFrame = 0;

    _animTicker = vsync.createTicker((elapsed) {
      if (_disposed) return;
      final t = Curves.easeInOut
          .transform((_animFrame / (_kAnimFrames - 1)).clamp(0.0, 1.0));

      final morphed = <Offset>[];
      for (int i = 0; i < from.length; i++) {
        morphed.add(Offset.lerp(from[i], to[i], t)!);
      }
      _regenerate(morphed);

      _animFrame++;
      if (_animFrame >= _kAnimFrames) {
        _animTicker?.stop();
        _animTicker?.dispose();
        _animTicker = null;
      }
    });
    _animTicker!.start();
  }

  Future<void> _regenerate(List<Offset> positions, {String? cacheKey}) async {
    if (_disposed || _colors.length < 4) return;

    final params = _GradientParams(
      width: _kRenderSize,
      height: _kRenderSize,
      posXs: positions.map((o) => o.dx).toList(),
      posYs: positions.map((o) => o.dy).toList(),
      rs: _colors.map((c) => c.red / 255.0).toList(),
      gs: _colors.map((c) => c.green / 255.0).toList(),
      bs: _colors.map((c) => c.blue / 255.0).toList(),
    );

    final pixels = await compute(generateTelegramGradient, params);
    if (_disposed) return;

    // Decode RGBA pixels into a ui.Image
    final completer = ui.ImmutableBuffer.fromUint8List(pixels);
    final buffer = await completer;
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: _kRenderSize,
      height: _kRenderSize,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    if (_disposed) {
      frame.image.dispose();
      return;
    }

    final old = imageNotifier.value;
    imageNotifier.value = frame.image;
    
    if (cacheKey != null) {
      _firstFrameCache[cacheKey] = frame.image;
    }

    if (old != null && !_firstFrameCache.values.contains(old)) {
      old.dispose();
    }
  }

  static Color _hexToColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TWallpaperWidget — renders the gradient from TWallpaperController
// ─────────────────────────────────────────────────────────────────────────────
class TWallpaperWidget extends StatelessWidget {
  final TWallpaperController controller;

  const TWallpaperWidget({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ValueListenableBuilder<ui.Image?>(
        valueListenable: controller.imageNotifier,
        builder: (context, image, _) {
          Widget content;
          if (image == null) {
            final c = controller.colors;
            if (c.length >= 2) {
              content = Container(
                key: const ValueKey('fallback'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [c[0], c[1]],
                  ),
                ),
              );
            } else {
              content = Container(
                key: const ValueKey('fallback_solid'),
                color: const Color(0xFFDBDDBB),
              );
            }
          } else {
            content = SizedBox.expand(
              key: const ValueKey('wallpaper_image'), // Use a stable key so AnimatedSwitcher doesn't fire continuously
              child: RawImage(
                image: image,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
              ),
            );
          }
          
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: <Widget>[
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            child: content,
          );
        },
      ),
    );
  }
}
