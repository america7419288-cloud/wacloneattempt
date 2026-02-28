import 'package:flutter/cupertino.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Widget create(BuildContext context) => const SettingsScreen();

  Future<void> _syncContacts(BuildContext context) async {
    try {
      if (await FlutterContacts.requestPermission()) {
        if (context.mounted) {
          showCupertinoDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(child: CupertinoActivityIndicator(radius: 16)),
          );
        }

        final contacts = await FlutterContacts.getContacts(withProperties: true);
        final batch = FirebaseFirestore.instance.batch();
        final addressBookRef = FirebaseFirestore.instance.collection('address_book');

        for (final contact in contacts) {
          if (contact.phones.isNotEmpty) {
            final phone = contact.phones.first.number;
            // Clean phone number
            final cleanPhone = phone.replaceAll(RegExp(r'[\s\-+]'), '');
            
            final docRef = addressBookRef.doc(cleanPhone);
            batch.set(docRef, {
              'phone': cleanPhone,
              'name': contact.displayName,
            });
          }
        }

        await batch.commit();

        if (context.mounted) {
          Navigator.pop(context); // Dismiss loading
          showCupertinoDialog(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: const Text('Success'),
              content: Text('Successfully synced ${contacts.length} contacts.'),
              actions: [
                CupertinoDialogAction(
                  child: const Text('OK'),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          );
        }
      } else {
        if (context.mounted) {
          showCupertinoDialog(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: const Text('Permission Denied'),
              content: const Text('We need contact permissions to sync your address book.'),
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
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Ensure loading is dismissed on error
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text('Failed to sync contacts: $e'),
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

  Future<void> _refreshProfilePictures(BuildContext context) async {
    try {
      await FirebaseFirestore.instance.collection('commands').add({
        'type': 'REFRESH_PROFILES',
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      if (context.mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Sync Started'),
            content: const Text('The bridge is now fetching profile pictures for all your chats. This may take a minute.'),
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
            content: Text('Failed to start sync: $e'),
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
                _SettingsSection(
                  children: [
                    _SettingsTile(
                      icon: CupertinoIcons.person_3_fill,
                      iconBgColor: CupertinoColors.systemIndigo,
                      title: 'Sync Phone Contacts',
                      onPressed: () => _syncContacts(context),
                    ),
                    _SettingsTile(
                      icon: CupertinoIcons.refresh_circled_solid,
                      iconBgColor: CupertinoColors.systemOrange,
                      title: 'Refresh Profile Pictures',
                      onPressed: () => _refreshProfilePictures(context),
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
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
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
  final VoidCallback? onPressed;

  const _SettingsTile({
    required this.icon,
    required this.iconBgColor,
    required this.title,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed ?? () {},
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
