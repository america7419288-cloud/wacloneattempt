import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';

class StatusViewScreen extends StatefulWidget {
  final String url;
  final String senderName;
  final String? senderJid;
  final String type; // 'image', 'video', or 'text'
  final VoidCallback? onFinished;

  const StatusViewScreen({
    super.key,
    required this.url,
    required this.senderName,
    this.senderJid,
    this.type = 'image', // default for backwards compat
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
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  VideoPlayerController? _videoCtrl;
  bool _videoInitialized = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          widget.onFinished?.call();
          Navigator.of(context).pop();
        }
      });

    _replyFocusNode.addListener(() {
      if (!_replyFocusNode.hasFocus && mounted) {
        _progressController.forward();
      }
    });

    if (widget.type == 'video' && widget.url.isNotEmpty) {
      _videoCtrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
        ..initialize().then((_) {
          if (!mounted) return;
          _progressController.duration = _videoCtrl!.value.duration.inSeconds > 0
              ? _videoCtrl!.value.duration
              : const Duration(seconds: 30); // fallback if duration unknown
          setState(() => _videoInitialized = true);
          _videoCtrl!.play();
          _videoCtrl!.setLooping(false);
          _progressController.forward();
          _imageLoaded = true;
        });
    } else if (widget.type != 'video') {
      // For image/text, set 5 second default
      _progressController.duration = const Duration(seconds: 5);
      // Image stories start the timer in loadingBuilder, text starts immediately
      if (widget.type == 'text') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _progressController.forward();
          _imageLoaded = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    _replyController.dispose();
    _replyFocusNode.dispose();
    _videoCtrl?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _sendReply() {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.selectionClick();
    if (widget.senderJid != null && widget.senderJid!.isNotEmpty) {
      FirebaseFirestore.instance.collection('outbox').add({
        'to': widget.senderJid,
        'text': text,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
    _replyController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      child: GestureDetector(
        // Fix 12: Tap left to restart, tap right to skip forward
        onTapUp: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx > screenWidth / 2) {
            widget.onFinished?.call();
            Navigator.of(context).pop();
          } else {
            HapticFeedback.selectionClick();
            _progressController.reset();
            if (_imageLoaded) _progressController.forward();
          }
        },
        // Long press to pause/resume
        onLongPressStart: (_) => _progressController.stop(),
        onLongPressEnd: (_) => _progressController.forward(),
        child: SafeArea(
          child: Stack(
            children: [
              // Main Image
              Center(
                child: widget.type == 'video'
                  ? (_videoInitialized && _videoCtrl != null
                      ? AspectRatio(
                          aspectRatio: _videoCtrl!.value.aspectRatio,
                          child: VideoPlayer(_videoCtrl!),
                        )
                      : const CupertinoActivityIndicator(color: CupertinoColors.white))
                  : widget.type == 'text'
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            widget.url.isEmpty ? widget.senderName : widget.url,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: CupertinoColors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    : Image.network(
                        widget.url,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) {
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
                          Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
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

              // Fix 13: Reply input bar at bottom
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        CupertinoColors.black.withValues(alpha: 0.6),
                        CupertinoColors.black.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: CupertinoColors.white.withValues(alpha: 0.5),
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: CupertinoTextField(
                            controller: _replyController,
                            focusNode: _replyFocusNode,
                            placeholder: 'Reply to ${widget.senderName}...',
                            placeholderStyle: TextStyle(
                              color: CupertinoColors.white.withValues(alpha: 0.5),
                              fontSize: 15,
                            ),
                            style: const TextStyle(
                              color: CupertinoColors.white,
                              fontSize: 15,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _sendReply,
                        child: const Icon(
                          CupertinoIcons.arrow_right_circle_fill,
                          color: CupertinoColors.white,
                          size: 34,
                        ),
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
