import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'status_screen.dart';
import 'calls_screen.dart';
import 'chats_list_screen.dart';
import 'settings_screen.dart';
import 'chat_detail_screen.dart' show TelegramPageRoute;

// ─────────────────────────────────────────────
//  HOME SCREEN — Floating frosted pill tab bar
// ─────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 2; // Start on Chats
  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    4,
    (_) => GlobalKey<NavigatorState>(),
  );

  // Track whether a detail screen is pushed in any tab
  bool _hideTabBar = false;

  // Route observers per tab to detect push/pop
  late final List<_TabRouteObserver> _routeObservers;

  @override
  void initState() {
    super.initState();
    _routeObservers = List.generate(4, (_) => _TabRouteObserver(
      onPush: () => _setTabBarVisibility(false),
      onPop: () => _setTabBarVisibility(true),
    ));
  }

  void _setTabBarVisibility(bool visible) {
    // Only update if the change is from the currently active tab
    if (mounted) {
      setState(() => _hideTabBar = !visible);
    }
  }

  void _onTabTap(int index) {
    HapticFeedback.selectionClick();
    if (index == _currentIndex) {
      // Pop to root if tapping the already-active tab
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return CupertinoPageScaffold(
      resizeToAvoidBottomInset: false,
      child: Stack(
        children: [
          // ── Tab bodies ──
          IndexedStack(
            index: _currentIndex,
            children: [
              _buildTabNavigator(0, const StatusScreen()),
              _buildTabNavigator(1, const CallsScreen()),
              _buildTabNavigator(2, const ChatsListScreen()),
              _buildTabNavigator(3, const SettingsScreen()),
            ],
          ),

          // ── Floating frosted pill tab bar ──
          Positioned(
            bottom: bottomPad > 0 ? bottomPad : 12,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              offset: _hideTabBar ? const Offset(0, 1.5) : Offset.zero,
              duration: const Duration(milliseconds: 300),
              curve: _hideTabBar ? Curves.easeIn : Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _hideTabBar ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Center(
                  child: _FrostedPillTabBar(
                    currentIndex: _currentIndex,
                    onTap: _onTabTap,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabNavigator(int index, Widget root) {
    return Navigator(
      key: _navigatorKeys[index],
      observers: [_routeObservers[index]],
      onGenerateRoute: (settings) => TelegramPageRoute(
        builder: (_) => root,
        settings: settings,
      ),
    );
  }
}

// ═══════════════════════════════════════════════
//  ROUTE OBSERVER — detects push/pop for hiding
// ═══════════════════════════════════════════════
class _TabRouteObserver extends NavigatorObserver {
  final VoidCallback onPush;
  final VoidCallback onPop;
  _TabRouteObserver({required this.onPush, required this.onPop});

  int _depth = 0;

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    _depth++;
    if (_depth > 1) onPush(); // Only hide when pushing beyond root
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    _depth--;
    if (_depth <= 1) onPop(); // Show when back to root
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    super.didRemove(route, previousRoute);
    _depth--;
    if (_depth <= 1) onPop();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    // Depth unchanged on replace
  }
}

// ═══════════════════════════════════════════════
//  FROSTED PILL TAB BAR
// ═══════════════════════════════════════════════
class _FrostedPillTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _FrostedPillTabBar({
    required this.currentIndex,
    required this.onTap,
  });

  static const _tabs = [
    _TabItem(icon: CupertinoIcons.radiowaves_right, activeIcon: CupertinoIcons.radiowaves_right, label: 'Status'),
    _TabItem(icon: CupertinoIcons.phone, activeIcon: CupertinoIcons.phone_fill, label: 'Calls'),
    _TabItem(icon: CupertinoIcons.chat_bubble_2, activeIcon: CupertinoIcons.chat_bubble_2_fill, label: 'Chats'),
    _TabItem(icon: CupertinoIcons.settings, activeIcon: CupertinoIcons.settings_solid, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(50),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xC01C1C1E)   // ~75% opaque dark
                : const Color(0xB8F2F2F7),  // ~72% opaque light
            borderRadius: BorderRadius.circular(50),
            border: Border.all(
              color: isDark
                  ? const Color(0x20FFFFFF)
                  : const Color(0x40FFFFFF),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_tabs.length, (i) {
              final tab = _tabs[i];
              final isActive = i == currentIndex;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                    horizontal: isActive ? 16 : 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? CupertinoColors.systemBlue.withValues(alpha: 0.15)
                        : const Color(0x00000000),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AnimatedTabIcon(
                        icon: isActive ? tab.activeIcon : tab.icon,
                        selected: isActive,
                      ),
                      // Show label only for active tab
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        child: isActive
                            ? Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Text(
                                  tab.label,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoColors.systemBlue,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _TabItem({required this.icon, required this.activeIcon, required this.label});
}

// ═══════════════════════════════════════════════
//  ANIMATED TAB ICON (spring bounce)
// ═══════════════════════════════════════════════
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
    final isActive = widget.selected;
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, __) => Transform.scale(
        scale: _scale.value,
        child: Icon(
          widget.icon,
          size: 22,
          color: isActive
              ? CupertinoColors.systemBlue
              : CupertinoColors.systemGrey,
        ),
      ),
    );
  }
}
