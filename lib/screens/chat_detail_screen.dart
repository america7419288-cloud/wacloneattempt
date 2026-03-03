import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/physics.dart';
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
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart' show Material;
import 'contact_info_screen.dart';
import '../chat_wallpaper_widget.dart';
import 'status_screen.dart' show kOwnJid;

// ─────────────────────────────────────────────
//  BUBBLE COLORS  (Telegram iOS exact palette)
// ─────────────────────────────────────────────
// Outgoing light: soft Telegram green. Dark: Telegram's deep blue.
const _incomingBubbleColor = CupertinoDynamicColor.withBrightness(
  color: Color(0xFFFFFFFF),
  darkColor: Color(0xFF212B36),
);
const _outgoingBubbleColor = CupertinoDynamicColor.withBrightness(
  color: Color(0xFFEEFEE0),   // Telegram soft green (light mode)
  darkColor: Color(0xFF2B5278), // Telegram dark mode blue
);

// ─────────────────────────────────────────────
//  DYNAMIC OUTGOING TEXT COLOR
// ─────────────────────────────────────────────
// Light mode: dark text on light-green bg. Dark mode: white on dark-blue bg.
Color _outgoingTextColor(BuildContext context) {
  final brightness = CupertinoTheme.brightnessOf(context);
  return brightness == Brightness.dark ? CupertinoColors.white : const Color(0xFF0D1A0D);
}

// ─────────────────────────────────────────────
//  MAIN SCREEN
// ─────────────────────────────────────────────
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
  int _unreadCount = 0; // for scroll-to-bottom badge
  int _prevDocCount = 0; // tracks previous message count to detect new arrivals
  double _navPillScale = 1.0; // overscroll bounce for floating pill

  // Single shared contact stream — reused by presence subtitle AND bottom bar
  late final Stream<DocumentSnapshot> _contactStream;

  @override
  void initState() {
    super.initState();
    _contactStream = FirebaseFirestore.instance
        .collection('contacts')
        .doc(widget.contactJid)
        .snapshots();

    FirebaseFirestore.instance
        .collection('contacts')
        .doc(widget.contactJid)
        .set({'unreadCount': 0}, SetOptions(merge: true));

    // FEATURE 4: Subscribe to this contact's presence so Baileys starts
    // forwarding their typing/online events to us via presence.update.
    // Node's listenToPresenceOutbox picks up this subscribe request.
    FirebaseFirestore.instance.collection('outbox_presence_subscribe').add({
      'jid': widget.contactJid,
      'action': 'subscribe',
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Scroll-to-bottom tracking is now via NotificationListener (not per-pixel addListener)

    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── SEND TEXT ──────────────────────────────
  // FEATURE 1 — Core Messaging & Delivery Status (Ticks)
  //
  // ACK lifecycle:
  //   1. User taps send → message written to Firestore with deliveryStatus:'pending'
  //      → UI shows single grey ✓ immediately (optimistic).
  //   2. Node bridge picks up outbox doc, calls sock.sendMessage().
  //      On success it sets deliveryStatus:'sent' on the Firestore message doc
  //      → UI updates to single white ✓.
  //   3. When WhatsApp server delivers to recipient, Baileys fires
  //      message-receipt.update with deliveredTimestamp
  //      → Node sets deliveryStatus:'delivered' → UI shows ✓✓ grey.
  //   4. When recipient opens the chat, Baileys fires message-receipt.update
  //      with readTimestamp → Node sets deliveryStatus:'read' → UI shows ✓✓ blue.
  //
  // The Firestore StreamBuilder on each bubble re-renders automatically
  // whenever deliveryStatus changes — no polling needed.
  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final jid = widget.contactJid;
    // localId ties the optimistic Firestore doc to the outbox doc so the
    // Node bridge can update the correct message when the ACK arrives.
    final localId = '${DateTime.now().millisecondsSinceEpoch}_${jid.hashCode}';

    final replySnapshot = _replyingTo; // capture before clearing

    // ── Step 1: Optimistic write — shows message instantly with pending tick ──
    final msgPayload = <String, dynamic>{
      'chatId': jid,
      'text': text,
      'from': 'me',
      'isMe': true,
      'localId': localId,
      'deliveryStatus': 'pending', // → single grey ✓
      'timestamp': FieldValue.serverTimestamp(),
    };
    if (replySnapshot != null) {
      // Store full reply context for rendering the quote bubble
      msgPayload['replyTo'] = {
        'text': replySnapshot['text'] ?? '',
        'author': replySnapshot['senderName'] ?? replySnapshot['from'] ?? '',
        if (replySnapshot['mediaUrl'] != null) 'mediaUrl': replySnapshot['mediaUrl'],
        if (replySnapshot['type'] != null) 'type': replySnapshot['type'],
      };
    }
    FirebaseFirestore.instance.collection('messages').add(msgPayload);

    // ── Step 2: Outbox — Node bridge picks this up and sends via Baileys ──
    final outboxPayload = <String, dynamic>{
      'to': jid,
      'text': text,
      'localId': localId, // key for Node to find the correct Firestore doc on ACK
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    };
    if (replySnapshot != null) {
      // Node needs the real WA msgKeyId to construct a quoted message payload
      outboxPayload['replyTo'] = {
        'msgKeyId': replySnapshot['msgKeyId'] ?? '',
      };
    }
    FirebaseFirestore.instance.collection('outbox').add(outboxPayload);

    _textController.clear();
    setState(() => _replyingTo = null);
    // Stop typing indicator when message is sent
    if (_isTypingActive) {
      _isTypingActive = false;
      _sendPresence('paused');
    }
  }

  // ── TYPING PRESENCE ─────────────────────────
  // FEATURE 4 — Typing Indicators & Presence
  //
  // When the user types, we fire a typing_start event via Firestore outbox_presence.
  // Node's listenToPresenceOutbox picks this up and calls:
  //   sock.sendPresenceUpdate('composing', contactJid)
  // When user stops typing for 3s or sends the message, we fire typing_stop:
  //   sock.sendPresenceUpdate('paused', contactJid)
  //
  // The reciprocal flow (seeing THEIR typing) is handled by _PresenceSubtitle
  // which reads the Firestore contact doc that Node updates from Baileys'
  // presence.update events.
  bool _isTypingActive = false;
  DateTime? _lastTypedAt;

  void _onTextChanged() {
    final has = _textController.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);

    if (has) {
      _lastTypedAt = DateTime.now();
      if (!_isTypingActive) {
        _isTypingActive = true;
        _sendPresence('composing');
      }
      // Schedule typing_stop after 3 seconds of inactivity
      Future.delayed(const Duration(seconds: 3), () {
        if (_isTypingActive && _lastTypedAt != null) {
          final idle = DateTime.now().difference(_lastTypedAt!);
          if (idle.inSeconds >= 3) {
            _isTypingActive = false;
            _sendPresence('paused');
          }
        }
      });
    } else {
      if (_isTypingActive) {
        _isTypingActive = false;
        _sendPresence('paused');
      }
    }
  }

  void _sendPresence(String type) {
    // Write to outbox_presence — Node picks this up and calls
    // sock.sendPresenceUpdate(type, contactJid)
    FirebaseFirestore.instance.collection('outbox_presence').add({
      'to': widget.contactJid,
      'presence': type, // 'composing' | 'paused' | 'recording'
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ── REPLY & READ RECEIPTS ──────────────────
  void _setReply(Map<String, dynamic> data) {
    HapticFeedback.selectionClick();
    setState(() => _replyingTo = data);
  }

  // FEATURE 1 & 5 — Read Receipts (Blue Ticks)
  //
  // When the user opens this chat screen, we fire read receipts for all
  // unread incoming messages. This is how WhatsApp turns ticks blue:
  //   Flutter opens chat → fires read_receipt for each unseen incoming message
  //   → Node's listenToReadReceiptOutbox calls sock.readMessages([keys])
  //   → Baileys sends read receipt to WhatsApp servers
  //   → Sender's Baileys gets message-receipt.update with readTimestamp
  //   → Node sets deliveryStatus:'read' → their ticks go blue.
  bool _hasMarkedRead = false;
  void _markAllMessagesRead(List<QueryDocumentSnapshot> docs) {
    if (_hasMarkedRead) return; // only fire once per screen open
    _hasMarkedRead = true;

    final unreadKeys = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['isMe'] != true && d['deliveryStatus'] != 'read' && d['msgKeyId'] != null) {
        unreadKeys.add({
          'remoteJid': widget.contactJid,
          'id': d['msgKeyId'],
          'fromMe': false,
        });
      }
    }
    if (unreadKeys.isEmpty) return;
    // Batch — Node calls sock.readMessages(keys) which triggers the blue tick
    FirebaseFirestore.instance.collection('outbox_read_receipts').add({
      'keys': unreadKeys,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ── COLORS ────────────────────────────────
  Color _senderColor(String name) {
    const colors = [
      Color(0xFFE91E63), Color(0xFF9C27B0), Color(0xFF3F51B5),
      Color(0xFF2196F3), Color(0xFF009688), Color(0xFF4CAF50),
      Color(0xFFFF5722), Color(0xFF795548),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  // ── PIN MESSAGE ────────────────────────────
  // FEATURE 3 — Pinning Messages (Chat-level metadata)
  //
  // Architecture: Pinned messages are chat-level metadata, not message-level.
  // WhatsApp stores pinned_message_id in chat metadata on their servers.
  // We mirror this by:
  //   1. Toggling isPinned flag on the Firestore message doc (so _buildPinnedBanner
  //      can query `where('isPinned', isEqualTo: true)` and show the correct preview).
  //   2. Writing to outbox_pins so Node's listenToPinOutbox sends the real WA
  //      pin event via sock.sendMessage({pin: ...}).
  //   3. Baileys' messages.update event fires a pinInChat update which Node
  //      also handles, keeping both sides in sync.
  void _pinMessage(Map<String, dynamic> data, String docId) {
    final isPinned = data['isPinned'] == true;
    final newPinState = !isPinned;

    // Optimistic local update — UI reflects change immediately
    FirebaseFirestore.instance.collection('messages').doc(docId).update({
      'isPinned': newPinState,
      'pinnedAt': newPinState ? FieldValue.serverTimestamp() : null,
    });

    // Only send WA pin event if we have a real msgKeyId (not a locally-only message)
    final msgKeyId = (data['msgKeyId'] ?? '').toString();
    if (msgKeyId.isNotEmpty) {
      FirebaseFirestore.instance.collection('outbox_pins').add({
        'chatJid': widget.contactJid,
        'msgKeyId': msgKeyId,
        'pin': newPinState,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  // ── CONTEXT MENU (Telegram-style overlay) ──
  void _showContextMenu(BuildContext ctx, Map<String, dynamic> data, String docId, Offset tapPosition) {
    if (data['deleted'] == true) return;
    HapticFeedback.mediumImpact();

    const emojis = ['❤️', '👍', '😂', '😮', '😢', '🙏'];
    final isOutgoing = data['isMe'] == true;
    final hasText = (data['text'] as String? ?? '').isNotEmpty;

    OverlayEntry? overlay;
    overlay = OverlayEntry(
      builder: (overlayCtx) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => overlay?.remove(),
          child: Material(
            color: const Color(0x00000000),
            child: Stack(
              children: [
                // Blurred backdrop
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(color: CupertinoColors.black.withValues(alpha: 0.3)),
                  ),
                ),
                // Menu — centered vertically, aligned to bubble side
                Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.85, end: 1.0),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: isOutgoing
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          // ── Emoji reactions row ──
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemBackground.resolveFrom(ctx),
                              borderRadius: BorderRadius.circular(50),
                              boxShadow: [
                                BoxShadow(
                                  color: CupertinoColors.black.withValues(alpha: 0.18),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: emojis.asMap().entries.map((e) {
                                // FEATURE 6 — Reactions (toggle & update semantics)
                                //
                                // WhatsApp reactions are stored per (user, message) pair.
                                // Tapping the same emoji again removes the reaction (toggle).
                                // Tapping a different emoji replaces the previous one.
                                //
                                // Architecture:
                                //   outbox_reactions doc → Node calls sock.sendMessage({react: ...})
                                //   with the emoji (or empty string '' to remove).
                                //   Baileys fires messages.reaction event which Node uses to update
                                //   the Firestore message doc's 'reactions' array.
                                //   Optimistic local update fires immediately so UI feels instant.
                                final reactions = (data['reactions'] as List<dynamic>? ?? []);
                                final myReaction = reactions
                                    .whereType<Map>()
                                    .where((r) => r['sender'] == kOwnJid)
                                    .map((r) => r['emoji'] as String?)
                                    .firstOrNull;
                                final isSameEmoji = myReaction == e.value;

                                return GestureDetector(
                                  onTap: () {
                                    overlay?.remove();
                                    HapticFeedback.mediumImpact();

                                    // Toggle: same emoji = remove; different = replace
                                    final emojiToSend = isSameEmoji ? '' : e.value;

                                    // Write to WA outbox ('' = remove in WA protocol)
                                    FirebaseFirestore.instance
                                        .collection('outbox_reactions')
                                        .add({
                                      'chatJid': widget.contactJid,
                                      'msgKeyId': data['msgKeyId'] ?? '',
                                      'emoji': emojiToSend,
                                      'fromMe': isOutgoing,
                                      'status': 'pending',
                                    });

                                    // Optimistic local update on Firestore message doc
                                    final msgKeyId = (data['msgKeyId'] ?? '').toString();
                                    if (msgKeyId.isNotEmpty) {
                                      FirebaseFirestore.instance
                                          .collection('messages')
                                          .where('msgKeyId', isEqualTo: msgKeyId)
                                          .limit(1)
                                          .get()
                                          .then((snap) {
                                        if (snap.docs.isEmpty) return;
                                        final ref = snap.docs.first.reference;
                                        final current =
                                            (snap.docs.first.data()['reactions'] as List<dynamic>? ?? []);
                                        // Remove any existing reaction from self
                                        final filtered = current
                                            .where((r) => r is Map && r['sender'] != kOwnJid)
                                            .toList();
                                        // Add new reaction unless toggling off
                                        if (emojiToSend.isNotEmpty) {
                                          filtered.add({'emoji': emojiToSend, 'sender': kOwnJid});
                                        }
                                        ref.update({'reactions': filtered});
                                      });
                                    }
                                  },
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0.0, end: 1.0),
                                    duration: Duration(milliseconds: 180 + e.key * 35),
                                    curve: Curves.easeOutBack,
                                    builder: (_, v, child) => Transform.scale(scale: v, child: child),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                                      decoration: isSameEmoji
                                          ? BoxDecoration(
                                              color: CupertinoColors.systemBlue.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(12),
                                            )
                                          : null,
                                      child: Text(e.value, style: const TextStyle(fontSize: 30)),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // ── Action items ──
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              color: CupertinoColors.systemBackground.resolveFrom(ctx),
                              constraints: const BoxConstraints(minWidth: 220),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ContextMenuItem(
                                    icon: CupertinoIcons.reply,
                                    label: 'Reply',
                                    onTap: () { overlay?.remove(); _setReply(data); },
                                  ),
                                  _ContextMenuDivider(),
                                  if (hasText) ...[
                                    _ContextMenuItem(
                                      icon: CupertinoIcons.doc_on_clipboard,
                                      label: 'Copy',
                                      onTap: () {
                                        overlay?.remove();
                                        Clipboard.setData(ClipboardData(text: data['text'] ?? ''));
                                        HapticFeedback.selectionClick();
                                      },
                                    ),
                                    _ContextMenuDivider(),
                                  ],
                                  _ContextMenuItem(
                                    icon: data['isPinned'] == true
                                        ? CupertinoIcons.pin_slash
                                        : CupertinoIcons.pin,
                                    label: data['isPinned'] == true ? 'Unpin' : 'Pin',
                                    onTap: () { overlay?.remove(); _pinMessage(data, docId); },
                                  ),
                                  _ContextMenuDivider(),
                                  _ContextMenuItem(
                                    icon: CupertinoIcons.delete,
                                    label: 'Delete',
                                    isDestructive: true,
                                    onTap: () {
                                      overlay?.remove();
                                      // FEATURE 2 — Delete for Everyone (Tombstone mechanism)
                                      //
                                      // WhatsApp enforces a ~48-hour window for delete-for-everyone.
                                      // We replicate that here:
                                      //   1. Check if the message is within 48h (client-side guard)
                                      //   2. Show confirmation: "Delete for Me" vs "Delete for Everyone"
                                      //   3. On "for everyone": mark local doc as tombstone + write
                                      //      to outbox_deletes so Node sends the WA delete event.
                                      //   4. On "for me": just update local Firestore doc (no WA event).
                                      //
                                      // The tombstone text ("This message was deleted") is set on the
                                      // Firestore doc so all Flutter clients see it immediately.
                                      // Node's delete-for-everyone also fires the WA revoke, making
                                      // the recipient's native WA client show the tombstone too.
                                      final ts = data['timestamp'] as Timestamp?;
                                      final sentAt = ts?.toDate();
                                      final withinWindow = sentAt == null
                                          ? false
                                          : DateTime.now().difference(sentAt).inHours < 48;
                                      final isOwnMessage = data['isMe'] == true;

                                      showCupertinoDialog(
                                        context: context,
                                        builder: (ctx) => CupertinoAlertDialog(
                                          title: const Text('Delete Message'),
                                          actions: [
                                            // Delete for Everyone (only if own message within 48h)
                                            if (isOwnMessage && withinWindow)
                                              CupertinoDialogAction(
                                                isDestructiveAction: true,
                                                onPressed: () {
                                                  Navigator.pop(ctx);
                                                  // Tombstone local doc immediately
                                                  FirebaseFirestore.instance
                                                      .collection('messages')
                                                      .doc(docId)
                                                      .update({
                                                    'deleted': true,
                                                    'text': 'This message was deleted',
                                                  }).catchError((e) => debugPrint('Delete err: $e'));
                                                  // Tell Node to send WA revoke event
                                                  if ((data['msgKeyId'] ?? '').toString().isNotEmpty) {
                                                    FirebaseFirestore.instance
                                                        .collection('outbox_deletes')
                                                        .add({
                                                      'chatJid': widget.contactJid,
                                                      'msgKeyId': data['msgKeyId'],
                                                      'fromMe': true,
                                                      'status': 'pending',
                                                      'timestamp': FieldValue.serverTimestamp(),
                                                    }).catchError((e) => debugPrint('Delete outbox err: $e'));
                                                  }
                                                },
                                                child: const Text('Delete for Everyone'),
                                              ),
                                            // Delete for Me (local only, always available)
                                            CupertinoDialogAction(
                                              isDestructiveAction: true,
                                              onPressed: () {
                                                Navigator.pop(ctx);
                                                FirebaseFirestore.instance
                                                    .collection('messages')
                                                    .doc(docId)
                                                    .update({
                                                  'deleted': true,
                                                  'text': 'This message was deleted',
                                                }).catchError((e) => debugPrint('Delete local err: $e'));
                                              },
                                              child: const Text('Delete for Me'),
                                            ),
                                            CupertinoDialogAction(
                                              isDefaultAction: true,
                                              onPressed: () => Navigator.pop(ctx),
                                              child: const Text('Cancel'),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    Overlay.of(ctx).insert(overlay!);
  }

  // ── PROFILE VIEWER ─────────────────────────
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

  // ── MEDIA UPLOAD (Supabase PUT) ────────────
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
              Text('Uploading…'),
            ],
          ),
        ),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final fileBytes = await file.readAsBytes();
      final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'jpg';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';

      final contentType = type == 'video'
          ? 'video/mp4'
          : ext == 'png'
              ? 'image/png'
              : 'image/jpeg';

      final uploadUrl = Uri.parse(
          'https://ooopunhwxoffnfuawmmy.supabase.co/storage/v1/object/whatsapp-media/$fileName');

      final response = await http.put(
        uploadUrl,
        headers: {
          'Authorization':
              'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9vb3B1bmh3eG9mZm5mdWF3bW15Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIxOTUyMzcsImV4cCI6MjA4Nzc3MTIzN30.qTyNjiDymtQhdruqvpcWQx-TIyxL2YK-k4rODtO9TcY',
          'Content-Type': contentType,
          'x-upsert': 'true',
        },
        body: fileBytes,
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Upload failed: HTTP ${response.statusCode}\n${response.body}');
      }

      final secureUrl =
          'https://ooopunhwxoffnfuawmmy.supabase.co/storage/v1/object/public/whatsapp-media/$fileName';
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
        outboxPayload['replyTo'] = {'msgKeyId': _replyingTo!['msgKeyId'] ?? ''};
        setState(() => _replyingTo = null);
      }
      await FirebaseFirestore.instance.collection('outbox_media').add(outboxPayload);

      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Upload Failed'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      }
    }
  }

  void _pickAndSendMedia() async {
    final picker = ImagePicker();
    showCupertinoModalPopup(
      context: context,
      builder: (dialogCtx) => CupertinoActionSheet(
        title: const Text('Attach Media'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
              if (file != null && mounted) _uploadAndSendMedia(file, 'image');
            },
            child: const Text('Photo Library'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
              if (file != null && mounted) _uploadAndSendMedia(file, 'image');
            },
            child: const Text('Camera'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final file = await picker.pickVideo(source: ImageSource.gallery);
              if (file != null && mounted) _uploadAndSendMedia(file, 'video');
            },
            child: const Text('Video'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(dialogCtx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
  // Heights used for padding computations
  static const double _kNavBarH = 56.0;
  static const double _kBottomBarEstH = 68.0;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground.resolveFrom(context),
      child: Stack(
        children: [
          // LAYER 0: Wallpaper (edge-to-edge)
          const Positioned.fill(child: ChatWallpaperBackground()),

          // LAYER 1: Messages (edge-to-edge, scrolls behind bars)
          Positioned.fill(child: _buildMessageList()),

          // LAYER 1b: Scroll-to-bottom button
          Positioned(
            bottom: _kBottomBarEstH + bottomPad + 8,
            right: 16,
            child: AnimatedScale(
              scale: _showScrollToBottom ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              child: _ScrollToBottomButton(
                unreadCount: _unreadCount,
                onTap: () {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                  );
                  setState(() => _unreadCount = 0);
                },
              ),
            ),
          ),

          // LAYER 2: Top scrim gradient (content darkening under nav)
          Positioned(
            top: 0, left: 0, right: 0,
            height: topPad + _kNavBarH + 32,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      CupertinoDynamicColor.resolve(
                        const CupertinoDynamicColor.withBrightness(
                          color: Color(0xF0F2F2F7),   // nearly opaque light
                          darkColor: Color(0xE8000000), // nearly opaque dark
                        ),
                        context,
                      ),
                      const Color(0x00000000),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // LAYER 3: Bottom scrim gradient (content darkening under input)
          Positioned(
            bottom: 0, left: 0, right: 0,
            height: bottomPad + _kBottomBarEstH + 48,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      CupertinoDynamicColor.resolve(
                        const CupertinoDynamicColor.withBrightness(
                          color: Color(0xF0F2F2F7),
                          darkColor: Color(0xE8000000),
                        ),
                        context,
                      ),
                      const Color(0x00000000),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // LAYER 4: Nav pills (transparent bar, individual pill blur)
          Positioned(
            top: topPad + (_kNavBarH - 32) / 2,
            left: 8,
            right: 8,
            child: AnimatedScale(
              scale: _navPillScale,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: _buildNavBar(),
            ),
          ),

          // LAYER 5: Pinned Bar
          Positioned(
            top: topPad + _kNavBarH + 4,
            left: 20,
            right: 20,
            child: _buildPinnedBanner(),
          ),

          // LAYER 6: Bottom bar (transparent, pills blur individually)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  NAV BAR  (Telegram-style)
  // ─────────────────────────────────────────────
  // ─ Saturation boost matrix (1.7×) for glass vibrancy ─
  // ─ Saturation boost matrix removed — no longer needed ─

  // ─────────────────────────────────────────────
  //  LIQUID GLASS PILL — shared container
  // ─────────────────────────────────────────────
  Widget _buildLiquidPill({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: CupertinoDynamicColor.resolve(
              const CupertinoDynamicColor.withBrightness(
                color: Color(0x94FFFFFF),
                darkColor: Color(0xAE2C2C2E),
              ),
              context,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: child,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  HEADER CONTENT — 3 separate Telegram-style pills
  // ─────────────────────────────────────────────
  Widget _buildNavBar() {
    final pillColor = CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: Color(0x94FFFFFF),   // white @ 0.58
        darkColor: Color(0xAE2C2C2E), // charcoal @ 0.68
      ),
      context,
    );
    final iconPillColor = CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: Color(0x85FFFFFF),   // white @ 0.52
        darkColor: Color(0x9E2C2C2E), // charcoal @ 0.62
      ),
      context,
    );

    return Row(
      children: [
        // ── BACK PILL ──
        _NavPressablePill(
          height: 32,
          radius: 16,
          color: pillColor,
          onTap: () => Navigator.of(context).pop(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.back,
                color: CupertinoColors.systemBlue.resolveFrom(context),
                size: 20,
              ),
              const SizedBox(width: 3),
              Text(
                'Chats',
                style: TextStyle(
                  color: CupertinoColors.systemBlue.resolveFrom(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // ── CENTER PILL (avatar + name + status) ──
        Expanded(
          child: Center(
            child: _NavPressablePill(
              height: 40,
              radius: 18,
              color: pillColor,
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute(
                  builder: (_) => ContactInfoScreen(contactJid: widget.contactJid),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _openProfileViewer,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF54C5F8), Color(0xFF2196F3)],
                        ),
                      ),
                      child: (widget.profileUrl != null && widget.profileUrl!.isNotEmpty)
                          ? ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: widget.profileUrl!,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => _buildFallbackAvatar(30),
                                errorWidget: (_, __, ___) => _buildFallbackAvatar(30),
                              ),
                            )
                          : _buildFallbackAvatar(30),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.contactName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                            color: CupertinoColors.label.resolveFrom(context),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 1),
                        _PresenceSubtitle(stream: _contactStream, ownJid: kOwnJid),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // ── RIGHT ICONS (video + phone) — individual 34px circles ──
        _NavPressablePill(
          height: 34,
          radius: 17,
          color: iconPillColor,
          onTap: () => showCupertinoDialog(
            context: context,
            builder: (ctx) => CupertinoAlertDialog(
              title: const Text('Video Call'),
              content: const Text('Video calling is not yet supported.'),
              actions: [
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
          child: Icon(
            CupertinoIcons.video_camera,
            color: CupertinoColors.systemBlue.resolveFrom(context),
            size: 20,
          ),
        ),
        const SizedBox(width: 8),
        _NavPressablePill(
          height: 34,
          radius: 17,
          color: iconPillColor,
          onTap: () => showCupertinoDialog(
            context: context,
            builder: (ctx) => CupertinoAlertDialog(
              title: const Text('Voice Call'),
              content: const Text('Voice calling is not yet supported.'),
              actions: [
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
          child: Icon(
            CupertinoIcons.phone,
            color: CupertinoColors.systemBlue.resolveFrom(context),
            size: 19,
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackAvatar(double size) {
    return Center(
      child: Text(
        widget.avatarLetter.toUpperCase(),
        style: TextStyle(
          color: CupertinoColors.white,
          fontSize: size * 0.44,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  PINNED MESSAGE BANNER
  // ─────────────────────────────────────────────
  // FIX: Track which pinned message index is shown so user can cycle through them.
  int _pinnedIndex = 0;

  Widget _buildPinnedBanner() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('messages')
          .where('chatId', isEqualTo: widget.contactJid)
          .where('isPinned', isEqualTo: true)
          .limit(3)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();
        final docs = snap.data!.docs;
        final idx = _pinnedIndex.clamp(0, docs.length - 1);
        final pinned = docs[idx].data() as Map<String, dynamic>;
        final pinnedText = pinned['text'] as String? ?? '';
        final pinnedType = pinned['type'] as String?;
        final preview = pinnedText.isNotEmpty
            ? pinnedText
            : pinnedType == 'image'
                ? '📷 Photo'
                : pinnedType == 'video'
                    ? '🎬 Video'
                    : pinnedType == 'audio'
                        ? '🎤 Voice message'
                        : '📎 Attachment';

        return _buildLiquidPill(
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                // Pin icon
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text('📌', style: TextStyle(fontSize: 14)),
                ),
                _PinnedProgressBar(total: docs.length, activeIndex: idx),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _pinnedIndex = (idx + 1) % docs.length),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) {
                        final slide = Tween<Offset>(
                          begin: const Offset(0, 0.5),
                          end: Offset.zero,
                        ).animate(anim);
                        return SlideTransition(
                          position: slide,
                          child: FadeTransition(opacity: anim, child: child),
                        );
                      },
                      child: Column(
                        key: ValueKey('pin_$idx'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            docs.length > 1
                                ? 'Pinned message ${idx + 1} of ${docs.length}'
                                : 'Pinned message',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: CupertinoColors.systemBlue,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.secondaryLabel.resolveFrom(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 32,
                  onPressed: () {
                    showCupertinoDialog(
                      context: context,
                      builder: (ctx) => CupertinoAlertDialog(
                        title: const Text('Unpin Message'),
                        content: const Text(
                            'Do you want to unpin this message for everyone?'),
                        actions: [
                          CupertinoDialogAction(
                            isDestructiveAction: true,
                            onPressed: () {
                              Navigator.pop(ctx);
                              FirebaseFirestore.instance
                                  .collection('messages')
                                  .doc(docs[idx].id)
                                  .update({'isPinned': false, 'pinnedAt': null});
                            },
                            child: const Text('Unpin'),
                          ),
                          CupertinoDialogAction(
                            isDefaultAction: true,
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Icon(
                    CupertinoIcons.xmark,
                    size: 16,
                    color: CupertinoColors.systemGrey.resolveFrom(context),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  //  MESSAGE LIST
  // ─────────────────────────────────────────────
  Widget _buildMessageList() {
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
                    style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
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

        // FIX: Track new incoming messages for the scroll-to-bottom badge.
        // Only count messages when the user is scrolled away from the bottom.
        if (_prevDocCount > 0 && docs.length > _prevDocCount && _showScrollToBottom) {
          final newest = docs.first.data() as Map<String, dynamic>;
          if (newest['isMe'] != true) {
            setState(() => _unreadCount += docs.length - _prevDocCount);
          }
        }
        _prevDocCount = docs.length;

        // FEATURE 1 & 5: Fire read receipts so sender's ticks go blue.
        // Only fired once per screen open (guarded by _hasMarkedRead).
        WidgetsBinding.instance.addPostFrameCallback((_) => _markAllMessagesRead(docs));

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.chat_bubble_2,
                    size: 64, color: CupertinoColors.systemGrey.withValues(alpha: 0.3)),
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

        return NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            if (notification is ScrollUpdateNotification) {
              final show = notification.metrics.pixels > 300;
              if (show != _showScrollToBottom) {
                setState(() {
                  _showScrollToBottom = show;
                  if (!show) _unreadCount = 0;
                });
              }
            }
            // Overscroll bounce for nav pill (reverse list: overscroll at bottom = list top)
            if (notification is OverscrollNotification) {
              if (_navPillScale != 0.98) {
                setState(() => _navPillScale = 0.98);
              }
            } else if (notification is ScrollEndNotification) {
              if (_navPillScale != 1.0) {
                setState(() => _navPillScale = 1.0);
              }
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            reverse: true,
            cacheExtent: 500.0,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              4,
              _kBottomBarEstH + MediaQuery.of(context).padding.bottom + 80,  // visual bottom (reverse top)
              4,
              _kNavBarH + MediaQuery.of(context).padding.top + 64,           // visual top (reverse bottom)
            ),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final isOutgoing = data['isMe'] == true;
              final timestamp = data['timestamp'] as Timestamp?;

              // Format time
              String timeStr = '';
              if (timestamp != null) {
                final dt = timestamp.toDate();
                timeStr =
                    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
              }

              // Date header
              Widget? dateHeader;
              if (timestamp != null) {
                final currentDate = timestamp.toDate();
                DateTime? prevDate;
                if (index < docs.length - 1) {
                  final prevTs = (docs[index + 1].data() as Map<String, dynamic>)['timestamp']
                      as Timestamp?;
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

              // Grouping: only the newest message in a cluster gets a tail.
              bool isTailMessage = true;
              bool isClusterMember = false;

              if (index < docs.length - 1) {
                final olderData = docs[index + 1].data() as Map<String, dynamic>;
                final olderIsOutgoing = olderData['isMe'] == true;
                final olderTs = olderData['timestamp'] as Timestamp?;
                if (olderIsOutgoing == isOutgoing && timestamp != null && olderTs != null) {
                  final diff = timestamp.toDate().difference(olderTs.toDate()).abs();
                  if (diff.inMinutes < 2) isClusterMember = true;
                }
              }

              if (index > 0) {
                final newerData = docs[index - 1].data() as Map<String, dynamic>;
                final newerIsOutgoing = newerData['isMe'] == true;
                final newerTs = newerData['timestamp'] as Timestamp?;
                if (newerIsOutgoing == isOutgoing && timestamp != null && newerTs != null) {
                  final diff = newerTs.toDate().difference(timestamp.toDate()).abs();
                  if (diff.inMinutes < 2) isTailMessage = false;
                }
              }

              final docId = docs[index].id;
              final isGroup = widget.contactJid.endsWith('@g.us');
              final senderName = data['senderName'] as String? ?? '';
              final isNewest = index == 0;

              Widget item = _buildMessageItem(
                context, data, docId, isOutgoing, isGroup, senderName,
                dateHeader, timeStr, isTailMessage, isClusterMember,
              );

              // Entrance animation — spring for newest, stagger for initial load
              if (isNewest) {
                item = _SpringEntranceWidget(
                  key: ValueKey('anim_$docId'),
                  isOutgoing: isOutgoing,
                  child: item,
                );
              } else if (index < 8 && _prevDocCount <= 1) {
                // Stagger initial load: first 8 messages cascade in
                item = TweenAnimationBuilder<double>(
                  key: ValueKey('stagger_$docId'),
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 350 + (index * 40)),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, child) => Opacity(
                    opacity: v.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.9 + (0.1 * v),
                      child: child,
                    ),
                  ),
                  child: item,
                );
              }

              return item;
            },
          ),
        );
      },
    );
  }

  Widget _buildMessageItem(
    BuildContext context,
    Map<String, dynamic> data,
    String docId,
    bool isOutgoing,
    bool isGroup,
    String senderName,
    Widget? dateHeader,
    String timeStr,
    bool isTailMessage,
    bool isClusterMember,
  ) {
    return Column(
      children: [
        if (dateHeader != null) dateHeader,
        _SwipableBubbleRow(
          data: data,
          time: timeStr,
          isOutgoing: isOutgoing,
          isGroup: isGroup,
          senderName: senderName,
          senderColor: senderName.isNotEmpty ? _senderColor(senderName) : CupertinoColors.systemBlue,
          docId: docId,
          isTailMessage: isTailMessage,
          isClusterMember: isClusterMember,
          onReply: _setReply,
          onLongPress: (tapPosition) => _showContextMenu(context, data, docId, tapPosition),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  BOTTOM BAR  (blur + typing + input)
  // ─────────────────────────────────────────────
  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 8, bottom: 4, top: 4),
        child: StreamBuilder<DocumentSnapshot>(
          stream: _contactStream,
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
                // Typing bubble
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (child, anim) {
                            return FadeTransition(
                              opacity: anim,
                              child: ScaleTransition(
                                scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                                alignment: Alignment.bottomLeft,
                                child: child,
                              ),
                            );
                          },
                          child: isTyping
                              ? Align(
                                  key: const ValueKey('typing_bubble'),
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 6, bottom: 4, top: 6),
                                    child: CustomPaint(
                                      painter: _BubbleTailPainter(
                                        color: CupertinoDynamicColor.resolve(
                                          const CupertinoDynamicColor.withBrightness(
                                            color: Color(0xFFE5E5EA),
                                            darkColor: Color(0xFF2C2C2E),
                                          ),
                                          context,
                                        ),
                                        isOutgoing: false,
                                      ),
                                      child: Container(
                                        margin: const EdgeInsets.only(left: 8),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: CupertinoDynamicColor.resolve(
                                            const CupertinoDynamicColor.withBrightness(
                                              color: Color(0xFFE5E5EA),
                                              darkColor: Color(0xFF2C2C2E),
                                            ),
                                            context,
                                          ),
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(18),
                                            topRight: Radius.circular(18),
                                            bottomRight: Radius.circular(18),
                                            bottomLeft: Radius.circular(4),
                                          ),
                                        ),
                                        child: const _TypingIndicator(),
                                      ),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(key: ValueKey('no_typing')),
                        ),
                        if (isAdminOnly)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              'Only admins can send messages',
                              style: TextStyle(
                                fontSize: 14,
                                color: CupertinoColors.secondaryLabel.resolveFrom(context),
                              ),
                            ),
                          )
                        else
                          _buildInputBar(),
                ],
              );
            },
          ),
        ),
      );
  }

  // ─────────────────────────────────────────────
  //  INPUT BAR  (Telegram layout)
  // ─────────────────────────────────────────────
  Widget _buildInputBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reply banner (animates in/out with slide + fade)
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            final slide = Tween<Offset>(
              begin: const Offset(0, 1.0),
              end: Offset.zero,
            ).animate(animation);
            return SlideTransition(
              position: slide,
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            );
          },
          child: _replyingTo != null
              ? KeyedSubtree(
                  key: const ValueKey('reply_banner'),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(0, 0, 0, 6),
                        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                        decoration: BoxDecoration(
                          color: CupertinoDynamicColor.resolve(
                            const CupertinoDynamicColor.withBrightness(
                              color: Color(0xD1FFFFFF),   // white @ 0.82
                              darkColor: Color(0xE02C2C2E), // charcoal @ 0.88
                            ),
                            context,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: CupertinoColors.separator.resolveFrom(context),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                      children: [
                        // Blue accent bar
                        Container(
                          width: 3,
                          height: 36,
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemBlue.resolveFrom(context),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _replyingTo!['senderName'] ?? 'Reply',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: CupertinoColors.systemBlue.resolveFrom(context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _replyingTo!['text'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 28,
                          onPressed: () => setState(() => _replyingTo = null),
                          child: Icon(
                            CupertinoIcons.xmark_circle_fill,
                            size: 20,
                            color: CupertinoColors.systemGrey.resolveFrom(context),
                          ),
                        ),
                      ],
                    ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        // Input row
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Attach button — circle pill
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: GestureDetector(
                  onTap: _pickAndSendMedia,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: CupertinoDynamicColor.resolve(
                            const CupertinoDynamicColor.withBrightness(
                              color: Color(0x85FFFFFF),   // white @ 0.52
                              darkColor: Color(0x9E2C2C2E), // charcoal @ 0.62
                            ),
                            context,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          CupertinoIcons.add_circled,
                          size: 22,
                          color: CupertinoColors.systemBlue.resolveFrom(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Text field — frosted pill
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  decoration: BoxDecoration(
                    color: CupertinoDynamicColor.resolve(
                      const CupertinoDynamicColor.withBrightness(
                        color: Color(0xB8FFFFFF),   // white @ 0.72
                        darkColor: Color(0xC72C2C2E), // charcoal @ 0.78
                      ),
                      context,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: CupertinoDynamicColor.resolve(
                        const CupertinoDynamicColor.withBrightness(
                          color: Color(0xFFD0D0D0),
                          darkColor: Color(0xFF48484A),
                        ),
                        context,
                      ),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: CupertinoTextField(
                          controller: _textController,
                          placeholder: 'Message',
                          maxLines: null,
                          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                          decoration: null,
                          style: TextStyle(
                            fontSize: 16,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                          placeholderStyle: TextStyle(
                            fontSize: 16,
                            color: CupertinoColors.placeholderText.resolveFrom(context),
                          ),
                        ),
                      ),
                      // Emoji / sticker button (inside field, right side)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6, right: 4),
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 32,
                          // FIX: Previously silent no-op. Now shows a coming-soon hint.
                          onPressed: () => showCupertinoModalPopup(
                            context: context,
                            builder: (ctx) => CupertinoActionSheet(
                              title: const Text('Emoji & Stickers'),
                              message: const Text('Emoji picker coming soon. Use your system keyboard emoji key for now.'),
                              cancelButton: CupertinoActionSheetAction(
                                isDefaultAction: true,
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('OK'),
                              ),
                            ),
                          ),
                          child: Image.asset(
                            'assets/Images.xcassets/Chat/Input/Text/AccessoryIconStickers.imageset/ConversationInputFieldStickerIcon@3x.png',
                            width: 22,
                            height: 22,
                            color: CupertinoColors.systemGrey.resolveFrom(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Send / mic button
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                  child: child,
                ),
                child: _hasText
                    ? _SendButton(key: const ValueKey('send'), onTap: _sendMessage)
                    : _MicButton(key: const ValueKey('mic')),
              ),
            ],
          ),
        ),
      ]);

  }
}

// ═══════════════════════════════════════════════
//  TELEGRAM BACK ARROW PAINTER
// ═══════════════════════════════════════════════
class _TelegramBackArrowPainter extends CustomPainter {
  final Color color;
  const _TelegramBackArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Exact Telegram iOS SVG path, scaled to fit the widget bounds.
    // Original viewBox: 0 0 13 23
    final sx = size.width / 13.0;
    final sy = size.height / 23.0;

    final path = Path()
      ..moveTo(3.60751322 * sx, 11.5 * sy)
      ..lineTo(11.5468531 * sx, 3.56066017 * sy)
      ..cubicTo(12.1326395 * sx, 2.97487373 * sy, 12.1326395 * sx, 2.02512627 * sy, 11.5468531 * sx, 1.43933983 * sy)
      ..cubicTo(10.9610666 * sx, 0.853553391 * sy, 10.0113191 * sx, 0.853553391 * sy, 9.42553271 * sx, 1.43933983 * sy)
      ..lineTo(0.449102936 * sx, 10.4157696 * sy)
      ..cubicTo(-0.149700979 * sx, 11.0145735 * sy, -0.149700979 * sx, 11.9854265 * sy, 0.449102936 * sx, 12.5842304 * sy)
      ..lineTo(9.42553271 * sx, 21.5606602 * sy)
      ..cubicTo(10.0113191 * sx, 22.1464466 * sy, 10.9610666 * sx, 22.1464466 * sy, 11.5468531 * sx, 21.5606602 * sy)
      ..cubicTo(12.1326395 * sx, 20.9748737 * sy, 12.1326395 * sx, 20.0251263 * sy, 11.5468531 * sx, 19.4393398 * sy)
      ..lineTo(3.60751322 * sx, 11.5 * sy)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Sub-pixel offset for high-DPI alignment
    canvas.translate(0.33, 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TelegramBackArrowPainter oldDelegate) => color != oldDelegate.color;
}

// ═══════════════════════════════════════════════
//  TELEGRAM PAGE ROUTE (edge shadow + parallax)
// ═══════════════════════════════════════════════
class TelegramPageRoute<T> extends CupertinoPageRoute<T> {
  TelegramPageRoute({required super.builder, super.settings});

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Squircle corner radius during transition
    final cornerRadius = Tween<double>(begin: 0, end: 0)
        .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        return Stack(
          children: [
            // Bottom screen (parallax at 0.3 ratio)
            if (secondaryAnimation.value > 0)
              SlideTransition(
                position: Tween<Offset>(
                  begin: Offset.zero,
                  end: const Offset(-0.3, 0),
                ).animate(secondaryAnimation),
                child: const SizedBox.expand(),
              ),
            // Edge shadow on leading side
            SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              )),
              child: Stack(
                children: [
                  // Shadow on left edge
                  Positioned(
                    left: -16,
                    top: 0,
                    bottom: 0,
                    width: 16,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF000000).withValues(alpha: 0.5 * animation.value),
                            blurRadius: 16.0,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // The actual page content
                  ClipRRect(
                    borderRadius: BorderRadius.circular(cornerRadius.value),
                    child: child,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════
//  SPRING ENTRANCE ANIMATION
// ═══════════════════════════════════════════════
class _SpringEntranceWidget extends StatefulWidget {
  final bool isOutgoing;
  final Widget child;
  const _SpringEntranceWidget({super.key, required this.isOutgoing, required this.child});

  @override
  State<_SpringEntranceWidget> createState() => _SpringEntranceWidgetState();
}

class _SpringEntranceWidgetState extends State<_SpringEntranceWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    return AnimatedBuilder(
      animation: curved,
      builder: (_, child) {
        final v = curved.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.scale(
            scale: 0.92 + (0.08 * v),
            alignment: widget.isOutgoing ? Alignment.bottomRight : Alignment.bottomLeft,
            child: Transform.translate(
              offset: Offset(widget.isOutgoing ? (1 - v) * 30 : (1 - v) * -30, 0),
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ═══════════════════════════════════════════════
//  SWIPABLE BUBBLE ROW (spring animation)
// ═══════════════════════════════════════════════
class _SwipableBubbleRow extends StatefulWidget {
  final Map<String, dynamic> data;
  final String time;
  final bool isOutgoing;
  final bool isGroup;
  final String senderName;
  final Color senderColor;
  final String docId;
  final bool isTailMessage;
  final bool isClusterMember;
  final void Function(Map<String, dynamic>) onReply;
  final void Function(Offset tapPosition) onLongPress;

  const _SwipableBubbleRow({
    required this.data,
    required this.time,
    required this.isOutgoing,
    required this.isGroup,
    required this.senderName,
    required this.senderColor,
    required this.docId,
    required this.isTailMessage,
    this.isClusterMember = false,
    required this.onReply,
    required this.onLongPress,
  });

  @override
  State<_SwipableBubbleRow> createState() => _SwipableBubbleRowState();
}

class _SwipableBubbleRowState extends State<_SwipableBubbleRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _swipeAnim;
  bool _didTriggerHaptic = false;
  double _dragOffset = 0;
  Offset _lastTapPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _swipeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _swipeAnim.dispose();
    super.dispose();
  }

  void _springBack(double velocity) {
    final start = _dragOffset; // capture before reset
    final spring = SpringDescription(
      mass: 1,
      stiffness: 500,
      damping: 30,
    );
    final simulation = SpringSimulation(spring, start, 0, velocity);
    _swipeAnim.animateWith(simulation);
    // Do NOT reset _dragOffset here — let the animation drive value from start → 0
    _didTriggerHaptic = false;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (d) => _lastTapPosition = d.globalPosition,
      onLongPressStart: (d) {
        _lastTapPosition = d.globalPosition;
        widget.onLongPress(_lastTapPosition);
      },
      onDoubleTap: () {
        if (widget.data['deleted'] == true) return;
        widget.onLongPress(_lastTapPosition);
      },
      onHorizontalDragUpdate: (details) {
        if (widget.data['deleted'] == true) return;
        final delta = widget.isOutgoing ? -details.delta.dx : details.delta.dx;
        if (delta > 0 || _dragOffset > 0) {
          setState(() {
            _dragOffset = (_dragOffset + delta).clamp(0.0, 72.0);
            if (_dragOffset > 44 && !_didTriggerHaptic) {
              _didTriggerHaptic = true;
              HapticFeedback.lightImpact();
            } else if (_dragOffset <= 44) {
              _didTriggerHaptic = false;
            }
          });
        }
      },
      onHorizontalDragEnd: (details) {
        if (_dragOffset > 44) widget.onReply(widget.data);
        final velocity = widget.isOutgoing ? -details.velocity.pixelsPerSecond.dx : details.velocity.pixelsPerSecond.dx;
        _springBack(velocity);
        setState(() {});
      },
      onHorizontalDragCancel: () {
        _springBack(0);
        setState(() {});
      },
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          alignment: widget.isOutgoing ? Alignment.centerLeft : Alignment.centerRight,
          children: [
            // Reply icon revealed during swipe
            AnimatedOpacity(
              opacity: (_dragOffset / 60).clamp(0.0, 1.0),
              duration: const Duration(milliseconds: 50),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey5.resolveFrom(context),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    CupertinoIcons.reply,
                    color: CupertinoColors.systemGrey,
                    size: 16,
                  ),
                ),
              ),
            ),
            // Bubble
            Align(
              alignment: widget.isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
              child: AnimatedBuilder(
                animation: _swipeAnim,
                builder: (_, child) {
                  // Direct offset from animation value (driven by SpringSimulation)
                  final offset = _swipeAnim.isAnimating
                      ? _swipeAnim.value
                      : _dragOffset;
                  return Transform.translate(
                    offset: Offset(widget.isOutgoing ? -offset : offset, 0),
                    child: child,
                  );
                },
                child: _ChatBubble(
                  data: widget.data,
                  time: widget.time,
                  isOutgoing: widget.isOutgoing,
                  isGroup: widget.isGroup,
                  senderName: widget.senderName,
                  senderColor: widget.senderColor,
                  docId: widget.docId,
                  isTailMessage: widget.isTailMessage,
                  isClusterMember: widget.isClusterMember,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
//  CHAT BUBBLE
// ═══════════════════════════════════════════════
class _ChatBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final String time;
  final bool isOutgoing;
  final bool isGroup;
  final String senderName;
  final Color senderColor;
  final String docId;
  final bool isTailMessage;
  final bool isClusterMember;

  const _ChatBubble({
    required this.data,
    required this.time,
    required this.isOutgoing,
    required this.isGroup,
    required this.senderName,
    required this.senderColor,
    required this.docId,
    required this.isTailMessage,
    this.isClusterMember = false,
  });

  @override
  Widget build(BuildContext context) {
    final type = data['type'] as String?;
    final replyTo = data['replyTo'] as Map<String, dynamic>?;
    final reactions = data['reactions'] as List<dynamic>?;
    final isDeleted = data['deleted'] == true;
    final isMediaOnly = ['image', 'video', 'audio', 'file'].contains(type) &&
        (data['text'] as String? ?? '').isEmpty;

    // Tight 2px padding within a cluster, 8px between clusters
    final verticalPad = isClusterMember && !isTailMessage ? 1.0 : 4.0;

    return Padding(
      padding: EdgeInsets.only(
        top: verticalPad,
        bottom: (reactions != null && reactions.isNotEmpty) ? 14.0 : verticalPad,
        left: isOutgoing ? 80 : 0,
        right: isOutgoing ? 0 : 80,
      ),
      child: Row(
        mainAxisAlignment: isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              // ── The bubble itself ──
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(
                    isOutgoing ? _outgoingBubbleColor : _incomingBubbleColor,
                    context,
                  ),
                  borderRadius: _bubbleRadius(isOutgoing, isTailMessage),
                  boxShadow: [
                    BoxShadow(
                      color: CupertinoColors.black.withValues(alpha: 0.07),
                      blurRadius: 4,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: _bubbleRadius(isOutgoing, isTailMessage),
                  child: Padding(
                    padding: _bubblePadding(type, isMediaOnly),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Group sender name (inside bubble, Telegram style)
                        if (isGroup && !isOutgoing && senderName.isNotEmpty && !isDeleted)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: 1.0,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                senderName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.4,
                                  color: senderColor,
                                ),
                              ),
                            ),
                          ),
                        // Reply preview
                        if (replyTo != null && !isDeleted)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: 1.0,
                            child: _ReplyPreviewInBubble(
                              replyTo: replyTo,
                              isOutgoing: isOutgoing,
                            ),
                          ),
                        // Content + Time — inline for text, stacked for media
                        if (type == 'text' || type == null || (!isMediaOnly && !isDeleted))
                          // Text messages: Wrap lets time sit inline after short text
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: 1.0,
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              crossAxisAlignment: WrapCrossAlignment.end,
                              spacing: 4,
                              runSpacing: 0,
                              children: [
                                _buildContent(context, type, isDeleted, isMediaOnly),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 1),
                                  child: _TimeRow(
                                    time: time,
                                    isOutgoing: isOutgoing,
                                    deliveryStatus: data['deliveryStatus'] as String? ?? 'pending',
                                    docId: docId,
                                    data: data,
                                    overlayOnMedia: false,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          // Media messages: stacked layout
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: 1.0,
                            child: _buildContent(context, type, isDeleted, isMediaOnly),
                          ),
                          // Time + ticks (right-aligned by Column's crossAxisAlignment)
                          Padding(
                            padding: isMediaOnly
                                ? EdgeInsets.zero
                                : const EdgeInsets.only(top: 3),
                            child: _TimeRow(
                              time: time,
                              isOutgoing: isOutgoing,
                              deliveryStatus: data['deliveryStatus'] as String? ?? 'pending',
                              docId: docId,
                              data: data,
                              overlayOnMedia: isMediaOnly && type == 'image',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // ── Bubble tail ──
              if (isTailMessage)
                Positioned(
                  bottom: 0,
                  left: isOutgoing ? null : -8,
                  right: isOutgoing ? -8 : null,
                  child: CustomPaint(
                    painter: _BubbleTailPainter(
                      isOutgoing: isOutgoing,
                      color: CupertinoDynamicColor.resolve(
                        isOutgoing ? _outgoingBubbleColor : _incomingBubbleColor,
                        context,
                      ),
                    ),
                    size: const Size(12, 16),
                  ),
                ),
              // ── Reactions ──
              if (reactions != null && reactions.isNotEmpty)
                Positioned(
                  bottom: -12,
                  right: isOutgoing ? 6 : null,
                  left: isOutgoing ? null : 6,
                  child: _ReactionsRow(reactions: reactions, context: context),
                ),
            ],
          ),
        ],
      ),
    );
  }

  BorderRadius _bubbleRadius(bool isOutgoing, bool isTail) {
    const r = Radius.circular(18);
    const rSmall = Radius.circular(4);
    if (isTail) {
      // Newest in cluster: sharp tail corner
      return BorderRadius.only(
        topLeft: r,
        topRight: r,
        bottomLeft: isOutgoing ? r : rSmall,
        bottomRight: isOutgoing ? rSmall : r,
      );
    }
    // Non-tail (older in cluster): uniform 18px on all sides
    return const BorderRadius.all(r);
  }

  EdgeInsets _bubblePadding(String? type, bool isMediaOnly) {
    if (type == 'image' || type == 'video') {
      return const EdgeInsets.all(3);
    }
    if (type == 'audio') {
      return const EdgeInsets.symmetric(horizontal: 10, vertical: 10);
    }
    return const EdgeInsets.fromLTRB(12, 7, 12, 7);
  }

  Widget _buildContent(BuildContext context, String? type, bool isDeleted, bool isMediaOnly) {
    if (isDeleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.nosign,
            size: 14,
            color: isOutgoing
                ? _outgoingTextColor(context).withValues(alpha: 0.55)
                : CupertinoColors.systemGrey,
          ),
          const SizedBox(width: 5),
          Text(
            'This message was deleted',
            style: TextStyle(
              fontSize: 15,
              fontStyle: FontStyle.italic,
              color: isOutgoing
                  ? _outgoingTextColor(context).withValues(alpha: 0.60)
                  : CupertinoColors.systemGrey.resolveFrom(context),
            ),
          ),
        ],
      );
    }

    final url = data['mediaUrl'] as String? ?? '';
    final isSkipped = type == 'large_file_skipped';
    final isMedia = ['image', 'video', 'audio', 'file'].contains(type);

    if (isSkipped || (isMedia && url.isEmpty)) {
      return _MissingMedia(
        text: isSkipped ? 'Media unavailable (>50 MB)' : 'Media not uploaded',
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
        return _VideoContent(
          mediaUrl: url,
          caption: data['text'] as String? ?? '',
          isOutgoing: isOutgoing,
        );
      case 'audio':
        return _AudioContent(mediaUrl: url, isOutgoing: isOutgoing);
      case 'file':
        return _FileContent(
          mediaUrl: url,
          fileName: data['fileName'] as String? ?? 'Document',
          isOutgoing: isOutgoing,
        );
      default:
        final text = data['text'] as String? ?? '';
        final linkPreview = data['linkPreview'] as Map<String, dynamic>?;
        return _TextContent(
          text: text,
          linkPreview: linkPreview,
          isOutgoing: isOutgoing,
        );
    }
  }
}

// ─────────────────────────────────────────────
//  BUBBLE TAIL PAINTER
// ─────────────────────────────────────────────
class _BubbleTailPainter extends CustomPainter {
  final bool isOutgoing;
  final Color color;
  const _BubbleTailPainter({required this.isOutgoing, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    if (isOutgoing) {
      path.moveTo(0, 0);
      path.lineTo(size.width, size.height);
      path.cubicTo(
        size.width * 0.55, size.height,
        size.width * 0.08, size.height * 0.88,
        0, size.height * 0.32,
      );
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(0, size.height);
      path.cubicTo(
        size.width * 0.45, size.height,
        size.width * 0.92, size.height * 0.88,
        size.width, size.height * 0.32,
      );
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter old) => old.color != color || old.isOutgoing != isOutgoing;
}

// ─────────────────────────────────────────────
//  TIME ROW  (time + delivery ticks)
// ─────────────────────────────────────────────
class _TimeRow extends StatelessWidget {
  final String time;
  final bool isOutgoing;
  final String deliveryStatus;
  final String docId;
  final Map<String, dynamic> data;
  final bool overlayOnMedia;

  const _TimeRow({
    required this.time,
    required this.isOutgoing,
    required this.deliveryStatus,
    required this.docId,
    required this.data,
    this.overlayOnMedia = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color timeColor;
    if (overlayOnMedia) {
      timeColor = CupertinoColors.white.withValues(alpha: 0.92);
    } else if (isOutgoing) {
      final brightness = CupertinoTheme.brightnessOf(context);
      timeColor = brightness == Brightness.dark
          ? CupertinoColors.white.withValues(alpha: 0.55)
          : const Color(0xFF3D8B45);
    } else {
      timeColor = CupertinoColors.systemGrey.resolveFrom(context);
    }

    Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          time,
          style: TextStyle(fontSize: 11, color: timeColor),
        ),
        // FIX: Delivery ticks only appear on outgoing messages.
        // Incoming messages only need the timestamp.
        if (isOutgoing) ...[
          const SizedBox(width: 3),
          _DeliveryTick(status: deliveryStatus, docId: docId, data: data),
        ],
      ],
    );

    if (overlayOnMedia) {
      row = Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: CupertinoColors.black.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(8),
        ),
        child: row,
      );
    }

    return row;
  }
}

// ─────────────────────────────────────────────
//  DELIVERY TICK
// ─────────────────────────────────────────────
class _DeliveryTick extends StatelessWidget {
  final String status;
  final String docId;
  final Map<String, dynamic> data;
  const _DeliveryTick({required this.status, required this.docId, required this.data});

  @override
  Widget build(BuildContext context) {
    final brightness = CupertinoTheme.brightnessOf(context);
    final readColor = brightness == Brightness.dark
        ? const Color(0xFF4FC3F7)
        : const Color(0xFF4A90D9);
    final mutedColor = brightness == Brightness.dark
        ? CupertinoColors.white.withValues(alpha: 0.5)
        : const Color(0xFF3D8B45);
    switch (status) {
      case 'read':
      case 'played':
        return Text('✓✓',
            style: TextStyle(
                fontSize: 12, color: readColor, fontWeight: FontWeight.w600, letterSpacing: -2));
      case 'delivered':
        return Text('✓✓',
            style: TextStyle(fontSize: 12, color: mutedColor, letterSpacing: -2));
      case 'sent':
        return Text('✓',
            style: TextStyle(fontSize: 12, color: mutedColor));
      case 'error':
        return GestureDetector(
          onTap: () {
            final type = data['type'] as String?;
            if (['image', 'video', 'file', 'audio'].contains(type)) {
              FirebaseFirestore.instance
                  .collection('outbox_media')
                  .where('localId', isEqualTo: data['localId'])
                  .limit(1)
                  .get()
                  .then((s) {
                if (s.docs.isNotEmpty) s.docs.first.reference.update({'status': 'pending'});
              });
            } else {
              FirebaseFirestore.instance
                  .collection('outbox')
                  .where('localId', isEqualTo: data['localId'])
                  .limit(1)
                  .get()
                  .then((s) {
                if (s.docs.isNotEmpty) s.docs.first.reference.update({'status': 'pending'});
              });
            }
            FirebaseFirestore.instance
                .collection('messages')
                .doc(docId)
                .update({'deliveryStatus': 'pending'});
          },
          child: const Icon(CupertinoIcons.exclamationmark_circle,
              color: CupertinoColors.systemRed, size: 14),
        );
      default: // pending
        return Text('✓',
            style: TextStyle(
                fontSize: 12,
                color: mutedColor.withValues(alpha: 0.6)));
    }
  }
}

// ─────────────────────────────────────────────
//  REACTIONS ROW
// ─────────────────────────────────────────────
class _ReactionsRow extends StatelessWidget {
  final List<dynamic> reactions;
  final BuildContext context;
  const _ReactionsRow({required this.reactions, required this.context});

  @override
  Widget build(BuildContext context) {
    // Deduplicate by emoji
    final Map<String, int> counts = {};
    for (final r in reactions) {
      if (r is Map) {
        final emoji = r['emoji'] as String? ?? '';
        if (emoji.isNotEmpty) counts[emoji] = (counts[emoji] ?? 0) + 1;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CupertinoColors.separator.resolveFrom(context),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: 0.10),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: counts.entries.take(5).map((e) {
          return Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.key, style: const TextStyle(fontSize: 13)),
                if (e.value > 1) ...[
                  const SizedBox(width: 2),
                  Text('${e.value}',
                      style: const TextStyle(fontSize: 11, color: CupertinoColors.systemGrey)),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  REPLY PREVIEW INSIDE BUBBLE
// ─────────────────────────────────────────────
class _ReplyPreviewInBubble extends StatelessWidget {
  final Map<String, dynamic> replyTo;
  final bool isOutgoing;
  const _ReplyPreviewInBubble({required this.replyTo, required this.isOutgoing});

  @override
  Widget build(BuildContext context) {
    final quotedText = replyTo['text'] as String? ?? '';
    final quotedAuthor = replyTo['author'] as String? ?? '';
    // FIX: Previously, any author that was all digits was assumed to be "You".
    // In group chats, unsaved contacts also appear as raw numbers.
    // Now we check against kOwnJid explicitly.
    final ownPhone = kOwnJid.split('@').first;
    final isOwnMessage = quotedAuthor == kOwnJid ||
        quotedAuthor == ownPhone ||
        quotedAuthor.isEmpty; // empty author in outgoing replies = self
    final displayAuthor = isOwnMessage ? 'You' : quotedAuthor;
    final mediaUrl = replyTo['mediaUrl'] as String?;
    final mediaType = replyTo['type'] as String?;

    final previewText = quotedText.isNotEmpty
        ? quotedText
        : mediaType == 'image'
            ? '📷 Photo'
            : mediaType == 'video'
                ? '🎬 Video'
                : mediaType == 'audio'
                    ? '🎤 Voice message'
                    : '📎 Attachment';

    final accentColor = const Color(0xFF4A90D9);
    final bgColor = isOutgoing
        ? const Color(0x22000000)
        : CupertinoColors.systemGrey6.resolveFrom(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: accentColor, width: 3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayAuthor,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    previewText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isOutgoing
                          ? _outgoingTextColor(context).withValues(alpha: 0.70)
                          : CupertinoColors.secondaryLabel.resolveFrom(context),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (mediaUrl != null && mediaUrl.isNotEmpty) ...[
              const SizedBox(width: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: mediaUrl,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 40,
                    height: 40,
                    color: CupertinoColors.systemGrey5,
                    child: const Icon(CupertinoIcons.photo, size: 18, color: CupertinoColors.systemGrey),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  REPLY BANNER (above input bar)
// ─────────────────────────────────────────────
class _ReplyBanner extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onCancel;
  const _ReplyBanner({required this.data, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final text = data['text'] as String? ?? '';
    final mediaUrl = data['mediaUrl'] as String?;
    final type = data['type'] as String?;
    final author = data['senderName'] as String? ?? data['from'] as String? ?? '';
    // FIX: Use kOwnJid to identify self, not a regex number check (same as _ReplyPreviewInBubble)
    final ownPhone = kOwnJid.split('@').first;
    final isOwnMessage = author.isEmpty || author == kOwnJid || author == ownPhone || author == 'me';
    final displayAuthor = isOwnMessage ? 'You' : author;

    final previewText = text.isNotEmpty
        ? text
        : type == 'image'
            ? '📷 Photo'
            : type == 'video'
                ? '🎬 Video'
                : type == 'audio'
                    ? '🎤 Voice message'
                    : '📎 Attachment';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.33,
          ),
        ),
      ),
      child: Row(
        children: [
          // Left accent — animates width from 0 → 3px
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 3),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            builder: (_, w, __) => Container(
              width: w,
              height: 40,
              decoration: BoxDecoration(
                color: CupertinoColors.systemBlue,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayAuthor,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.systemBlue,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ],
            ),
          ),
          // Thumbnail
          if (mediaUrl != null && mediaUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: mediaUrl,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          // Cancel
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minSize: 36,
            onPressed: onCancel,
            child: Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 20,
              color: CupertinoColors.systemGrey.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  CONTEXT MENU ITEM
// ─────────────────────────────────────────────
class _ContextMenuItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;
  const _ContextMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });
  @override
  State<_ContextMenuItem> createState() => _ContextMenuItemState();
}

class _ContextMenuItemState extends State<_ContextMenuItem> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.isDestructive
        ? CupertinoColors.systemRed
        : CupertinoColors.label.resolveFrom(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        color: _pressed
            ? CupertinoColors.systemGrey5.resolveFrom(context)
            : CupertinoColors.systemBackground.resolveFrom(context),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(fontSize: 17, color: color),
              ),
            ),
            Icon(widget.icon, size: 20, color: color),
          ],
        ),
      ),
    );
  }
}

class _ContextMenuDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.33,
      color: CupertinoColors.separator.resolveFrom(context),
      margin: const EdgeInsets.only(left: 16),
    );
  }
}

// ─────────────────────────────────────────────
//  NAV PRESSABLE PILL (Telegram-style with press scale)
// ─────────────────────────────────────────────
class _NavPressablePill extends StatefulWidget {
  final double height;
  final double radius;
  final Color color;
  final VoidCallback onTap;
  final Widget child;
  const _NavPressablePill({
    required this.height,
    required this.radius,
    required this.color,
    required this.onTap,
    required this.child,
  });
  @override
  State<_NavPressablePill> createState() => _NavPressablePillState();
}

class _NavPressablePillState extends State<_NavPressablePill> {
  double _scale = 1.0;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.92),
      onTapUp: (_) { setState(() => _scale = 1.0); widget.onTap(); },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: widget.height,
              constraints: BoxConstraints(minWidth: widget.height),
              padding: EdgeInsets.symmetric(horizontal: widget.radius * 0.5),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(widget.radius),
              ),
              alignment: Alignment.center,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  SCROLL TO BOTTOM BUTTON
// ─────────────────────────────────────────────
class _ScrollToBottomButton extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onTap;
  const _ScrollToBottomButton({required this.unreadCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
               child: Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(0.5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      CupertinoColors.white.withValues(alpha: 0.6),
                      CupertinoColors.white.withValues(alpha: 0.05),
                      CupertinoColors.white.withValues(alpha: 0.02),
                      CupertinoColors.white.withValues(alpha: 0.3),
                    ],
                    stops: const [0.0, 0.3, 0.7, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: CupertinoColors.black.withValues(alpha: 0.12),
                      blurRadius: 20,
                      spreadRadius: -5,
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemBackground.resolveFrom(context).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    CupertinoIcons.chevron_down,
                    size: 22,
                    color: CupertinoColors.systemBlue.resolveFrom(context),
                  ),
                ),
              ),
            ),
          ),
          if (unreadCount > 0)
            Positioned(
              top: -4,
              right: -2,
              child: Builder(
                builder: (context) {
                  final text = unreadCount > 99 ? '99+' : '$unreadCount';
                  final isWide = text.length >= 2;
                  return Container(
                    constraints: BoxConstraints(
                      minWidth: isWide ? 18.0 + 10.0 : 18.0,
                      minHeight: 18.0,
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 5 : 0,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemBlue,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: CupertinoColors.white,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  PINNED PROGRESS BAR (left side of banner)
// ─────────────────────────────────────────────
class _PinnedProgressBar extends StatelessWidget {
  final int total;
  // FIX: highlight the currently active pin segment
  final int activeIndex;
  const _PinnedProgressBar({required this.total, required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 2,
      height: 30,
      child: Column(
        children: List.generate(total.clamp(1, 5), (i) {
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: i < total - 1 ? 3 : 0),
              decoration: BoxDecoration(
                color: i == activeIndex
                    ? CupertinoColors.systemBlue
                    : CupertinoColors.systemBlue.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  INPUT ICON BUTTON
// ─────────────────────────────────────────────
class _InputIconButton extends StatefulWidget {
  final String assetPath;
  final VoidCallback onTap;
  const _InputIconButton({required this.assetPath, required this.onTap});
  @override
  State<_InputIconButton> createState() => _InputIconButtonState();
}

class _InputIconButtonState extends State<_InputIconButton> {
  double _scale = 1.0;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.88),
      onTapUp: (_) { setState(() => _scale = 1.0); widget.onTap(); },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey5.resolveFrom(context),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Image.asset(
              widget.assetPath,
              width: 20,
              height: 20,
              color: CupertinoColors.systemGrey.resolveFrom(context),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  SEND BUTTON
// ─────────────────────────────────────────────
class _SendButton extends StatefulWidget {
  final VoidCallback onTap;
  const _SendButton({super.key, required this.onTap});
  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  double _scale = 1.0;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.88),
      onTapUp: (_) { setState(() => _scale = 1.0); HapticFeedback.selectionClick(); widget.onTap(); },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: CupertinoColors.systemBlue,
            shape: BoxShape.circle,
          ),
          child: const Icon(CupertinoIcons.arrow_up, color: CupertinoColors.white, size: 22),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  MIC BUTTON
// ─────────────────────────────────────────────
class _MicButton extends StatelessWidget {
  const _MicButton({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: const BoxDecoration(
        color: CupertinoColors.systemBlue,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Image.asset(
          'assets/Images.xcassets/Chat/Input/Text/IconMicrophone.imageset/ModernConversationMicButton@3x.png',
          width: 20,
          height: 20,
          color: CupertinoColors.white,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  DATE CHIP (sticky-style floating pill)
// ─────────────────────────────────────────────
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    if (diff < 365) return '${d.day} ${months[d.month - 1]}';
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(
                  const CupertinoDynamicColor.withBrightness(
                    color: Color(0xCCF2F2F6),
                    darkColor: Color(0xCC1C1C1E),
                  ),
                  context,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _formatDate(date),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  TEXT CONTENT  (with link preview)
// ─────────────────────────────────────────────
class _TextContent extends StatelessWidget {
  final String text;
  final Map<String, dynamic>? linkPreview;
  final bool isOutgoing;
  const _TextContent({required this.text, required this.linkPreview, required this.isOutgoing});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 16,
            height: 1.2,
            letterSpacing: -0.2,
            color: isOutgoing
                ? _outgoingTextColor(context)
                : CupertinoColors.label.resolveFrom(context),
          ),
        ),
        if (linkPreview != null) ...[
          const SizedBox(height: 8),
          _LinkPreviewCard(linkPreview: linkPreview!, isOutgoing: isOutgoing),
        ],
      ],
    );
  }
}

class _LinkPreviewCard extends StatelessWidget {
  final Map<String, dynamic> linkPreview;
  final bool isOutgoing;
  const _LinkPreviewCard({required this.linkPreview, required this.isOutgoing});

  @override
  Widget build(BuildContext context) {
    final img = linkPreview['image'] as String? ?? '';
    final title = linkPreview['title'] as String? ?? '';
    final desc = linkPreview['description'] as String? ?? '';
    final url = linkPreview['url'] as String? ?? '';

    return GestureDetector(
      onTap: () {
        if (url.isNotEmpty) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isOutgoing
              ? CupertinoColors.black.withValues(alpha: 0.15)
              : CupertinoColors.systemGrey6.resolveFrom(context),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(
              color: isOutgoing ? const Color(0xFF4A90D9) : CupertinoColors.systemBlue,
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (img.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                child: CachedNetworkImage(
                  imageUrl: img,
                  height: 110,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isNotEmpty)
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isOutgoing
                            ? _outgoingTextColor(context)
                            : CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isOutgoing
                            ? _outgoingTextColor(context).withValues(alpha: 0.65)
                            : CupertinoColors.systemGrey.resolveFrom(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  MISSING MEDIA
// ─────────────────────────────────────────────
class _MissingMedia extends StatelessWidget {
  final String text;
  final bool isOutgoing;
  const _MissingMedia({required this.text, required this.isOutgoing});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: isOutgoing
            ? CupertinoColors.black.withValues(alpha: 0.15)
            : CupertinoColors.systemGrey5.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle,
            size: 24,
            color: isOutgoing
                ? _outgoingTextColor(context).withValues(alpha: 0.65)
                : CupertinoColors.systemGrey.resolveFrom(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: isOutgoing
                    ? _outgoingTextColor(context).withValues(alpha: 0.80)
                    : CupertinoColors.systemGrey.resolveFrom(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  IMAGE CONTENT
// ─────────────────────────────────────────────
class _ImageContent extends StatelessWidget {
  final String mediaUrl;
  final String caption;
  final bool isOutgoing;
  const _ImageContent({required this.mediaUrl, required this.caption, required this.isOutgoing});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute(builder: (_) => _MediaViewerPage(imageUrl: mediaUrl)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260, maxHeight: 320, minHeight: 120),
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: mediaUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    placeholder: (_, __) => const SizedBox(
                      height: 180,
                      child: Center(child: CupertinoActivityIndicator()),
                    ),
                    errorWidget: (_, __, ___) => SizedBox(
                      height: 180,
                      child: Center(
                        child: Icon(CupertinoIcons.photo,
                            size: 40,
                            color: isOutgoing
                                ? CupertinoColors.white.withValues(alpha: 0.6)
                                : CupertinoColors.systemGrey),
                      ),
                    ),
                  ),
                  // FIX: The time overlay was an empty Container with no child — nothing rendered.
                  // Time is already rendered by _TimeRow via overlayOnMedia=true, so just remove this dead widget.
                  // (The _TimeRow with overlayOnMedia wraps time+ticks in a dark pill automatically)
                ],
              ),
            ),
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              caption,
              style: TextStyle(
                fontSize: 15,
                color: isOutgoing
                    ? CupertinoColors.white
                    : CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  VIDEO CONTENT
// ─────────────────────────────────────────────
class _VideoContent extends StatelessWidget {
  final String mediaUrl;
  final String caption;
  final bool isOutgoing;
  const _VideoContent({required this.mediaUrl, required this.caption, required this.isOutgoing});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute(builder: (_) => _VideoPlayerPage(videoUrl: mediaUrl)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 240,
              height: 170,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: const Color(0xFF1A1A1A)),
                  // Play icon
                  Center(
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: CupertinoColors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                        border: Border.all(color: CupertinoColors.white.withValues(alpha: 0.8), width: 2),
                      ),
                      child: const Icon(
                        CupertinoIcons.play_fill,
                        color: CupertinoColors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              caption,
              style: TextStyle(
                fontSize: 15,
                color: isOutgoing
                    ? CupertinoColors.white
                    : CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  AUDIO / VOICE MESSAGE  (with waveform)
// ─────────────────────────────────────────────
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
  bool _loading = false;

  // Random waveform bars (seeded to be consistent per URL)
  late final List<double> _bars;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(widget.mediaUrl.hashCode);
    _bars = List.generate(30, (_) => 0.2 + rng.nextDouble() * 0.8);

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
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player!.pause();
      return;
    }
    if (_player!.processingState == ProcessingState.idle) {
      setState(() => _loading = true);
      await _player!.setUrl(widget.mediaUrl);
      setState(() => _loading = false);
    }
    await _player!.play();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final brightness = CupertinoTheme.brightnessOf(context);
    final activeColor = widget.isOutgoing
        ? (brightness == Brightness.dark ? const Color(0xFF4FC3F7) : const Color(0xFF3D8B45))
        : CupertinoColors.systemBlue;
    final inactiveColor = widget.isOutgoing
        ? (brightness == Brightness.dark
            ? CupertinoColors.white.withValues(alpha: 0.30)
            : const Color(0xFF3D8B45).withValues(alpha: 0.28))
        : CupertinoColors.systemGrey3.resolveFrom(context);

    return SizedBox(
      width: 240,
      child: Row(
        children: [
          // Play/pause
          GestureDetector(
            onTap: _togglePlay,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _loading
                  ? SizedBox(
                      width: 40,
                      height: 40,
                      child: CupertinoActivityIndicator(color: activeColor),
                    )
                  : Icon(
                      _isPlaying ? CupertinoIcons.pause_circle_fill : CupertinoIcons.play_circle_fill,
                      key: ValueKey(_isPlaying),
                      size: 40,
                      color: activeColor,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Waveform
                SizedBox(
                  height: 28,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: _bars.asMap().entries.map((e) {
                      final barProgress = e.key / _bars.length;
                      final isActive = barProgress <= progress;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 50),
                            decoration: BoxDecoration(
                              color: isActive ? activeColor : inactiveColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            height: 28 * e.value,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _isPlaying || _position > Duration.zero
                      ? _fmt(_position)
                      : _fmt(_duration),
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.isOutgoing
                        ? activeColor.withValues(alpha: 0.75)
                        : CupertinoColors.systemGrey.resolveFrom(context),
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

// ─────────────────────────────────────────────
//  FILE / DOCUMENT
// ─────────────────────────────────────────────
class _FileContent extends StatelessWidget {
  final String mediaUrl;
  final String fileName;
  final bool isOutgoing;
  const _FileContent({required this.mediaUrl, required this.fileName, required this.isOutgoing});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (mediaUrl.isNotEmpty) {
          launchUrl(Uri.parse(mediaUrl), mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isOutgoing
              ? CupertinoColors.black.withValues(alpha: 0.12)
              : CupertinoColors.systemGrey5.resolveFrom(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isOutgoing
                    ? const Color(0xFF3D8B45).withValues(alpha: 0.22)
                    : CupertinoColors.systemBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                CupertinoIcons.doc_fill,
                size: 24,
                color: isOutgoing ? const Color(0xFF3D8B45) : CupertinoColors.systemBlue,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isOutgoing
                          ? _outgoingTextColor(context)
                          : CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to open',
                    style: TextStyle(
                      fontSize: 12,
                      color: isOutgoing
                          ? _outgoingTextColor(context).withValues(alpha: 0.55)
                          : CupertinoColors.systemGrey.resolveFrom(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  TYPING INDICATOR
// ─────────────────────────────────────────────
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (_) => AnimationController(vsync: this, duration: const Duration(milliseconds: 500)),
    );
    _animations = _controllers
        .map((c) => Tween(begin: 0.0, end: -5.0)
            .animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)))
        .toList();
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 160), () {
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
      children: List.generate(
        3,
        (i) => AnimatedBuilder(
          animation: _animations[i],
          builder: (_, __) => Transform.translate(
            offset: Offset(0, _animations[i].value),
            child: Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey.resolveFrom(context),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  PRESENCE SUBTITLE  (uses shared stream)
// ─────────────────────────────────────────────
class _PresenceSubtitle extends StatelessWidget {
  final Stream<DocumentSnapshot> stream;
  final String ownJid;
  const _PresenceSubtitle({required this.stream, required this.ownJid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
        final data = snapshot.data!.data() as Map<String, dynamic>;
        final presence = data['presence'] as String? ?? 'unavailable';
        final typingSource = data['typingSource'] as String?;
        final isTyping = presence == 'composing' && typingSource == ownJid;
        final isRecording = presence == 'recording' && typingSource == ownJid;

        String text = '';
        Color color = CupertinoColors.systemGrey;
        if (isTyping) { text = 'typing…'; color = CupertinoColors.systemBlue; }
        else if (isRecording) { text = 'recording audio…'; color = CupertinoColors.systemGreen; }
        else if (presence == 'available') { text = 'online'; color = CupertinoColors.systemBlue; }

        if (text.isEmpty) return const SizedBox.shrink();
        return Text(
          text,
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w400, letterSpacing: -0.1),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
//  PROFILE VIEWER
// ─────────────────────────────────────────────
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

// ─────────────────────────────────────────────
//  FULL-SCREEN IMAGE VIEWER
// ─────────────────────────────────────────────
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

// ─────────────────────────────────────────────
//  VIDEO PLAYER PAGE
// ─────────────────────────────────────────────
class _VideoPlayerPage extends StatefulWidget {
  final String videoUrl;
  const _VideoPlayerPage({required this.videoUrl});

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _controller.play();
          // FIX: Auto-hide controls after playback starts
          _scheduleHideControls();
        }
      });
  }

  // FIX: Auto-hide controls after 3 seconds of inactivity (standard video player UX)
  void _scheduleHideControls() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    // FIX: Re-schedule auto-hide each time controls are shown
    if (_showControls) _scheduleHideControls();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: _showControls
          ? const CupertinoNavigationBar(
              backgroundColor: CupertinoColors.black,
            )
          : null,
      child: GestureDetector(
        onTap: _toggleControls,
        child: Container(
          color: CupertinoColors.black,
          child: Center(
            child: _initialized
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      ),
                      // Controls overlay
                      AnimatedOpacity(
                        opacity: _showControls ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _controller.value.isPlaying
                                  ? _controller.pause()
                                  : _controller.play();
                            });
                          },
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: CupertinoColors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _controller.value.isPlaying
                                  ? CupertinoIcons.pause_fill
                                  : CupertinoIcons.play_fill,
                              color: CupertinoColors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : const CupertinoActivityIndicator(color: CupertinoColors.white, radius: 16),
          ),
        ),
      ),
    );
  }
}