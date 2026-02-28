import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
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
  int _currentIndex = 2;

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
        onTap: (index) {
          HapticFeedback.selectionClick();
          setState(() => _currentIndex = index);
        },
        items: [
          BottomNavigationBarItem(
            icon: _AnimatedTabIcon(icon: CupertinoIcons.radiowaves_right, selected: _currentIndex == 0),
            label: 'Status',
          ),
          BottomNavigationBarItem(
            icon: _AnimatedTabIcon(icon: CupertinoIcons.phone, selected: _currentIndex == 1),
            label: 'Calls',
          ),
          BottomNavigationBarItem(
            icon: _AnimatedTabIcon(icon: CupertinoIcons.chat_bubble_2_fill, selected: _currentIndex == 2),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: _AnimatedTabIcon(icon: CupertinoIcons.settings, selected: _currentIndex == 3),
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

class _AnimatedTabIcon extends StatefulWidget {
  final IconData icon;
  final bool selected;
  const _AnimatedTabIcon({required this.icon, required this.selected});
  @override
  State<_AnimatedTabIcon> createState() => _AnimatedTabIconState();
}

class _AnimatedTabIconState extends State<_AnimatedTabIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scale = Tween(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _c, curve: Curves.elasticOut),
    );
    if (widget.selected) _c.forward();
  }

  @override
  void didUpdateWidget(_AnimatedTabIcon old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) _c.forward(from: 0);
    if (!widget.selected && old.selected) _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, __) => Transform.scale(
        scale: _scale.value,
        child: Icon(widget.icon, size: 24),
      ),
    );
  }
}
