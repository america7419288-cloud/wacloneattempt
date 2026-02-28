import 'package:flutter/cupertino.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'chat_detail_screen.dart';

class ContactPickerScreen extends StatefulWidget {
  const ContactPickerScreen({super.key});

  @override
  State<ContactPickerScreen> createState() => _ContactPickerScreenState();
}

class _ContactPickerScreenState extends State<ContactPickerScreen> {
  List<Contact> _contacts = [];
  bool _isLoading = true;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final granted = await FlutterContacts.requestPermission();
    if (!granted) {
      setState(() {
        _permissionDenied = true;
        _isLoading = false;
      });
      return;
    }

    final contacts = await FlutterContacts.getContacts(
        withProperties: true, withPhoto: true);
    setState(() {
      _contacts = contacts;
      _isLoading = false;
    });
  }

  Future<void> _selectContact(Contact contact) async {
    if (contact.phones.isEmpty) {
      _showAlert('No Phone Number', 'This contact has no phone number.');
      return;
    }

    final phone = contact.phones.first.number;
    final cleanPhone = phone.replaceAll(RegExp(r'[\s\-+()]'), '');
    final fullJid = '$cleanPhone@s.whatsapp.net'.toLowerCase();

    try {
      await FirebaseFirestore.instance.collection('address_book').add({
        'phone': cleanPhone,
        'name': contact.displayName,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          CupertinoPageRoute(
            builder: (_) => ChatDetailScreen(
              contactJid: fullJid,
              contactName: contact.displayName,
              avatarLetter: contact.displayName.isNotEmpty
                  ? contact.displayName[0].toUpperCase()
                  : '?',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showAlert('Error', e.toString());
      }
    }
  }

  void _showAlert(String title, String content) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        middle: const Text('Select Contact'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      child: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator(radius: 16));
    }

    if (_permissionDenied) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Contact permission was denied.\nPlease enable it in Settings.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: CupertinoColors.systemGrey,
            ),
          ),
        ),
      );
    }

    if (_contacts.isEmpty) {
      return const Center(
        child: Text(
          'No contacts found.',
          style: TextStyle(fontSize: 15, color: CupertinoColors.systemGrey),
        ),
      );
    }

    return ListView.builder(
      itemCount: _contacts.length,
      itemBuilder: (context, index) {
        final contact = _contacts[index];
        final phone = contact.phones.isNotEmpty
            ? contact.phones.first.number
            : 'No number';
        final cleanPhone = phone.replaceAll(RegExp(r'[\s\-+()]'), '');
        final jid = '$cleanPhone@s.whatsapp.net'.toLowerCase();
        final letter = contact.displayName.isNotEmpty
            ? contact.displayName[0].toUpperCase()
            : '?';

        return GestureDetector(
          onTap: () => _selectContact(contact),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('contacts')
                      .doc(jid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    String? networkProfileUrl;
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final data = snapshot.data!.data() as Map<String, dynamic>?;
                      networkProfileUrl = data?['profileUrl'] as String?;
                    }

                    Widget avatarWidget;
                    // Priority 1: Network Image from WhatsApp (via Firestore)
                    if (networkProfileUrl != null && networkProfileUrl.isNotEmpty) {
                      avatarWidget = ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: networkProfileUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => _buildFallback(letter),
                          errorWidget: (context, url, error) => _buildFallback(letter),
                        ),
                      );
                    } 
                    // Priority 2: Local Device Photo (as fallback)
                    else if (contact.photo != null) {
                      avatarWidget = ClipOval(
                        child: Image.memory(contact.photo!, fit: BoxFit.cover),
                      );
                    } 
                    // Priority 3: Letter Avatar
                    else {
                      avatarWidget = _buildFallback(letter);
                    }

                    return SizedBox(
                      width: 44,
                      height: 44,
                      child: avatarWidget,
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.black,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        phone,
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
      },
    );
  }
  Widget _buildFallback(String letter) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            CupertinoColors.systemGrey.withValues(alpha: 0.4),
            CupertinoColors.systemGrey2.withValues(alpha: 0.6),
          ],
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            color: CupertinoColors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
