import 'package:flutter/cupertino.dart';

class _CallEntry {
  final String name;
  final String letter;
  final String time;
  final bool isOutgoing;
  final bool isMissed;
  final bool isVideo;

  const _CallEntry({
    required this.name,
    required this.letter,
    required this.time,
    this.isOutgoing = true,
    this.isMissed = false,
    this.isVideo = false,
  });
}

final List<_CallEntry> _demoCalls = [
  const _CallEntry(
    name: 'Rahul',
    letter: 'R',
    time: 'Today, 10:32 AM',
    isOutgoing: true,
    isVideo: true,
  ),
  const _CallEntry(
    name: 'Mom',
    letter: 'M',
    time: 'Today, 9:15 AM',
    isOutgoing: false,
    isMissed: true,
  ),
  const _CallEntry(
    name: 'Sneha',
    letter: 'S',
    time: 'Yesterday, 8:45 PM',
    isOutgoing: true,
  ),
  const _CallEntry(
    name: 'Dad',
    letter: 'D',
    time: 'Yesterday, 7:20 PM',
    isOutgoing: false,
  ),
  const _CallEntry(
    name: 'Amit',
    letter: 'A',
    time: 'Monday, 3:10 PM',
    isOutgoing: true,
    isVideo: true,
  ),
  const _CallEntry(
    name: 'Priya',
    letter: 'P',
    time: 'Monday, 1:05 PM',
    isOutgoing: false,
    isMissed: true,
  ),
  const _CallEntry(
    name: 'College Group',
    letter: 'C',
    time: 'Sunday, 11:00 AM',
    isOutgoing: true,
    isVideo: true,
  ),
];

class CallsScreen extends StatelessWidget {
  const CallsScreen({super.key});

  static Widget create(BuildContext context) => const CallsScreen();

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(
            largeTitle: Text('Calls'),
            trailing: Icon(
              CupertinoIcons.phone_badge_plus,
              color: CupertinoColors.systemBlue,
            ),
          ),
          // Link row
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(CupertinoIcons.link,
                      size: 18, color: CupertinoColors.systemBlue),
                  SizedBox(width: 8),
                  Text(
                    'Create Call Link',
                    style: TextStyle(
                      color: CupertinoColors.systemBlue,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Section label
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Text(
                'RECENT',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.systemGrey,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          // Call list
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final call = _demoCalls[index];
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                      Container(
                        width: 48,
                        height: 48,
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
                            call.letter,
                            style: const TextStyle(
                              color: CupertinoColors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Name + direction + time
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              call.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: call.isMissed
                                    ? CupertinoColors.systemRed
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  call.isOutgoing
                                      ? CupertinoIcons.arrow_up_right
                                      : CupertinoIcons.arrow_down_left,
                                  size: 14,
                                  color: call.isMissed
                                      ? CupertinoColors.systemRed
                                      : CupertinoColors.systemGrey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  call.time,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: CupertinoColors.systemGrey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Call type icon
                      Icon(
                        call.isVideo
                            ? CupertinoIcons.video_camera
                            : CupertinoIcons.phone,
                        color: CupertinoColors.systemBlue,
                        size: 22,
                      ),
                    ],
                  ),
                );
              },
              childCount: _demoCalls.length,
            ),
          ),
        ],
      ),
    );
  }
}
