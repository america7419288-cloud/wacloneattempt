import 'package:flutter/cupertino.dart';
import 'status_screen.dart';
import 'calls_screen.dart';
import 'chats_list_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        currentIndex: 2,
        activeColor: CupertinoColors.systemBlue,
        inactiveColor: CupertinoColors.systemGrey,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.radiowaves_right),
            label: 'Status',
          ),
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.phone),
            label: 'Calls',
          ),
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.chat_bubble_2_fill),
            label: 'Chats',
          ),
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings),
            label: 'Settings',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        switch (index) {
          case 0:
            return const CupertinoTabView(builder: StatusScreen.create);
          case 1:
            return const CupertinoTabView(builder: CallsScreen.create);
          case 2:
            return const CupertinoTabView(builder: ChatsListScreen.create);
          case 3:
            return const CupertinoTabView(builder: SettingsScreen.create);
          default:
            return const CupertinoTabView(builder: ChatsListScreen.create);
        }
      },
    );
  }
}
