import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:any_link_preview/any_link_preview.dart';

const Color _incomingBubbleColor = Color(0xFFE5E5EA);
const Color _outgoingBubbleColor = Color(0xFF34C759);

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

  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance
        .collection('contacts')
        .doc(widget.contactJid)
        .set({'unreadCount': 0}, SetOptions(merge: true));
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final jid = widget.contactJid;

    final msgPayload = <String, dynamic>{
      'chatId': jid,
      'text': text,
      'from': 'me',
      'isMe': true,
      'timestamp': FieldValue.serverTimestamp(),
    };
    if (_replyingTo != null) {
      msgPayload['replyTo'] = {
        'text': _replyingTo!['text'] ?? '',
        'author': _replyingTo!['senderName'] ?? _replyingTo!['from'] ?? '',
      };
    }
    FirebaseFirestore.instance.collection('messages').add(msgPayload);

    FirebaseFirestore.instance.collection('outbox').add({
      'to': jid,
      'text': text,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });

    _textController.clear();
    setState(() => _replyingTo = null);
  }

  void _setReply(Map<String, dynamic> data) {
    setState(() => _replyingTo = data);
  }

  void _showLongPressMenu(BuildContext ctx, Map<String, dynamic> data, String docId) {
    showCupertinoModalPopup(
      context: ctx,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () { Navigator.pop(ctx); _setReply(data); },
            child: const Text('Reply'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: data['text'] ?? ''));
            },
            child: const Text('Copy'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseFirestore.instance.collection('messages').doc(docId).delete();
            },
            child: const Text('Delete'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showReactionPicker(BuildContext ctx, Map<String, dynamic> data) {
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    showCupertinoModalPopup(
      context: ctx,
      builder: (_) => Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          color: CupertinoColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: emojis.map((emoji) {
              return GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  FirebaseFirestore.instance.collection('outbox_reactions').add({
                    'chatJid': widget.contactJid,
                    'msgKeyId': data['msgKeyId'] ?? '',
                    'emoji': emoji,
                    'fromMe': data['isMe'] ?? false,
                    'status': 'pending',
                  });
                },
                child: Text(emoji, style: const TextStyle(fontSize: 32)),
              );
            }).toList(),
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

  void _pickAndSendMedia() async {
    final picker = ImagePicker();
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              final file = await picker.pickImage(source: ImageSource.gallery);
              if (file != null) {
                // Placeholder: send image path as text for now
                FirebaseFirestore.instance.collection('messages').add({
                  'chatId': widget.contactJid,
                  'text': '📷 Image selected: ${file.name}',
                  'from': 'me',
                  'isMe': true,
                  'timestamp': FieldValue.serverTimestamp(),
                });
              }
            },
            child: const Text('Photo Library'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              final file = await picker.pickImage(source: ImageSource.camera);
              if (file != null) {
                FirebaseFirestore.instance.collection('messages').add({
                  'chatId': widget.contactJid,
                  'text': '📷 Photo taken: ${file.name}',
                  'from': 'me',
                  'isMe': true,
                  'timestamp': FieldValue.serverTimestamp(),
                });
              }
            },
            child: const Text('Camera'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              final file = await picker.pickVideo(source: ImageSource.gallery);
              if (file != null) {
                FirebaseFirestore.instance.collection('messages').add({
                  'chatId': widget.contactJid,
                  'text': '🎬 Video selected: ${file.name}',
                  'from': 'me',
                  'isMe': true,
                  'timestamp': FieldValue.serverTimestamp(),
                });
              }
            },
            child: const Text('Video'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
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
            Column(
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
                const Text(
                  'online',
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.systemGrey,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
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
      child: SafeArea(
        child: Column(
          children: [
            // Messages area
            Expanded(
              child: _buildMessageList(),
            ),
            // Input bar (with admin restriction)
            _buildRestrictedInputBar(),
          ],
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final isOutgoing = data['isMe'] == true;
            final timestamp = data['timestamp'] as Timestamp?;
            final timeStr = timestamp != null
                ? '${timestamp.toDate().hour.toString().padLeft(2, '0')}:${timestamp.toDate().minute.toString().padLeft(2, '0')}'
                : '';

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
            double _swipeOffset = 0;

            return Column(
              children: [
                ?dateHeader,
                StatefulBuilder(
                  builder: (context, setLocalState) {
                    return GestureDetector(
                      onHorizontalDragUpdate: (details) {
                        setLocalState(() {
                          _swipeOffset = (_swipeOffset + details.delta.dx).clamp(0.0, 80.0);
                        });
                      },
                      onHorizontalDragEnd: (_) {
                        if (_swipeOffset > 60) _setReply(data);
                        setLocalState(() => _swipeOffset = 0);
                      },
                      onLongPress: () => _showLongPressMenu(context, data, docId),
                      onDoubleTap: () => _showReactionPicker(context, data),
                      child: Transform.translate(
                        offset: Offset(_swipeOffset, 0),
                        child: _ChatBubble(
                          data: data,
                          time: timeStr,
                          isOutgoing: isOutgoing,
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildRestrictedInputBar() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('contacts')
          .doc(widget.contactJid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final isAdminOnly = data['onlyAdminsCanMessage'] == true;
          if (isAdminOnly) {
            return Container(
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
                  style: TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              ),
            );
          }
        }
        return _buildInputBar();
      },
    );
  }

  Widget _buildInputBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reply preview bar
        if (_replyingTo != null)
          Container(
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
                  width: 3,
                  height: 36,
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
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CupertinoColors.systemBlue),
                      ),
                      Text(
                        _replyingTo!['text'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
                      ),
                    ],
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Icon(CupertinoIcons.xmark_circle_fill, size: 20, color: CupertinoColors.systemGrey),
                  onPressed: () => setState(() => _replyingTo = null),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: CupertinoColors.systemBackground.resolveFrom(context),
            border: const Border(
              top: BorderSide(color: CupertinoColors.separator, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              // Camera icon -> media picker
              CupertinoButton(
                padding: const EdgeInsets.all(4),
                child: const Icon(
                  CupertinoIcons.camera_fill,
                  color: CupertinoColors.systemGrey,
                  size: 24,
                ),
                onPressed: _pickAndSendMedia,
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
              // Send button
              CupertinoButton(
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
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final String time;
  final bool isOutgoing;

  const _ChatBubble({
    required this.data,
    required this.time,
    required this.isOutgoing,
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
                  maxWidth: MediaQuery.of(context).size.width * 0.72,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: isOutgoing ? _outgoingBubbleColor : _incomingBubbleColor,
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
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Reply preview
                    if (replyTo != null) _buildReplyPreview(replyTo),
                    _buildContent(type),
                    const SizedBox(height: 3),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 11,
                        color: isOutgoing
                            ? CupertinoColors.white.withValues(alpha: 0.7)
                            : CupertinoColors.systemGrey,
                      ),
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
                      color: CupertinoColors.white,
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

  Widget _buildReplyPreview(Map<String, dynamic> replyTo) {
    final quotedText = replyTo['text'] as String? ?? '';
    final quotedAuthor = replyTo['author'] as String? ?? '';
    final displayAuthor = quotedAuthor.isNotEmpty
        ? quotedAuthor.split('@')[0]
        : 'Unknown';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayAuthor,
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
            quotedText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: isOutgoing
                  ? CupertinoColors.white.withValues(alpha: 0.7)
                  : CupertinoColors.systemGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(String? type) {
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
        return Text(
          data['text'] as String? ?? '',
          style: TextStyle(
            fontSize: 15.5,
            color:
                isOutgoing ? CupertinoColors.white : CupertinoColors.black,
          ),
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
            color: CupertinoColors.systemGrey5,
            borderRadius: BorderRadius.circular(12),
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
              launchUrl(Uri.parse(mediaUrl),
                  mode: LaunchMode.externalApplication);
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
class _AudioContent extends StatelessWidget {
  final String mediaUrl;
  final bool isOutgoing;

  const _AudioContent({
    required this.mediaUrl,
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
            CupertinoIcons.mic_fill,
            size: 22,
            color:
                isOutgoing ? CupertinoColors.white : CupertinoColors.systemBlue,
          ),
          const SizedBox(width: 8),
          // Waveform-style placeholder
          ...List.generate(12, (i) {
            final h = 4.0 + (i % 3 == 0 ? 10.0 : (i % 2 == 0 ? 6.0 : 14.0));
            return Container(
              width: 3,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: isOutgoing
                    ? CupertinoColors.white.withValues(alpha: 0.6)
                    : CupertinoColors.systemGrey3,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
          const SizedBox(width: 8),
          Text(
            'Voice note',
            style: TextStyle(
              fontSize: 13,
              color: isOutgoing
                  ? CupertinoColors.white.withValues(alpha: 0.8)
                  : CupertinoColors.systemGrey,
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
                    : CupertinoColors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
