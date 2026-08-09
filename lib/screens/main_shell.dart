import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../utils/constants.dart';
import 'home_screen.dart';
import 'kid_search_screen.dart';
import 'shorts_tab_screen.dart';
import 'subscriptions_screen.dart';
import 'library_screen.dart';
import 'parent_login_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const _searchTabIndex = 2;

  final List<Widget> _screens = const [
    HomeScreen(),
    ShortsTabScreen(),
    SizedBox(), // search opens as its own route, never as a tab body
    SubscriptionsScreen(),
    LibraryScreen(),
  ];

  void _onTabTapped(int index) {
    if (index == _searchTabIndex) {
      _openSearch();
      return;
    }
    setState(() => _currentIndex = index);
  }

  void _openSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const KidSearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSyncing = context.select<AppProvider, bool>((p) => p.isSyncing);

    return Scaffold(
      backgroundColor: AppColors.ytDarkBg,
      appBar: _currentIndex == 1
          ? null // Shorts tab has no app bar (full screen)
          : AppBar(
              backgroundColor: AppColors.ytDarkBg,
              elevation: 0,
              scrolledUnderElevation: 0,
              toolbarHeight: 48,
              titleSpacing: 16,
              // A hairline progress bar is all the child sees of a channel
              // sync — no blocking spinners.
              bottom: isSyncing
                  ? const PreferredSize(
                      preferredSize: Size.fromHeight(2),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: AppColors.ytRed,
                        backgroundColor: Colors.transparent,
                      ),
                    )
                  : null,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.ytRed,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.play_arrow,
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'KidTube',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search,
                      color: AppColors.white, size: 24),
                  onPressed: _openSearch,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                // Parent mode: long press profile avatar
                GestureDetector(
                  onLongPress: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const ParentLoginScreen()),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.only(right: 14),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.teal,
                      child: Text('K',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                ),
              ],
            ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 0.5,
            color: AppColors.ytBottomBarBorder,
          ),
          BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _onTabTapped,
            backgroundColor: AppColors.ytDarkBg,
            selectedItemColor: AppColors.white,
            unselectedItemColor: AppColors.ytGrey,
            type: BottomNavigationBarType.fixed,
            showSelectedLabels: true,
            showUnselectedLabels: true,
            selectedFontSize: 10,
            unselectedFontSize: 10,
            iconSize: 26,
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home_filled),
                label: 'Главная',
              ),
              BottomNavigationBarItem(
                icon: _buildShortsIcon(false),
                activeIcon: _buildShortsIcon(true),
                label: 'Shorts',
              ),
              // Replaces YouTube's upload button, which does nothing useful in
              // a kids' app.
              const BottomNavigationBarItem(
                icon: Icon(Icons.search),
                label: 'Поиск',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.subscriptions_outlined),
                activeIcon: Icon(Icons.subscriptions),
                label: 'Каналы',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: 'Я',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShortsIcon(bool active) {
    final color = active ? AppColors.white : AppColors.ytGrey;
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 18,
            height: 22,
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 2),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          Icon(Icons.play_arrow, size: 13, color: color),
        ],
      ),
    );
  }
}
