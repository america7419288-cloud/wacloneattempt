import 'dart:ui' as ui;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator, AlwaysStoppedAnimation;
import 'contact_info_screen.dart';
import '../chat_wallpaper_widget.dart';
import 'status_screen.dart' show kOwnJid;

const _incomingBubbleColor = CupertinoDynamicColor.withBrightness(
  color: Color(0xFFE5E5EA),
  darkColor: Color(0xFF1C1C1E),
);
const _outgoingBubbleColor = CupertinoDynamicColor.withBrightness(
  color: Color(0xFF34C759),
  darkColor: Color(0xFF174F2A),
);

class ChatDetailScreen extends StatefulWidget {
  final String contactJid;
  final String contactName;
  final String avatarLetter;
  final String? profileUrl;

  const ChatDetailScreen({
    super.key,
    required this.contactJid,
    required this.contactName,
    required this.avatarLetter,
    this.profileUrl,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Map<String, dynamic>? _replyingTo;
  bool _showScrollToBottom = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance
        .collection('contacts')
        .doc(widget.contactJid)
        .set({'unreadCount': 0}, SetOptions(merge: true));
    _scrollController.addListener(() {
      final show = _scrollController.offset > 200;
      if (show != _showScrollToBottom) {
        setState(() => _showScrollToBottom = show);
      }
    });
    _textController.addListener(() {
      final has = _textController.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final jid = widget.contactJid;
    final localId = '${DateTime.now().millisecondsSinceEpoch}_${jid.hashCode}';

    final msgPayload = <String, dynamic>{
      'chatId': jid,
      'text': text,
      'from': 'me',
      'isMe': true,
      'localId': localId,
      'deliveryStatus': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    };
    if (_replyingTo != null) {
      msgPayload['replyTo'] = {
        'text': _replyingTo!['text'] ?? '',
        'author': _replyingTo!['senderName'] ?? _replyingTo!['from'] ?? '',
        if (_replyingTo!['mediaUrl'] != null) 'mediaUrl': _replyingTo!['mediaUrl'],
      };
    }
    FirebaseFirestore.instance.collection('messages').add(msgPayload);

    final outboxPayload = <String, dynamic>{
      'to': jid,
      'text': text,
      'localId': localId,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    };
    if (_replyingTo != null) {
      outboxPayload['replyTo'] = {
        'msgKeyId': _replyingTo!['msgKeyId'] ?? '',
      };
    }
    FirebaseFirestore.instance.collection('outbox').add(outboxPayload);

    _textController.clear();
    setState(() => _replyingTo = null);
  }

  void _setReply(Map<String, dynamic> data) {
    setState(() => _replyingTo = data);
  }

  Color _senderColor(String name) {
    const colors = [
      Color(0xFFE91E63), Color(0xFF9C27B0), Color(0xFF3F51B5),
      Color(0xFF2196F3), Color(0xFF009688), Color(0xFF4CAF50),
      Color(0xFFFF5722), Color(0xFF795548),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  void _showLongPressMenu(BuildContext ctx, Map<String, dynamic> data, String docId) {
    showCupertinoDialog(
      context: ctx,
      builder: (dialogCtx) => CupertinoAlertDialog(
        title: const Text('Message Options'),
        actions: [
          CupertinoDialogAction(
            onPressed: () { Navigator.pop(dialogCtx); _setReply(data); },
            child: const Text('Reply'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              Navigator.pop(dialogCtx);
              Clipboard.setData(ClipboardData(text: data['text'] ?? ''));
            },
            child: const Text('Copy'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await FirebaseFirestore.instance.collection('messages').doc(docId).delete();
            },
            child: const Text('Delete'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showReactionPicker(BuildContext ctx, Map<String, dynamic> data) {
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    showCupertinoModalPopup(
      context: ctx,
      builder: (modalCtx) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.elasticOut,
        builder: (context, value, child) => Transform.scale(
          scale: value,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          decoration: BoxDecoration(
            color: CupertinoColors.systemBackground.resolveFrom(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [BoxShadow(color: CupertinoColors.black.withValues(alpha: 0.15), blurRadius: 20)],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: emojis.map((emoji) {
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.pop(modalCtx);
                        FirebaseFirestore.instance.collection('outbox_reactions').add({
                          'chatJid': widget.contactJid,
                          'msgKeyId': data['msgKeyId'] ?? '',
                          'emoji': emoji,
                          'fromMe': data['isMe'] ?? false,
                          'status': 'pending',
                        });
                      },
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.5, end: 1.0),
                        duration: Duration(milliseconds: 300 + emojis.indexOf(emoji) * 50),
                        curve: Curves.elasticOut,
                        builder: (_, v, child) => Transform.scale(scale: v, child: child),
                        child: Text(emoji, style: const TextStyle(fontSize: 36)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openProfileViewer() {
    if (widget.profileUrl == null || widget.profileUrl!.isEmpty) return;
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => _ProfileViewerPage(
          imageUrl: widget.profileUrl!,
          name: widget.contactName,
        ),
      ),
    );
  }

  Future<void> _uploadAndSendMedia(XFile file, String type) async {
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const CupertinoAlertDialog(
        content: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoActivityIndicator(radius: 14),
              SizedBox(height: 12),
              Text('Uploading media...'),
            ],
          ),
        ),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 100)); // Ensure dialog route pushes

    try {
      final url = Uri.parse("https://api.cloudinary.com/v1_1/druwafmub/${type == 'video' ? 'video' : 'image'}/upload");
      final request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = 'whatsappClone'
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final response = await request.send();
      if (response.statusCode != 200) {
        throw Exception('Upload failed: HTTP ${response.statusCode}');
      }

      final responseData = await response.stream.bytesToString();
      final jsonResponse = jsonDecode(responseData);
      final String? secureUrl = jsonResponse['secure_url'];

      if (secureUrl == null || secureUrl.isEmpty) {
        throw Exception('No URL returned from Cloudinary');
      }

      final localId = '${DateTime.now().millisecondsSinceEpoch}_${widget.contactJid.hashCode}';

      await FirebaseFirestore.instance.collection('messages').add({
        'chatId': widget.contactJid,
        'type': type,
        'mediaUrl': secureUrl,
        'text': '',
        'from': 'me',
        'isMe': true,
        'localId': localId,
        'deliveryStatus': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      final outboxPayload = <String, dynamic>{
        'to': widget.contactJid,
        'type': type,
        'url': secureUrl,
        'status': 'pending',
        'localId': localId,
        'timestamp': FieldValue.serverTimestamp(),
      };

      if (_replyingTo != null) {
        outboxPayload['replyTo'] = {
          'msgKeyId': _replyingTo!['msgKeyId'] ?? '',
        };
        setState(() => _replyingTo = null);
      }

      await FirebaseFirestore.instance.collection('outbox_media').add(outboxPayload);

      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (dialogCtx) => CupertinoAlertDialog(
            title: const Text('Upload Failed'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(dialogCtx),
              ),
            ],
          ),
        );
      }
    }
  }

  void _pickAndSendMedia() async {
    final picker = ImagePicker();
    showCupertinoDialog(
      context: context,
      builder: (dialogCtx) => CupertinoAlertDialog(
        title: const Text('Attach Media'),
        actions: [
          CupertinoDialogAction(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final file = await picker.pickImage(source: ImageSource.gallery);
              if (file != null) _uploadAndSendMedia(file, 'image');
            },
            child: const Text('Photo Library'),
          ),
          CupertinoDialogAction(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final file = await picker.pickImage(source: ImageSource.camera);
              if (file != null) _uploadAndSendMedia(file, 'image');
            },
            child: const Text('Camera'),
          ),
          CupertinoDialogAction(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final file = await picker.pickVideo(source: ImageSource.gallery);
              if (file != null) _uploadAndSendMedia(file, 'video');
            },
            child: const Text('Video'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.systemBackground.resolveFrom(context).withValues(alpha: 0.8),
        border: Border(bottom: BorderSide(color: CupertinoColors.separator.resolveFrom(context), width: 0.33)),
        transitionBetweenRoutes: false,
        middle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: GestureDetector(
                onTap: _openProfileViewer,
                child: (widget.profileUrl != null &&
                        widget.profileUrl!.isNotEmpty)
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: widget.profileUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => _buildFallbackAvatar(),
                          errorWidget: (context, url, error) =>
                              _buildFallbackAvatar(),
                        ),
                      )
                    : _buildFallbackAvatar(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (_) => ContactInfoScreen(contactJid: widget.contactJid),
                  ),
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.contactName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  _PresenceSubtitle(contactJid: widget.contactJid, ownJid: kOwnJid),
                ],
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Icon(CupertinoIcons.video_camera,
                  color: CupertinoColors.systemBlue),
              onPressed: () {},
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Icon(CupertinoIcons.phone,
                  color: CupertinoColors.systemBlue),
              onPressed: () {},
            ),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Animated wallpaper background
          const Positioned.fill(child: ChatWallpaperBackground()),
          SafeArea(
            child: Column(
              children: [
                // Messages area
                Expanded(
                  child: Stack(
                    children: [
                      _buildMessageList(),
                  if (_showScrollToBottom)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          _scrollController.animateTo(
                            0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemBackground.resolveFrom(context),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: CupertinoColors.systemGrey.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            CupertinoIcons.arrow_down_circle_fill,
                            color: CupertinoColors.systemGrey,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Input bar (with admin restriction + typing indicator)
              _buildBottomBar(),
            ],
          ),
        ),
        ],
      ),
    );
  }

  Widget _buildFallbackAvatar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            CupertinoColors.systemGrey.withValues(alpha: 0.4),
            CupertinoColors.systemGrey2.withValues(alpha: 0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          widget.avatarLetter,
          style: const TextStyle(
            color: CupertinoColors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    // Query messages where chatId matches this contact's JID
    // chatId is set by index.js for both incoming and outgoing messages
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('messages')
          .where('chatId', isEqualTo: widget.contactJid)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(CupertinoIcons.exclamationmark_triangle,
                      size: 40, color: CupertinoColors.systemRed),
                  const SizedBox(height: 12),
                  Text(
                    'Error:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13, color: CupertinoColors.systemGrey),
                  ),
                ],
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CupertinoActivityIndicator());
        }

        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.chat_bubble_2,
                  size: 64,
                  color: CupertinoColors.systemGrey.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'No messages yet',
                  style: TextStyle(
                    fontSize: 16,
                    color: CupertinoColors.systemGrey.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Send a message to start chatting',
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.systemGrey.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final isOutgoing = data['isMe'] == true;
            final timestamp = data['timestamp'] as Timestamp?;
            // Fix 6: Relative time display
            String timeStr = '';
            if (timestamp != null) {
              final dt = timestamp.toDate();
              final now = DateTime.now();
              final hhmm = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
              if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
                timeStr = hhmm;
              } else if (dt.year == now.year && dt.month == now.month && dt.day == now.day - 1) {
                timeStr = 'Yesterday $hhmm';
              } else if (now.difference(dt).inDays < 7) {
                const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                timeStr = '${days[dt.weekday - 1]} $hhmm';
              } else {
                timeStr = '${dt.day}/${dt.month} $hhmm';
              }
            }

            // --- DATE HEADER LOGIC ---
            Widget? dateHeader;
            if (timestamp != null) {
              final currentDate = timestamp.toDate();
              DateTime? prevDate;
              if (index < docs.length - 1) {
                final prevTs = (docs[index + 1].data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                prevDate = prevTs?.toDate();
              }
              final showHeader = prevDate == null ||
                  currentDate.year != prevDate.year ||
                  currentDate.month != prevDate.month ||
                  currentDate.day != prevDate.day;
              if (showHeader) {
                dateHeader = _DateChip(date: currentDate);
              }
            }

            final docId = docs[index].id;
            final isGroup = widget.contactJid.endsWith('@g.us');
            final senderName = data['senderName'] as String? ?? '';
            final isNewest = index == 0;

            return isNewest
                ? TweenAnimationBuilder<Offset>(
                    key: ValueKey('slide_$docId'),
                    tween: Tween<Offset>(
                        begin: const Offset(0.0, 0.5), end: Offset.zero),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    builder: (_, translation, child) =>
                        FractionalTranslation(translation: translation, child: child!),
                    child: _buildMessageItem(context, data, docId, isOutgoing, isGroup, senderName, dateHeader, timeStr),
                  )
                : _buildMessageItem(context, data, docId, isOutgoing, isGroup, senderName, dateHeader, timeStr);
          },
        );
      },
    );
  }

  Widget _buildMessageItem(BuildContext context, Map<String, dynamic> data, String docId, bool isOutgoing, bool isGroup, String senderName, Widget? dateHeader, String timeStr) {
    return Column(
      children: [
        if (dateHeader != null) dateHeader,
        if (!isOutgoing && isGroup && senderName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 14, bottom: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                senderName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _senderColor(senderName),
                ),
              ),
            ),
          ),
        _SwipableBubbleRow(
          data: data,
          time: timeStr,
          isOutgoing: isOutgoing,
          docId: docId,
          onReply: _setReply,
          onLongPress: () {
            if (data['deleted'] == true) return;
            HapticFeedback.mediumImpact();
            _showLongPressMenu(context, data, docId);
          },
          onDoubleTap: () {
            if (data['deleted'] == true) return;
            HapticFeedback.selectionClick();
            _showReactionPicker(context, data);
          },
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('contacts')
          .doc(widget.contactJid)
          .snapshots(),
      builder: (context, snapshot) {
        bool isAdminOnly = false;
        bool isTyping = false;
        if (snapshot.hasData && snapshot.data!.exists) {
          final d = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          isAdminOnly = d['onlyAdminsCanMessage'] == true;
          isTyping = d['presence'] == 'composing';
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isTyping)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(left: 12, bottom: 4, top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: CupertinoDynamicColor.resolve(
                      const CupertinoDynamicColor.withBrightness(
                        color: Color(0xFFE5E5EA),
                        darkColor: Color(0xFF2C2C2E),
                      ),
                      context,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const _TypingIndicator(),
                ),
              ),
            if (isAdminOnly)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemBackground.resolveFrom(context),
                  border: const Border(
                    top: BorderSide(color: CupertinoColors.separator, width: 0.5),
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Only admins can send messages',
                    style: TextStyle(fontSize: 14, color: CupertinoColors.systemGrey),
                  ),
                ),
              )
            else
              _buildInputBar(),
          ],
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1F: Animated reply banner
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: _replyingTo != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey6.resolveFrom(context),
                  border: const Border(
                    top: BorderSide(color: CupertinoColors.separator, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 48,
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemBlue,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _replyingTo!['senderName'] ?? _replyingTo!['from'] ?? '',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: CupertinoColors.systemBlue),
                          ),
                          Text(
                            _replyingTo!['text']?.toString().isNotEmpty == true ? _replyingTo!['text'] : 'Photo',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, color: CupertinoColors.systemGrey),
                          ),
                        ],
                      ),
                    ),
                    if (_replyingTo!['mediaUrl'] != null && _replyingTo!['mediaUrl'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            imageUrl: _replyingTo!['mediaUrl'],
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: const Icon(CupertinoIcons.xmark_circle_fill, size: 22, color: CupertinoColors.systemGrey),
                      onPressed: () => setState(() => _replyingTo = null),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(),
        ),
        ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: CupertinoColors.systemBackground.resolveFrom(context).withValues(alpha: 0.88),
            border: const Border(
              top: BorderSide(color: CupertinoColors.separator, width: 0.33),
            ),
          ),
          child: Row(
            children: [
              // Attachment icon -> action sheet (Fix 7)
              CupertinoButton(
                padding: const EdgeInsets.all(4),
                child: const Icon(
                  CupertinoIcons.paperclip,
                  color: CupertinoColors.systemGrey,
                  size: 24,
                ),
                onPressed: _pickAndSendMedia,
              ),
              // Emoji button (Fix 4)
              CupertinoButton(
                padding: const EdgeInsets.all(4),
                child: const Icon(
                  CupertinoIcons.smiley,
                  color: CupertinoColors.systemGrey,
                  size: 24,
                ),
                onPressed: () {},
              ),
              // Text field
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey6.resolveFrom(context),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: CupertinoTextField(
                    controller: _textController,
                    placeholder: 'Message',
                    maxLines: null,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: null,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Dynamic send/mic button with elastic spring (1E)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) {
                  return ScaleTransition(
                    scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
                    child: FadeTransition(opacity: anim, child: child),
                  );
                },
                child: _hasText
                    ? CupertinoButton(
                        key: const ValueKey('send'),
                        padding: const EdgeInsets.all(4),
                        onPressed: _sendMessage,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: CupertinoColors.systemBlue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CupertinoIcons.arrow_up,
                            color: CupertinoColors.white,
                            size: 20,
                          ),
                        ),
                      )
                    : CupertinoButton(
                        key: const ValueKey('mic'),
                        padding: const EdgeInsets.all(4),
                        onPressed: () {},
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: CupertinoColors.systemBlue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CupertinoIcons.mic,
                            color: CupertinoColors.white,
                            size: 20,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        ), // BackdropFilter
        ), // ClipRect
      ],
    );
  }
}

// --- SWIPABLE BUBBLE ROW ---
class _SwipableBubbleRow extends StatefulWidget {
  final Map<String, dynamic> data;
  final String time;
  final bool isOutgoing;
  final String docId;
  final void Function(Map<String, dynamic>) onReply;
  final VoidCallback onLongPress;
  final VoidCallback onDoubleTap;

  const _SwipableBubbleRow({
    required this.data,
    required this.time,
    required this.isOutgoing,
    required this.docId,
    required this.onReply,
    required this.onLongPress,
    required this.onDoubleTap,
  });

  @override
  State<_SwipableBubbleRow> createState() => _SwipableBubbleRowState();
}

class _SwipableBubbleRowState extends State<_SwipableBubbleRow> {
  double swipeOffset = 0;
  bool didTriggerHaptic = false;
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.97),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onHorizontalDragUpdate: (details) {
        final delta = widget.isOutgoing ? -details.delta.dx : details.delta.dx;
        if (delta > 0 || swipeOffset > 0) {
          setState(() {
            swipeOffset = (swipeOffset + delta).clamp(0.0, 70.0);
            if (swipeOffset > 40 && !didTriggerHaptic) {
              didTriggerHaptic = true;
              HapticFeedback.mediumImpact();
            } else if (swipeOffset <= 40) {
              didTriggerHaptic = false;
            }
          });
        }
      },
      onHorizontalDragEnd: (_) async {
        if (swipeOffset > 40) widget.onReply(widget.data);
        while (swipeOffset > 0) {
          await Future.delayed(const Duration(milliseconds: 16));
          if (!mounted) break;
          setState(() {
            swipeOffset = (swipeOffset - 15).clamp(0.0, 70.0);
          });
        }
        if (mounted) {
          setState(() {
            swipeOffset = 0;
            didTriggerHaptic = false;
          });
        }
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        widget.onLongPress();
      },
      onDoubleTap: () {
        HapticFeedback.selectionClick();
        widget.onDoubleTap();
      },
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: SizedBox(
          width: double.infinity,
          child: Stack(
            alignment: widget.isOutgoing ? Alignment.centerLeft : Alignment.centerRight,
            children: [
              if (swipeOffset > 10)
                Opacity(
                  opacity: (swipeOffset / 60).clamp(0.0, 1.0),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Icon(CupertinoIcons.reply, color: CupertinoColors.systemGrey, size: 22),
                  ),
                ),
              Align(
                alignment: widget.isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
                child: Transform.translate(
                  offset: Offset(widget.isOutgoing ? -swipeOffset : swipeOffset, 0),
                  child: _ChatBubble(
                    data: widget.data,
                    time: widget.time,
                    isOutgoing: widget.isOutgoing,
                    docId: widget.docId,
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

class _ChatBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final String time;
  final bool isOutgoing;
  final String docId;

  const _ChatBubble({
    required this.data,
    required this.time,
    required this.isOutgoing,
    required this.docId,
  });

  @override
  Widget build(BuildContext context) {
    final type = data['type'] as String?;
    final replyTo = data['replyTo'] as Map<String, dynamic>?;
    final reactions = data['reactions'] as List<dynamic>?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
            isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(isOutgoing ? _outgoingBubbleColor : _incomingBubbleColor, context),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: isOutgoing
                        ? const Radius.circular(16)
                        : const Radius.circular(4),
                    bottomRight: isOutgoing
                        ? const Radius.circular(4)
                        : const Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: CupertinoColors.black.withValues(alpha: isOutgoing ? 0.10 : 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    // Reply preview
                    if (replyTo != null && data['deleted'] != true) _buildReplyPreview(context, replyTo),
                    if (data['deleted'] == true)
                      // Deleted message styling
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'This message was deleted',
                            style: TextStyle(
                              fontSize: 15,
                              fontStyle: FontStyle.italic,
                              color: isOutgoing
                                  ? CupertinoColors.white.withValues(alpha: 0.7)
                                  : CupertinoColors.systemGrey,
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8, top: 4),
                              child: Text(
                                time,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isOutgoing
                                      ? CupertinoColors.white.withValues(alpha: 0.7)
                                      : CupertinoColors.systemGrey,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildContent(context, type),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                time,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isOutgoing
                                      ? CupertinoColors.white.withValues(alpha: 0.7)
                                      : CupertinoColors.systemGrey,
                                ),
                              ),
                              if (isOutgoing) ...[
                                const SizedBox(width: 3),
                                _buildDeliveryTicks(),
                              ],
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              // Reaction emojis
              if (reactions != null && reactions.isNotEmpty)
                Positioned(
                  bottom: -8,
                  right: isOutgoing ? 4 : null,
                  left: isOutgoing ? null : 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemBackground.resolveFrom(context),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: CupertinoColors.systemGrey.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: reactions.take(5).map((r) {
                        final emoji = (r is Map) ? (r['emoji'] ?? '') : '';
                        return Text(emoji, style: const TextStyle(fontSize: 14));
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview(BuildContext context, Map<String, dynamic> replyTo) {
    final quotedText = replyTo['text'] as String? ?? '';
    final quotedAuthor = replyTo['author'] as String? ?? '';
    // Show 'You' for own messages, otherwise use the name as-is (now resolved by bridge)
    final isOwnNumber = RegExp(r'^\d+$').hasMatch(quotedAuthor);
    final displayAuthor = quotedAuthor.isEmpty
        ? 'Unknown'
        : isOwnNumber
            ? 'You'
            : quotedAuthor;
    final mediaUrl = replyTo['mediaUrl'] as String?;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 60),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isOutgoing
              ? CupertinoColors.white.withValues(alpha: 0.15)
              : CupertinoColors.systemGrey5,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: isOutgoing
                  ? CupertinoColors.white.withValues(alpha: 0.6)
                  : CupertinoColors.systemBlue,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayAuthor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isOutgoing
                          ? CupertinoColors.white.withValues(alpha: 0.9)
                          : CupertinoColors.systemBlue,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    quotedText.isNotEmpty ? quotedText : 'Photo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: isOutgoing
                          ? CupertinoColors.white.withValues(alpha: 0.7)
                          : CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ],
              ),
            ),
            if (mediaUrl != null && mediaUrl.isNotEmpty) ...[
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: mediaUrl,
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryTicks() {
    final status = data['deliveryStatus'] as String? ?? 'pending';
    switch (status) {
      case 'read':
        return Text(
          '✓✓',
          style: TextStyle(
            fontSize: 11,
            color: CupertinoColors.systemBlue,
            fontWeight: FontWeight.w600,
          ),
        );
      case 'played':
        return Text(
          '✓✓',
          style: TextStyle(
            fontSize: 11,
            color: CupertinoColors.systemBlue,
            fontWeight: FontWeight.w600,
          ),
        );
      case 'delivered':
        return Text(
          '✓✓',
          style: TextStyle(
            fontSize: 11,
            color: CupertinoColors.white.withValues(alpha: 0.7),
          ),
        );
      case 'sent':
        return Text(
          '✓',
          style: TextStyle(
            fontSize: 11,
            color: CupertinoColors.white.withValues(alpha: 0.7),
          ),
        );
      case 'error':
      return GestureDetector(
        onTap: () {
          // Retry
          if (data['type'] == 'image' || data['type'] == 'video' || data['type'] == 'file' || data['type'] == 'audio') {
            FirebaseFirestore.instance.collection('outbox_media').where('localId', isEqualTo: data['localId']).limit(1).get().then((snap) {
              if (snap.docs.isNotEmpty) snap.docs.first.reference.update({'status': 'pending'});
            });
          } else {
            FirebaseFirestore.instance.collection('outbox').where('localId', isEqualTo: data['localId']).limit(1).get().then((snap) {
              if (snap.docs.isNotEmpty) snap.docs.first.reference.update({'status': 'pending'});
            });
          }
          FirebaseFirestore.instance.collection('messages').doc(docId).update({'deliveryStatus': 'pending'});
        },
        child: const Icon(CupertinoIcons.exclamationmark_circle, color: CupertinoColors.systemRed, size: 14),
      );
    default: // pending
      return Text(
        '✓',
        style: TextStyle(
          fontSize: 11,
          color: CupertinoColors.white.withValues(alpha: 0.7),
        ),
      );
    }
  }

  Widget _buildContent(BuildContext context, String? type) {
    // If it's a skipped file or empty URL for a media type, show a placeholder
    final bool isSkipped = type == 'large_file_skipped';
    final String url = data['mediaUrl'] as String? ?? '';
    final bool isMedia = ['image', 'video', 'audio', 'file'].contains(type);
    
    if (isSkipped || (isMedia && url.isEmpty)) {
      return _MissingMedia(
        text: isSkipped ? 'Media Unavailable (> 10MB)' : 'Media Not Uploaded',
        caption: data['text'] as String? ?? '',
        isOutgoing: isOutgoing,
      );
    }

    switch (type) {
      case 'image':
        return _ImageContent(
          mediaUrl: url,
          caption: data['text'] as String? ?? '',
          isOutgoing: isOutgoing,
        );
      case 'video':
        return _VideoPreview(
          mediaUrl: url,
          caption: data['text'] as String? ?? '',
          isOutgoing: isOutgoing,
        );
      case 'audio':
        return _AudioContent(
          mediaUrl: url,
          isOutgoing: isOutgoing,
        );
      case 'file':
        return _FileContent(
          mediaUrl: url,
          fileName: data['fileName'] as String? ?? 'Document',
          isOutgoing: isOutgoing,
        );
      default:
        final text = data['text'] as String? ?? '';
        final linkPreview = data['linkPreview'] as Map<String, dynamic>?;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                fontSize: 15.5,
                color:
                    isOutgoing ? CupertinoColors.white : CupertinoColors.label.resolveFrom(context),
              ),
            ),
            if (linkPreview != null) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () {
                  final url = linkPreview['url'] as String? ?? '';
                  if (url.isNotEmpty) {
                    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isOutgoing
                        ? CupertinoColors.white.withValues(alpha: 0.15)
                        : CupertinoColors.systemGrey6,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((linkPreview['image'] as String? ?? '').isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: CachedNetworkImage(
                            imageUrl: linkPreview['image'],
                            height: 100,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      if ((linkPreview['title'] as String? ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          linkPreview['title'],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isOutgoing ? CupertinoColors.white : CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                      ],
                      if ((linkPreview['description'] as String? ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          linkPreview['description'],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isOutgoing
                                ? CupertinoColors.white.withValues(alpha: 0.7)
                                : CupertinoColors.systemGrey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
    }
  }
}

// --- DATE CHIP ---
class _DateChip extends StatelessWidget {
  final DateTime date;

  const _DateChip({required this.date});

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(d.year, d.month, d.day);
    final diff = today.difference(dateOnly).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';

    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: CupertinoColors.systemBackground.resolveFrom(context).withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.33,
            ),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            _formatDate(date),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: CupertinoColors.systemGrey,
            ),
          ),
        ),
      ),
    );
  }
}

// --- MISSING FILES ---
class _MissingMedia extends StatelessWidget {
  final String text;
  final String caption;
  final bool isOutgoing;

  const _MissingMedia({
    required this.text,
    required this.caption,
    required this.isOutgoing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 200,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: isOutgoing 
                ? CupertinoColors.white.withValues(alpha: 0.2)
                : CupertinoColors.systemGrey5,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isOutgoing 
                  ? CupertinoColors.white.withValues(alpha: 0.4)
                  : CupertinoColors.systemGrey4,
              width: 0.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                CupertinoIcons.exclamationmark_triangle,
                size: 32,
                color: isOutgoing 
                    ? CupertinoColors.white.withValues(alpha: 0.8)
                    : CupertinoColors.systemGrey,
              ),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isOutgoing 
                      ? CupertinoColors.white.withValues(alpha: 0.9)
                      : CupertinoColors.systemGrey,
                ),
              ),
            ],
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            caption,
            style: TextStyle(
              fontSize: 15,
              color:
                  isOutgoing ? CupertinoColors.white : CupertinoColors.black,
            ),
          ),
        ],
      ],
    );
  }
}

// --- IMAGE ---
class _ImageContent extends StatelessWidget {
  final String mediaUrl;
  final String caption;
  final bool isOutgoing;

  const _ImageContent({
    required this.mediaUrl,
    required this.caption,
    required this.isOutgoing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            if (mediaUrl.isNotEmpty) {
              Navigator.of(context).push(
                CupertinoPageRoute(
                  builder: (_) => _MediaViewerPage(imageUrl: mediaUrl),
                ),
              );
            }
          },
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: mediaUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: mediaUrl,
                        placeholder: (_, __) => const SizedBox(
                          height: 150,
                          child: Center(child: CupertinoActivityIndicator()),
                        ),
                        errorWidget: (_, __, ___) => const SizedBox(
                          height: 150,
                          child: Center(
                            child: Icon(CupertinoIcons.photo,
                                size: 40, color: CupertinoColors.systemGrey),
                          ),
                        ),
                        fit: BoxFit.cover,
                      )
                    : const SizedBox(
                        height: 150,
                        child: Center(
                          child: Icon(CupertinoIcons.photo,
                              size: 40, color: CupertinoColors.systemGrey),
                        ),
                      ),
              ),
              // Fix 9: Fullscreen icon overlay
              if (mediaUrl.isNotEmpty)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: CupertinoColors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      CupertinoIcons.fullscreen,
                      size: 14,
                      color: CupertinoColors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            caption,
            style: TextStyle(
              fontSize: 15,
              color:
                  isOutgoing ? CupertinoColors.white : CupertinoColors.black,
            ),
          ),
        ],
      ],
    );
  }
}

// --- VIDEO PREVIEW ---
class _VideoPreview extends StatelessWidget {
  final String mediaUrl;
  final String caption;
  final bool isOutgoing;

  const _VideoPreview({
    required this.mediaUrl,
    required this.caption,
    required this.isOutgoing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            if (mediaUrl.isNotEmpty) {
              Navigator.of(context).push(
                CupertinoPageRoute(
                  builder: (_) => _VideoPlayerPage(videoUrl: mediaUrl),
                ),
              );
            }
          },
          child: Container(
            height: 180,
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey5,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Icon(
                CupertinoIcons.play_circle_fill,
                size: 52,
                color: CupertinoColors.white,
              ),
            ),
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            caption,
            style: TextStyle(
              fontSize: 15,
              color:
                  isOutgoing ? CupertinoColors.white : CupertinoColors.black,
            ),
          ),
        ],
      ],
    );
  }
}

// --- AUDIO / VOICE NOTE ---
class _AudioContent extends StatefulWidget {
  final String mediaUrl;
  final bool isOutgoing;

  const _AudioContent({required this.mediaUrl, required this.isOutgoing});

  @override
  State<_AudioContent> createState() => _AudioContentState();
}

class _AudioContentState extends State<_AudioContent> {
  AudioPlayer? _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player!.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player!.durationStream.listen((dur) {
      if (mounted) setState(() => _duration = dur ?? Duration.zero);
    });
    _player!.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
    });
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              if (_isPlaying) {
                await _player!.pause();
              } else {
                if (_player!.processingState == ProcessingState.idle) {
                  await _player!.setUrl(widget.mediaUrl);
                }
                await _player!.play();
              }
            },
            child: Icon(
              _isPlaying ? CupertinoIcons.pause_circle_fill : CupertinoIcons.play_circle_fill,
              size: 36,
              color: widget.isOutgoing ? CupertinoColors.white : CupertinoColors.systemBlue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: (widget.isOutgoing ? CupertinoColors.white : CupertinoColors.systemGrey3).withValues(alpha: 0.4),
                    valueColor: AlwaysStoppedAnimation(
                      widget.isOutgoing ? CupertinoColors.white : CupertinoColors.systemBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_fmt(_position)} / ${_fmt(_duration)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.isOutgoing
                        ? CupertinoColors.white.withValues(alpha: 0.7)
                        : CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- FILE / DOCUMENT ---
class _FileContent extends StatelessWidget {
  final String mediaUrl;
  final String fileName;
  final bool isOutgoing;

  const _FileContent({
    required this.mediaUrl,
    required this.fileName,
    required this.isOutgoing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (mediaUrl.isNotEmpty) {
          launchUrl(Uri.parse(mediaUrl),
              mode: LaunchMode.externalApplication);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.doc_fill,
            size: 28,
            color:
                isOutgoing ? CupertinoColors.white : CupertinoColors.systemBlue,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isOutgoing
                    ? CupertinoColors.white
                    : CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- PROFILE VIEWER ---
class _ProfileViewerPage extends StatelessWidget {
  final String imageUrl;
  final String name;

  const _ProfileViewerPage({required this.imageUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(name),
        backgroundColor: CupertinoColors.black,
      ),
      child: Container(
        color: CupertinoColors.black,
        child: PhotoView(
          imageProvider: CachedNetworkImageProvider(imageUrl),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
        ),
      ),
    );
  }
}

// --- FULL SCREEN IMAGE VIEWER ---
class _MediaViewerPage extends StatelessWidget {
  final String imageUrl;

  const _MediaViewerPage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        backgroundColor: CupertinoColors.black,
      ),
      child: Container(
        color: CupertinoColors.black,
        child: PhotoView(
          imageProvider: CachedNetworkImageProvider(imageUrl),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
        ),
      ),
    );
  }
}

// --- VIDEO PLAYER PAGE ---
class _VideoPlayerPage extends StatefulWidget {
  final String videoUrl;

  const _VideoPlayerPage({required this.videoUrl});

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        setState(() => _initialized = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        backgroundColor: CupertinoColors.black,
      ),
      child: Container(
        color: CupertinoColors.black,
        child: Center(
          child: _initialized
              ? AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_controller),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _controller.value.isPlaying
                                ? _controller.pause()
                                : _controller.play();
                          });
                        },
                        child: AnimatedOpacity(
                          opacity: _controller.value.isPlaying ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(
                            CupertinoIcons.play_circle_fill,
                            size: 64,
                            color: CupertinoColors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const CupertinoActivityIndicator(),
        ),
      ),
    );
  }
}

// --- TYPING INDICATOR ---
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) => AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    ));
    _animations = _controllers.map((c) => Tween(begin: 0.0, end: -6.0)
        .animate(CurvedAnimation(parent: c, curve: Curves.easeInOut))).toList();

    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) => AnimatedBuilder(
        animation: _animations[i],
        builder: (_, __) => Transform.translate(
          offset: Offset(0, _animations[i].value),
          child: Container(
            width: 6, height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: const BoxDecoration(
              color: Color(0xFF8E8E93),
              shape: BoxShape.circle,
            ),
          ),
        ),
      )),
    );
  }
}

// --- CHAT BACKGROUND PAINTER ---
class _ChatBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: 0.03)
      ..style = PaintingStyle.fill;
    const spacing = 24.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PresenceSubtitle extends StatelessWidget {
  final String contactJid;
  final String ownJid;

  const _PresenceSubtitle({required this.contactJid, required this.ownJid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('contacts')
          .doc(contactJid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final presence = data['presence'] as String? ?? 'unavailable';
        final typingSource = data['typingSource'] as String?;
        final isTyping = presence == 'composing' && typingSource == ownJid;
        final isRecording =
            presence == 'recording' && typingSource == ownJid;

        String subtitleText = '';
        if (isTyping) {
          subtitleText = 'typing...';
        } else if (isRecording) {
          subtitleText = 'recording audio...';
        } else if (presence == 'available') {
          subtitleText = 'online';
        }

        if (subtitleText.isEmpty) {
          return const SizedBox.shrink();
        }

        return Text(
          subtitleText,
          style: TextStyle(
            fontSize: 12,
            color: (isTyping || isRecording)
                ? CupertinoColors.systemBlue
                : CupertinoColors.systemGrey,
            fontWeight: (isTyping || isRecording)
                ? FontWeight.w500
                : FontWeight.normal,
          ),
        );
      },
    );
  }
}
