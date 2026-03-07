import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  void _handleSwipe(DragEndDetails details) {
    // Determine the swipe velocity
    final double velocity = details.primaryVelocity ?? 0.0;

    // We only care about noticeable swipes
    if (velocity.abs() < 300) return;

    final int currentIndex = navigationShell.currentIndex;

    if (velocity > 0) {
      // Swiped right -> go to previous tab (left)
      if (currentIndex > 0) {
        _goBranch(currentIndex - 1);
      }
    } else {
      // Swiped left -> go to next tab (right)
      if (currentIndex < 2) {
        // 2 is the max index (Settings)
        _goBranch(currentIndex + 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: _handleSwipe,
      behavior: HitTestBehavior.translucent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 600) {
            // Use NavigationBar strictly for mobile layout
            return Scaffold(
              body: navigationShell,
              bottomNavigationBar: NavigationBar(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _goBranch,
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.nfc), label: 'Reader'),
                  NavigationDestination(
                    icon: Icon(Icons.credit_card),
                    label: 'Cards',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings),
                    label: 'Settings',
                  ),
                ],
              ),
            );
          } else {
            // Use NavigationRail for wider screens (Tablets, Foldables, LandScape)
            return Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    selectedIndex: navigationShell.currentIndex,
                    onDestinationSelected: _goBranch,
                    labelType: NavigationRailLabelType.all,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.nfc),
                        label: Text('Reader'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.credit_card),
                        label: Text('Cards'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings),
                        label: Text('Settings'),
                      ),
                    ],
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  Expanded(child: navigationShell),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}
