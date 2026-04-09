import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';

import '../models/scanning_mode.dart';
import 'app_layout.dart';
import '../providers/app_update_provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/navigation_provider.dart';
import 'components/device/device_mini_bar.dart';

class ScaffoldWithNavBar extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    _syncShellState(context, ref);
    final destinations = _buildNavDestinations(context, ref);

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = context.appLayout;

        return GestureDetector(
          onHorizontalDragEnd: layout.useRailNavigation ? null : _handleSwipe,
          onVerticalDragEnd: layout.useRailNavigation ? _handleSwipe : null,
          behavior: HitTestBehavior.translucent,
          child: layout.useRailNavigation
              ? _RailScaffoldBody(
                  navigationShell: navigationShell,
                  currentIndex: navigationShell.currentIndex,
                  onDestinationSelected: _goBranch,
                )
              : _MobileScaffoldBody(
                  navigationShell: navigationShell,
                  currentIndex: navigationShell.currentIndex,
                  onDestinationSelected: _goBranch,
                  destinations: destinations,
                ),
        );
      },
    );
  }

  void _syncShellState(BuildContext context, WidgetRef ref) {
    final bool isScaffoldVisible = context.modalRoute?.isCurrent ?? false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(isScaffoldCoveredProvider) == isScaffoldVisible) {
        ref
            .read(isScaffoldCoveredProvider.notifier)
            .setCovered(!isScaffoldVisible);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(activeBranchProvider) != navigationShell.currentIndex) {
        ref
            .read(activeBranchProvider.notifier)
            .setIndex(navigationShell.currentIndex);
      }
    });
  }

  List<NavigationDestination> _buildNavDestinations(
    BuildContext context,
    WidgetRef ref,
  ) {
    final l10n = context.l10n;
    final hasUpdate = ref.watch(appUpdateProvider).hasUpdate;

    return [
      NavigationDestination(icon: const Icon(Icons.nfc), label: l10n.scan),
      NavigationDestination(
        icon: const Icon(Icons.credit_card),
        label: l10n.cards,
      ),
      NavigationDestination(
        icon: Badge(
          isLabelVisible: hasUpdate,
          child: const Icon(Icons.settings),
        ),
        label: l10n.settings,
      ),
    ];
  }
}

class _MobileScaffoldBody extends StatelessWidget {
  const _MobileScaffoldBody({
    required this.navigationShell,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final StatefulNavigationShell navigationShell;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _NavigationShellHost(navigationShell: navigationShell),
          ),
          const _BottomFloatingDeviceBar(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations,
      ),
    );
  }
}

class _RailScaffoldBody extends ConsumerWidget {
  const _RailScaffoldBody({
    required this.navigationShell,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  final StatefulNavigationShell navigationShell;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    final isExtended = layout.canExtendRail;
    final railColumn = _RailColumn(
      currentIndex: currentIndex,
      onDestinationSelected: onDestinationSelected,
      isExtended: isExtended,
      showModeSwitcher: layout.isCompactLandscapePhone && currentIndex == 0,
    );

    return Scaffold(
      body: Row(
        children: [
          if (layout.railOnLeadingSide) railColumn,
          if (layout.railOnLeadingSide)
            const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: _RailContentHost(
              navigationShell: navigationShell,
              isCompactLandscapePhone: layout.isCompactLandscapePhone,
            ),
          ),
          if (!layout.railOnLeadingSide)
            const VerticalDivider(thickness: 1, width: 1),
          if (!layout.railOnLeadingSide) railColumn,
        ],
      ),
    );
  }
}

class _RailColumn extends ConsumerWidget {
  const _RailColumn({
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.isExtended,
    required this.showModeSwitcher,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool isExtended;
  final bool showModeSwitcher;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final hasUpdate = ref.watch(appUpdateProvider).hasUpdate;
    final railDestinations = [
      NavigationRailDestination(
        icon: const Icon(Icons.nfc),
        label: Text(l10n.scan),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.credit_card),
        label: Text(l10n.cards),
      ),
      NavigationRailDestination(
        icon: Badge(
          isLabelVisible: hasUpdate,
          child: const Icon(Icons.settings),
        ),
        label: Text(l10n.settings),
      ),
    ];

    return SafeArea(
      minimum: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        width: isExtended ? 176 : 80,
        child: Column(
          children: [
            Expanded(
              child: _RailNavigation(
                extended: isExtended,
                selectedIndex: currentIndex,
                onDestinationSelected: onDestinationSelected,
                destinations: railDestinations,
              ),
            ),
            _RailFooter(
              showModeSwitcher: showModeSwitcher,
              showDeviceBar: context.appLayout.isCompactLandscapePhone,
              isExtended: isExtended,
              mode: ref.watch(scanningModeProvider),
              onModeChanged: (mode) {
                ref.read(scanningModeProvider.notifier).setMode(mode);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RailNavigation extends StatelessWidget {
  const _RailNavigation({
    required this.extended,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final bool extended;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationRailDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      extended: extended,
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      destinations: destinations,
    );
  }
}

class _RailFooter extends StatelessWidget {
  const _RailFooter({
    required this.showModeSwitcher,
    required this.showDeviceBar,
    required this.isExtended,
    required this.mode,
    required this.onModeChanged,
  });

  final bool showModeSwitcher;
  final bool showDeviceBar;
  final bool isExtended;
  final ScanningMode mode;
  final ValueChanged<ScanningMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    if (!showModeSwitcher && !showDeviceBar) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        if (showModeSwitcher)
          _RailSection(
            child: _RailModeSwitcher(
              isExtended: isExtended,
              mode: mode,
              onModeChanged: onModeChanged,
            ),
          ),
        if (showDeviceBar)
          _RailSection(
            child: isExtended
                ? const DeviceMiniBar(railExpanded: true)
                : const DeviceMiniBar(compact: true),
          ),
      ],
    );
  }
}

class _RailSection extends StatelessWidget {
  const _RailSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: child,
    );
  }
}

class _RailContentHost extends StatelessWidget {
  const _RailContentHost({
    required this.navigationShell,
    required this.isCompactLandscapePhone,
  });

  final StatefulNavigationShell navigationShell;
  final bool isCompactLandscapePhone;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _NavigationShellHost(navigationShell: navigationShell),
        ),
        if (!isCompactLandscapePhone) const _BottomFloatingDeviceBar(),
      ],
    );
  }
}

class _NavigationShellHost extends StatelessWidget {
  const _NavigationShellHost({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return navigationShell;
  }
}

class _BottomFloatingDeviceBar extends StatelessWidget {
  const _BottomFloatingDeviceBar();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: const DeviceMiniBar(),
          ),
        ),
      ),
    );
  }
}

class _RailModeSwitcher extends StatelessWidget {
  final bool isExtended;
  final ScanningMode mode;
  final ValueChanged<ScanningMode> onModeChanged;

  const _RailModeSwitcher({
    required this.isExtended,
    required this.mode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final buttons = [
      _RailModeButton(
        icon: Icons.person_pin_rounded,
        label: 'Normal',
        selected: mode == ScanningMode.normal,
        expanded: isExtended,
        onTap: () => onModeChanged(ScanningMode.normal),
      ),
      _RailModeButton(
        icon: Icons.send_rounded,
        label: 'Sender',
        selected: mode == ScanningMode.sender,
        expanded: isExtended,
        onTap: () => onModeChanged(ScanningMode.sender),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: _RailModeButtonList(buttons: buttons),
      ),
    );
  }
}

class _RailModeButtonList extends StatelessWidget {
  const _RailModeButtonList({required this.buttons});

  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [buttons.first, const SizedBox(height: 6), buttons.last],
    );
  }
}

class _RailModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  const _RailModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final foreground = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    final background = selected
        ? colorScheme.secondaryContainer
        : Colors.transparent;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: expanded
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
              : const EdgeInsets.all(10),
          child: expanded
              ? _ExpandedRailModeButtonContent(
                  icon: icon,
                  label: label,
                  foreground: foreground,
                  selected: selected,
                )
              : _CompactRailModeButtonContent(
                  icon: icon,
                  label: label,
                  foreground: foreground,
                ),
        ),
      ),
    );
  }
}

class _ExpandedRailModeButtonContent extends StatelessWidget {
  const _ExpandedRailModeButtonContent({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: foreground),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: context.textTheme.labelLarge?.copyWith(
              color: foreground,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactRailModeButtonContent extends StatelessWidget {
  const _CompactRailModeButtonContent({
    required this.icon,
    required this.label,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Icon(icon, size: 20, color: foreground),
    );
  }
}
