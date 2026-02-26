import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class StatusScreen extends StatelessWidget {
  const StatusScreen({super.key});

  static Widget create(BuildContext context) => const StatusScreen();

  Future<void> _pickAndUploadStory(BuildContext context) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;

    try {
      final File file = File(image.path);
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference storageRef =
          FirebaseStorage.instance.ref().child('stories/$fileName');

      // Upload file to Firebase Storage
      final UploadTask uploadTask = storageRef.putFile(file);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      // Create document in Firestore
      await FirebaseFirestore.instance.collection('stories').add({
        'url': downloadUrl,
        'senderName': 'Ankit', // Logic to get current user name could be added here
        'senderId': 'user_ankit_123', // Logic to get current user ID
        'timestamp': FieldValue.serverTimestamp(),
        'caption': '', // Caption can be added via a custom UI if needed
        'type': 'image',
      });

      if (context.mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Success'),
            content: const Text('Story uploaded successfully!'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text('Failed to upload story: $e'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Status'),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _pickAndUploadStory(context),
              child: const Icon(
                CupertinoIcons.camera,
                color: CupertinoColors.systemBlue,
              ),
            ),
          ),
          // Horizontal status ring list — streamed from Firestore stories
          SliverToBoxAdapter(
            child: _StatusRingStrip(),
          ),
          // Divider
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'RECENT UPDATES',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.systemGrey,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          // Recent updates list from Firestore stories
          SliverToBoxAdapter(
            child: _RecentStories(),
          ),
        ],
      ),
    );
  }
}

/// Horizontal scrolling story ring strip — reads from 'stories' collection
class _StatusRingStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('stories')
            .where('timestamp',
                isGreaterThan: Timestamp.fromDate(
                    DateTime.now().subtract(const Duration(hours: 24))))
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          // Always show "My Status" as the first item
          final List<Map<String, dynamic>> storyUsers = [];

          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            // Group stories by senderName, keep unique senders
            final Set<String> seenSenders = {};
            for (final doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final senderName = data['senderName'] as String? ?? 'Unknown';
              if (!seenSenders.contains(senderName)) {
                seenSenders.add(senderName);
                storyUsers.add(data);
              }
            }
          }

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: 1 + storyUsers.length, // +1 for My Status
            itemBuilder: (context, index) {
              if (index == 0) {
                // My Status
                return _StatusRingAvatar(
                  name: 'My Status',
                  letter: 'A',
                  isMyStatus: true,
                  seen: true,
                );
              }

              final data = storyUsers[index - 1];
              final senderName = data['senderName'] as String? ?? 'Unknown';
              final letter = senderName.isNotEmpty
                  ? senderName[0].toUpperCase()
                  : '?';

              return _StatusRingAvatar(
                name: senderName,
                letter: data['url'] as String? ?? letter,
                isMyStatus: false,
                seen: false, // Treat all as unseen (green ring)
              );
            },
          );
        },
      ),
    );
  }
}

class _StatusRingAvatar extends StatelessWidget {
  final String name;
  final String letter;
  final bool isMyStatus;
  final bool seen;

  const _StatusRingAvatar({
    required this.name,
    required this.letter,
    required this.isMyStatus,
    required this.seen,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: (seen || isMyStatus)
                      ? LinearGradient(
                          colors: [
                            CupertinoColors.systemGrey3.withValues(alpha: 0.5),
                            CupertinoColors.systemGrey4.withValues(alpha: 0.5),
                          ],
                        )
                      : const LinearGradient(
                          colors: [
                            Color(0xFF25D366),
                            Color(0xFF128C7E),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                ),
                padding: const EdgeInsets.all(2.5),
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: CupertinoColors.white,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      image: !isMyStatus && name != 'My Status'
                          ? DecorationImage(
                              image: NetworkImage(letter), // Passing URL as letter for now
                              fit: BoxFit.cover,
                            )
                          : null,
                      gradient: isMyStatus || name == 'My Status'
                          ? LinearGradient(
                              colors: [
                                CupertinoColors.systemGrey.withValues(alpha: 0.3),
                                CupertinoColors.systemGrey2.withValues(alpha: 0.5),
                              ],
                            )
                          : null,
                    ),
                    child: (isMyStatus || name == 'My Status')
                        ? Center(
                            child: Text(
                              letter,
                              style: const TextStyle(
                                color: CupertinoColors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              if (isMyStatus)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemBlue,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: CupertinoColors.white,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      CupertinoIcons.add,
                      color: CupertinoColors.white,
                      size: 14,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 64,
            child: Text(
              name,
              style: const TextStyle(
                  fontSize: 11.5, color: CupertinoColors.black),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical list of recent story updates from Firestore
class _RecentStories extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('stories')
          .where('timestamp',
              isGreaterThan: Timestamp.fromDate(
                  DateTime.now().subtract(const Duration(hours: 24))))
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CupertinoActivityIndicator()),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                'No recent updates',
                style: TextStyle(
                  fontSize: 14,
                  color: CupertinoColors.systemGrey.withValues(alpha: 0.7),
                ),
              ),
            ),
          );
        }

        final docs = snapshot.data!.docs;
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final senderName = data['senderName'] as String? ?? 'Unknown';
            final caption = data['caption'] as String? ?? '';
            final type = data['type'] as String? ?? 'text';
            final letter = senderName.isNotEmpty
                ? senderName[0].toUpperCase()
                : '?';

            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: CupertinoColors.separator, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF25D366), Color(0xFF128C7E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border:
                          Border.all(color: const Color(0xFF25D366), width: 2),
                    ),
                    child: type == 'image' && data['url'] != null
                        ? ClipOval(
                            child: Image.network(
                              data['url'],
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(CupertinoIcons.photo,
                                      color: CupertinoColors.white, size: 20),
                            ),
                          )
                        : Center(
                            child: Text(
                              letter,
                              style: const TextStyle(
                                color: CupertinoColors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          senderName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: CupertinoColors.black,
                          ),
                        ),
                        if (caption.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            caption,
                            style: const TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.systemGrey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
