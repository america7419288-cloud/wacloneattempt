import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const Color _incomingBubbleColor = Color(0xFFE5E5EA);
const Color _outgoingBubbleColor = Color(0xFF34C759);

class ChatDetailScreen extends StatefulWidget {
  final String contactJid;
  final String contactName;
  final String avatarLetter;

  const ChatDetailScreen({
    super.key,
    required this.contactJid,
    required this.contactName,
    required this.avatarLetter,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    // Write to outbox collection — the Node.js bridge picks this up
    FirebaseFirestore.instance.collection('outbox').add({
      'to': widget.contactJid, // Full JID e.g. 919876543210@s.whatsapp.net
      'text': text,
      'status': 'pending', // Bridge looks for 'pending' status
      'timestamp': FieldValue.serverTimestamp(),
    });

    _textController.clear();
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
        middle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
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
            // Input bar
            _buildInputBar(),
          ],
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
            final text = data['text'] as String? ?? '';
            // index.js uses 'isMe' field (true/false)
            final isOutgoing = data['isMe'] == true;
            final timestamp = data['timestamp'] as Timestamp?;
            final timeStr = timestamp != null
                ? '${timestamp.toDate().hour.toString().padLeft(2, '0')}:${timestamp.toDate().minute.toString().padLeft(2, '0')}'
                : '';

            return _ChatBubble(
              text: text,
              time: timeStr,
              isOutgoing: isOutgoing,
            );
          },
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        border: const Border(
          top: BorderSide(color: CupertinoColors.separator, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Camera icon
          CupertinoButton(
            padding: const EdgeInsets.all(4),
            child: const Icon(
              CupertinoIcons.camera_fill,
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
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String text;
  final String time;
  final bool isOutgoing;

  const _ChatBubble({
    required this.text,
    required this.time,
    required this.isOutgoing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
            isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
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
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 15.5,
                    color: isOutgoing
                        ? CupertinoColors.white
                        : CupertinoColors.black,
                  ),
                ),
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
        ],
      ),
    );
  }
}
