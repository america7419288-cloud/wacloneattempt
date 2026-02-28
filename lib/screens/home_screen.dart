import 'package:flutter/cupertino.dart';
import 'status_screen.dart';
import 'calls_screen.dart';
import 'chats_list_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late CupertinoTabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = CupertinoTabController(initialIndex: 2);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      controller: _tabController,
      restorationId: 'home_tab_scaffold',
      tabBar: CupertinoTabBar(
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
            return CupertinoTabView(
              builder: (context) => const StatusScreen(),
            );
          case 1:
            return CupertinoTabView(
              builder: (context) => const CallsScreen(),
            );
          case 2:
            return CupertinoTabView(
              builder: (context) => const ChatsListScreen(),
            );
          case 3:
            return CupertinoTabView(
              builder: (context) => const SettingsScreen(),
            );
          default:
            return CupertinoTabView(
              builder: (context) => const ChatsListScreen(),
            );
        }
      },
    );
  }
}
