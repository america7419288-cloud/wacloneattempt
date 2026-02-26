import 'package:flutter/cupertino.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Widget create(BuildContext context) => const SettingsScreen();

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(
            largeTitle: Text('Settings'),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Profile header
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
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
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF007AFF),
                                Color(0xFF5856D6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              'A',
                              style: TextStyle(
                                color: CupertinoColors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Ankit',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  color: CupertinoColors.black,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Hey there! I am using WhatsApp.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: CupertinoColors.systemGrey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          CupertinoIcons.qrcode,
                          color: CupertinoColors.systemBlue,
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Settings sections
                _SettingsSection(
                  children: [
                    _SettingsTile(
                      icon: CupertinoIcons.star_fill,
                      iconBgColor: const Color(0xFFFFCC00),
                      title: 'Starred Messages',
                    ),
                    _SettingsTile(
                      icon: CupertinoIcons.device_laptop,
                      iconBgColor: CupertinoColors.systemGreen,
                      title: 'Linked Devices',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SettingsSection(
                  children: [
                    _SettingsTile(
                      icon: CupertinoIcons.lock_fill,
                      iconBgColor: CupertinoColors.systemBlue,
                      title: 'Account',
                    ),
                    _SettingsTile(
                      icon: CupertinoIcons.lock_shield_fill,
                      iconBgColor: const Color(0xFF30B0C7),
                      title: 'Privacy',
                    ),
                    _SettingsTile(
                      icon: CupertinoIcons.chat_bubble_fill,
                      iconBgColor: CupertinoColors.systemGreen,
                      title: 'Chats',
                    ),
                    _SettingsTile(
                      icon: CupertinoIcons.bell_fill,
                      iconBgColor: CupertinoColors.systemRed,
                      title: 'Notifications',
                    ),
                    _SettingsTile(
                      icon: CupertinoIcons.arrow_counterclockwise,
                      iconBgColor: CupertinoColors.systemGreen,
                      title: 'Storage and Data',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SettingsSection(
                  children: [
                    _SettingsTile(
                      icon: CupertinoIcons.question_circle_fill,
                      iconBgColor: CupertinoColors.systemBlue,
                      title: 'Help',
                    ),
                    _SettingsTile(
                      icon: CupertinoIcons.heart_fill,
                      iconBgColor: CupertinoColors.systemRed,
                      title: 'Tell a Friend',
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final List<_SettingsTile> children;

  const _SettingsSection({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 52),
                child: Container(
                  height: 0.5,
                  color: CupertinoColors.separator,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final String title;

  const _SettingsTile({
    required this.icon,
    required this.iconBgColor,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, color: CupertinoColors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  color: CupertinoColors.black,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: CupertinoColors.systemGrey3,
            ),
          ],
        ),
      ),
    );
  }
}
