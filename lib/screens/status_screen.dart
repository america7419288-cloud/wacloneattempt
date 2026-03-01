import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'status_view_screen.dart';

// The user's own JID — used to identify "My Status" stories
const String kOwnJid = '919728470719@s.whatsapp.net';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  static Widget create(BuildContext context) => const StatusScreen();

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  bool _isUploadingStory = false;



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
    if (_isUploadingStory) return; // prevent double tap
    
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() => _isUploadingStory = true);
    
    // Show loading overlay
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
              Text('Uploading status...'),
            ],
          ),
        ),
      ),
    );

    try {
      final url = Uri.parse('https://api.cloudinary.com/v1_1/druwafmub/image/upload');
      final request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = 'whatsappClone'
        ..files.add(await http.MultipartFile.fromPath('file', image.path));

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

      await FirebaseFirestore.instance.collection('outbox_stories').add({
        'url': secureUrl,
        'senderName': 'Ankit',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
        'caption': '',
      });

      if (context.mounted) Navigator.of(context).pop(); // dismiss loading
      if (context.mounted) {
        _showCupertinoAlert(context, 'Success', 'Status posted successfully!');
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop(); // dismiss loading
      if (context.mounted) {
        _showCupertinoAlert(context, 'Upload Failed', e.toString());
      }
    } finally {
      if (mounted) setState(() => _isUploadingStory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('stories')
            .where('timestamp',
                isGreaterThan: Timestamp.fromDate(
                    DateTime.now().subtract(const Duration(hours: 24))))
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          // Parse stories once for both widgets
          final List<Map<String, dynamic>> otherStories = [];
          String? myLatestStoryUrl;
          String myLatestStoryType = 'image';
          final Set<String> seenSenders = {};

          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            for (final doc in snapshot.data!.docs) {
               final data = doc.data() as Map<String, dynamic>;
               final senderId = data['senderId'] as String? ?? '';
               
               if (senderId == kOwnJid) {
                 if (myLatestStoryUrl == null) {
                   myLatestStoryUrl = data['url'] as String?;
                   myLatestStoryType = data['type'] as String? ?? 'image';
                 }
               } else {
                 if (!seenSenders.contains(senderId)) {
                   seenSenders.add(senderId);
                   otherStories.add(data);
                 }
               }
            }
          }

          return CustomScrollView(
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
              // Horizontal status ring list
              SliverToBoxAdapter(
                child: _StatusRingStrip(
                  storyUsers: otherStories,
                  myLatestStoryUrl: myLatestStoryUrl,
                  myLatestStoryType: myLatestStoryType,
                ),
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
              // Recent updates list
              SliverToBoxAdapter(
                child: _RecentStories(stories: otherStories),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Horizontal scrolling story ring strip
class _StatusRingStrip extends StatelessWidget {
  final List<Map<String, dynamic>> storyUsers;
  final String? myLatestStoryUrl;
  final String myLatestStoryType;

  const _StatusRingStrip({
    required this.storyUsers,
    this.myLatestStoryUrl,
    this.myLatestStoryType = 'image',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: ListView.builder(
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
                        type: myLatestStoryType,
                      ),
                    ),
                  );
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
          final profileUrl = data['profileUrl'] as String?;
          final letter = senderName.isNotEmpty
              ? senderName[0].toUpperCase()
              : '?';

          return GestureDetector(
            onTap: () {
              final storyType = data['type'] as String? ?? 'image';
              final storyUrl = data['url'] as String? ?? '';
              // Allow text stories through (url may be empty for text type)
              if (storyUrl.isNotEmpty || storyType == 'text') {
                Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => StatusViewScreen(
                      url: storyUrl,
                      senderName: senderName,
                      senderJid: data['senderId'] as String?,
                      type: storyType,
                    ),
                  ),
                );
              }
            },
            child: _StatusRingAvatar(
              name: senderName,
              url: data['url'] as String?,
              profileUrl: profileUrl,
              letter: letter,
              isMyStatus: false,
              seen: false,
            ),
          );
        },
      ),
    );
  }
}

class _StatusRingAvatar extends StatelessWidget {
  final String name;
  final String? url;
  final String? profileUrl;
  final String letter;
  final bool isMyStatus;
  final bool seen;

  const _StatusRingAvatar({
    required this.name,
    this.url,
    this.profileUrl,
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
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CupertinoColors.systemBackground.resolveFrom(context),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      image: (profileUrl != null && profileUrl!.isNotEmpty)
                          ? DecorationImage(
                              image: NetworkImage(profileUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                      gradient: (profileUrl == null || profileUrl!.isEmpty)
                          ? LinearGradient(
                              colors: [
                                CupertinoColors.systemGrey.withValues(alpha: 0.3),
                                CupertinoColors.systemGrey2.withValues(alpha: 0.5),
                              ],
                            )
                          : null,
                    ),
                    child: (profileUrl == null || profileUrl!.isEmpty)
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
              style: TextStyle(
                  fontSize: 11.5, color: CupertinoColors.label.resolveFrom(context)),
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

/// Vertical list of recent story updates — receives pre-parsed data
class _RecentStories extends StatelessWidget {
  final List<Map<String, dynamic>> stories;

  const _RecentStories({required this.stories});

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) {
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: stories.map((data) {
        final senderName = data['senderName'] as String? ?? 'Unknown';
        final profileUrl = data['profileUrl'] as String?;
        final letter = senderName.isNotEmpty
            ? senderName[0].toUpperCase()
            : '?';

        return GestureDetector(
          onTap: () {
            final storyType = data['type'] as String? ?? 'image';
            final storyUrl = data['url'] as String? ?? '';
            // Allow text stories through (url may be empty for text type)
            if (storyUrl.isNotEmpty || storyType == 'text') {
              Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => StatusViewScreen(
                    url: storyUrl,
                    senderName: senderName,
                    senderJid: data['senderId'] as String?,
                    type: storyType,
                  ),
                ),
              );
            }
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: CupertinoColors.systemBackground.resolveFrom(context),
              border: const Border(
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
                  child: (profileUrl != null && profileUrl.isNotEmpty)
                      ? ClipOval(
                          child: Image.network(
                            profileUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: Text(
                                  letter,
                                  style: const TextStyle(
                                    color: CupertinoColors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) =>
                                Center(
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
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.label.resolveFrom(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _timeAgo(data['timestamp'] as Timestamp?),
                        style: const TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.systemGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  static String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${ts.toDate().day}/${ts.toDate().month}';
  }
}
