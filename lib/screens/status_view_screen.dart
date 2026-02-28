import 'dart:async';
import 'package:flutter/cupertino.dart';

class StatusViewScreen extends StatefulWidget {
  final String url;
  final String senderName;
  final VoidCallback? onFinished;

  const StatusViewScreen({
    super.key,
    required this.url,
    required this.senderName,
    this.onFinished,
  });

  @override
  State<StatusViewScreen> createState() => _StatusViewScreenState();
}

class _StatusViewScreenState extends State<StatusViewScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  Timer? _timer;
  bool _imageLoaded = false;

  @override
  void initState() {
    super.initState();
    // 5 second timer for the status
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addListener(() {
        setState(() {});
      });

    // Don't start forward() here — wait until image loads
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        if (widget.onFinished != null) {
          widget.onFinished!();
        }
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _progressController.stop();
  }

  void _onTapUp(TapUpDetails details) {
    // Resume animation
    _progressController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: () => _progressController.forward(),
        child: SafeArea(
          child: Stack(
            children: [
              // Main Image
              Center(
                child: Image.network(
                  widget.url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) {
                      // Image loaded — start the progress timer
                      if (!_imageLoaded) {
                        _imageLoaded = true;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _progressController.forward();
                        });
                      }
                      return child;
                    }
                    return const Center(
                      child: CupertinoActivityIndicator(
                        color: CupertinoColors.white,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(
                      CupertinoIcons.exclamationmark_triangle,
                      color: CupertinoColors.systemRed,
                      size: 40,
                    ),
                  ),
                ),
              ),
              
              // Top Bar (Progress & User Info)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        CupertinoColors.black.withValues(alpha: 0.5),
                        CupertinoColors.black.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      // Progress Bar
                      LinearProgressIndicator(
                        value: _progressController.value,
                        backgroundColor: CupertinoColors.systemGrey.withValues(alpha: 0.5),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          CupertinoColors.white,
                        ),
                        minHeight: 2,
                      ),
                      const SizedBox(height: 12),
                      // User Info Row
                      Row(
                        children: [
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Icon(
                              CupertinoIcons.back,
                              color: CupertinoColors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Avatar placeholder
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: CupertinoColors.systemGrey,
                            ),
                            child: Center(
                              child: Text(
                                widget.senderName.isNotEmpty ? widget.senderName[0].toUpperCase() : '?',
                                style: const TextStyle(
                                  color: CupertinoColors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            widget.senderName,
                            style: const TextStyle(
                              color: CupertinoColors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Simple fallback widget to simulate Material's LinearProgressIndicator using flutter/widgets
class LinearProgressIndicator extends StatelessWidget {
  final double value;
  final Color backgroundColor;
  final Animation<Color> valueColor;
  final double minHeight;

  const LinearProgressIndicator({
    super.key,
    required this.value,
    required this.backgroundColor,
    required this.valueColor,
    required this.minHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: minHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(minHeight / 2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: valueColor.value,
            borderRadius: BorderRadius.circular(minHeight / 2),
          ),
        ),
      ),
    );
  }
}
