import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator, AlwaysStoppedAnimation;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_detail_screen.dart';
import 'contact_picker_screen.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  static Widget create(BuildContext context) => const ChatsListScreen();

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(
            largeTitle: Text('Chats'),
            trailing: _ComposeButton(),
          ),
          // Sync progress banner
          SliverToBoxAdapter(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('app_status')
                  .doc('sync_progress')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const SizedBox.shrink();
                }
                final data =
                    snapshot.data!.data() as Map<String, dynamic>? ?? {};
                final isSyncing = data['isSyncing'] as bool? ?? false;
                if (!isSyncing) return const SizedBox.shrink();

                final total = (data['totalMessages'] as num?)?.toInt() ?? 1;
                final processed =
                    (data['processedMessages'] as num?)?.toInt() ?? 0;
                final progress = total > 0 ? processed / total : 0.0;

                return Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey6,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: CupertinoColors.systemGrey4,
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            CupertinoIcons.arrow_2_circlepath,
                            size: 16,
                            color: CupertinoColors.systemBlue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Restoring history… $processed / $total messages',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: CupertinoColors.label,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: CupertinoColors.systemGrey5,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            CupertinoColors.systemBlue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(progress * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 11,
                          color: CupertinoColors.systemGrey,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: CupertinoSearchTextField(
                placeholder: 'Search',
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
          ),
          // Broadcast / New Group row
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  _quickAction(CupertinoIcons.antenna_radiowaves_left_right,
                      'Broadcast Lists'),
                  const SizedBox(width: 16),
                  _quickAction(CupertinoIcons.person_2, 'New Group'),
                ],
              ),
            ),
          ),
          // Real-time chat list from Firestore contacts collection
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('contacts')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.exclamationmark_triangle,
                              size: 40, color: CupertinoColors.systemRed),
                          const SizedBox(height: 12),
                          Text(
                            'Error loading chats:\n${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.systemGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CupertinoActivityIndicator()),
                  ),
                );
              }

              var docs = snapshot.data!.docs;

              // Apply search filter
              if (_searchQuery.isNotEmpty) {
                docs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = data['name'] as String? ?? '';
                  final lastMsg = data['lastMessage'] as String? ?? '';
                  return name
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase()) ||
                      lastMsg
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase());
                }).toList();
              }

              if (docs.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.chat_bubble_2,
                              size: 56,
                              color: CupertinoColors.systemGrey
                                  .withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isEmpty
                                ? 'No conversations yet'
                                : 'No matching chats',
                            style: TextStyle(
                              fontSize: 16,
                              color: CupertinoColors.systemGrey
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    // doc.id is the JID (set by index.js via db.collection('contacts').doc(jid).set(...))
                    final jid = docs[index].id;
                    final name = data['name'] as String? ?? jid.split('@')[0];
                    final lastMessage = data['lastMessage'] as String? ?? '';
                    final timestamp = data['timestamp'] as Timestamp?;
                    final avatarLetter = data['avatarLetter'] as String? ??
                        (name.isNotEmpty ? name[0].toUpperCase() : '?');
                    final profileUrl = data['profileUrl'] as String?;
                    final unreadCount = data['unreadCount'] as int? ?? 0;
                    final isGroup = data['isGroup'] == true;

                    return _ChatTile(
                      jid: jid,
                      name: name,
                      lastMessage: lastMessage,
                      timestamp: timestamp,
                      avatarLetter: avatarLetter,
                      profileUrl: profileUrl,
                      unreadCount: unreadCount,
                      isGroup: isGroup,
                    );
                  },
                  childCount: docs.length,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _quickAction(IconData icon, String label) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () {},
      child: Row(
        children: [
          Icon(icon, size: 18, color: CupertinoColors.systemBlue),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: CupertinoColors.systemBlue, fontSize: 14)),
        ],
      ),
    );
  }
}

class _ComposeButton extends StatelessWidget {
  const _ComposeButton();

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => const ContactPickerScreen(),
          ),
        );
      },
      child: const Icon(
        CupertinoIcons.square_pencil,
        color: CupertinoColors.systemBlue,
      ),
    );
  }
}

String _formatTimestamp(Timestamp? timestamp) {
  if (timestamp == null) return '';
  final dt = timestamp.toDate();
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inDays == 0) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } else if (diff.inDays == 1) {
    return 'Yesterday';
  } else if (diff.inDays < 7) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[dt.weekday - 1];
  } else {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _ChatTile extends StatelessWidget {
  final String jid;
  final String name;
  final String lastMessage;
  final Timestamp? timestamp;
  final String avatarLetter;
  final String? profileUrl;
  final int unreadCount;
  final bool isGroup;

  const _ChatTile({
    required this.jid,
    required this.name,
    required this.lastMessage,
    required this.timestamp,
    required this.avatarLetter,
    this.profileUrl,
    this.unreadCount = 0,
    this.isGroup = false,
  });

  void _showDeleteActionSheet(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext ctx) => CupertinoActionSheet(
        title: const Text('Delete Chat?'),
        message: Text('Are you sure you want to delete the chat with $name?'),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                // Delete from contacts
                await FirebaseFirestore.instance.collection('contacts').doc(jid).delete();

                // Delete associated messages in batch
                final msgs = await FirebaseFirestore.instance
                    .collection('messages')
                    .where('chatId', isEqualTo: jid)
                    .get();

                if (msgs.docs.isNotEmpty) {
                  final batch = FirebaseFirestore.instance.batch();
                  for (var doc in msgs.docs) {
                    batch.delete(doc.reference);
                  }
                  await batch.commit();
                }
              } catch (e) {
                debugPrint('Error deleting chat: $e');
              }
            },
            child: const Text('Delete Chat'),
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
  Widget build(BuildContext context) {
    final timeStr = _formatTimestamp(timestamp);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => ChatDetailScreen(
              contactJid: jid,
              contactName: name,
              avatarLetter: avatarLetter,
              profileUrl: profileUrl,
            ),
          ),
        );
      },
      onLongPress: () => _showDeleteActionSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: CupertinoColors.separator,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                children: [
                  (profileUrl != null && profileUrl!.isNotEmpty)
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: profileUrl!,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => _buildFallbackAvatar(),
                            errorWidget: (context, url, error) =>
                                _buildFallbackAvatar(),
                          ),
                        )
                      : _buildFallbackAvatar(),
                  if (isGroup)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemGreen,
                          shape: BoxShape.circle,
                          border: Border.all(color: CupertinoColors.white, width: 1.5),
                        ),
                        child: const Icon(
                          CupertinoIcons.person_2_fill,
                          size: 10,
                          color: CupertinoColors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Name + last message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    lastMessage,
                    style: const TextStyle(
                      fontSize: 14,
                      color: CupertinoColors.systemGrey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Timestamp + unread badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timeStr,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
                if (unreadCount > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGreen,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ]),
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
          avatarLetter,
          style: const TextStyle(
            color: CupertinoColors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
