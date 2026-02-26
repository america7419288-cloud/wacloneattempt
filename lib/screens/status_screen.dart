import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'status_view_screen.dart';

class StatusScreen extends StatelessWidget {
  const StatusScreen({super.key});

  static Widget create(BuildContext context) => const StatusScreen();

  void _showCupertinoAlert(BuildContext context, String title, String content) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadStory(BuildContext context) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    try {
      // 1. Upload to Cloudinary via REST API
      final url = Uri.parse('https://api.cloudinary.com/v1_1/druwafmub/image/upload');
      final request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = 'whatsappClone'
        ..files.add(await http.MultipartFile.fromPath('file', image.path));

      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final jsonResponse = jsonDecode(responseData);
      final String secureUrl = jsonResponse['secure_url'];

      // 2. ONLY write to 'outbox_stories'
      // Do NOT write to 'stories' manually. Let the bridge handle that.
      await FirebaseFirestore.instance.collection('outbox_stories').add({
        'url': secureUrl,
        'senderName': 'Ankit',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending', // Bridge will see this and post to WhatsApp
        'caption': '',
      });

      if (context.mounted) {
        _showCupertinoAlert(context, 'Success', 'Status sent to WhatsApp!');
      }
    } catch (e) {
      if (context.mounted) {
        _showCupertinoAlert(context, 'Error', e.toString());
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
            .collection('outbox_stories')
            .where('timestamp',
                isGreaterThan: Timestamp.fromDate(
                    DateTime.now().subtract(const Duration(hours: 24))))
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          // Always show "My Status" as the first item
          final List<Map<String, dynamic>> storyUsers = [];
          String? myLatestStoryUrl;

          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            // Group stories by senderName, keep unique senders
            final Set<String> seenSenders = {};
            for (final doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final senderId = data['senderId'] as String? ?? '';
              final senderName = data['senderName'] as String? ?? 'Unknown';

              if (senderId == 'user_ankit_123') {
                myLatestStoryUrl ??= data['url'] as String?;
              } else {
                if (!seenSenders.contains(senderName)) {
                  seenSenders.add(senderName);
                  storyUsers.add(data);
                }
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
                return GestureDetector(
                  onTap: () {
                    if (myLatestStoryUrl != null && myLatestStoryUrl!.isNotEmpty) {
                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => StatusViewScreen(
                            url: myLatestStoryUrl!,
                            senderName: 'My Status',
                          ),
                        ),
                      );
                    } else {
                      // Trigger upload if 'My Status' has no story
                      // We need to access the _pickAndUploadStory from the parent,
                      // Since it's stateless here we might just notify parent, or 
                      // let user use the top camera icon for now to avoid refactor.
                    }
                  },
                  child: _StatusRingAvatar(
                    name: 'My Status',
                    url: myLatestStoryUrl,
                    letter: 'A',
                    isMyStatus: true,
                    seen: true,
                  ),
                );
              }

              final data = storyUsers[index - 1];
              final senderName = data['senderName'] as String? ?? 'Unknown';
              final letter = senderName.isNotEmpty
                  ? senderName[0].toUpperCase()
                  : '?';

              return GestureDetector(
                onTap: () {
                  if (data['url'] != null && data['url'].toString().isNotEmpty) {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => StatusViewScreen(
                          url: data['url'],
                          senderName: senderName,
                        ),
                      ),
                    );
                  }
                },
                child: _StatusRingAvatar(
                  name: senderName,
                  url: data['url'] as String?,
                  letter: letter,
                  isMyStatus: false,
                  seen: false, // Treat all as unseen (green ring)
                ),
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
  final String? url;
  final String letter;
  final bool isMyStatus;
  final bool seen;

  const _StatusRingAvatar({
    required this.name,
    this.url,
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
                      image: url != null && url!.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(url!),
                              fit: BoxFit.cover,
                            )
                          : null,
                      gradient: url == null || url!.isEmpty
                          ? LinearGradient(
                              colors: [
                                CupertinoColors.systemGrey.withValues(alpha: 0.3),
                                CupertinoColors.systemGrey2.withValues(alpha: 0.5),
                              ],
                            )
                          : null,
                    ),
                    child: (url == null || url!.isEmpty)
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
          .collection('outbox_stories')
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

        final List<Map<String, dynamic>> uniqueOtherStories = [];
        final Set<String> seenSenders = {};
        
        for (final doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final senderId = data['senderId'] as String? ?? '';
          final senderName = data['senderName'] as String? ?? 'Unknown';

          if (senderId != 'user_ankit_123') {
            if (!seenSenders.contains(senderName)) {
              seenSenders.add(senderName);
              uniqueOtherStories.add(data);
            }
          }
        }

        if (uniqueOtherStories.isEmpty) {
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

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: uniqueOtherStories.length,
          itemBuilder: (context, index) {
            final data = uniqueOtherStories[index];
            final senderName = data['senderName'] as String? ?? 'Unknown';
            final caption = data['caption'] as String? ?? '';
            final type = data['type'] as String? ?? 'text';
            final letter = senderName.isNotEmpty
                ? senderName[0].toUpperCase()
                : '?';

            return GestureDetector(
              onTap: () {
                if (data['url'] != null && data['url'].toString().isNotEmpty) {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => StatusViewScreen(
                        url: data['url'],
                        senderName: senderName,
                      ),
                    ),
                  );
                }
              },
              child: Container(
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
                      child: type == 'image' && data['url'] != null && data['url'].toString().isNotEmpty
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
              ),
            );
          },
        );
      },
    );
  }
}
