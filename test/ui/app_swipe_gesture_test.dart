import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/models/scanning_mode.dart';
import 'package:hinata_go/providers/app_state_provider.dart';
import 'package:hinata_go/providers/storage_provider.dart';
import 'package:hinata_go/ui/widgets/app_swipe_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  });

  tearDown(() => container.dispose());

  Widget app({
    required Axis axis,
    required Widget child,
    required ValueChanged<int> onBranchSelected,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: AppSwipeNavigation(
          tabAxis: axis,
          branchIndex: 0,
          onBranchSelected: onBranchSelected,
          child: Scaffold(body: child),
        ),
      ),
    );
  }

  Widget verticalList() {
    return ListView.builder(
      itemCount: 50,
      itemBuilder: (context, index) =>
          SizedBox(height: 60, child: Text('Item $index')),
    );
  }

  Widget horizontalList() {
    return ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (var index = 0; index < 20; index++)
          SizedBox(width: 100, child: Text('Tab $index')),
      ],
    );
  }

  testWidgets('a vertical list keeps a vertical drag', (tester) async {
    int? selectedBranch;
    await tester.pumpWidget(
      app(
        axis: Axis.vertical,
        onBranchSelected: (index) => selectedBranch = index,
        child: verticalList(),
      ),
    );

    await tester.fling(find.byType(ListView), const Offset(0, -300), 1000);
    await tester.pumpAndSettle();

    expect(selectedBranch, isNull);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets('empty content still switches top-level tabs', (tester) async {
    int? selectedBranch;
    await tester.pumpWidget(
      app(
        axis: Axis.vertical,
        onBranchSelected: (index) => selectedBranch = index,
        child: Container(color: Colors.white),
      ),
    );

    await tester.fling(
      find.byType(AppSwipeNavigation),
      const Offset(0, -300),
      1000,
    );
    await tester.pumpAndSettle();

    expect(selectedBranch, 1);
  });

  testWidgets('a vertical list does not block horizontal modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        axis: Axis.horizontal,
        onBranchSelected: (_) {},
        child: verticalList(),
      ),
    );

    await tester.fling(find.byType(ListView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();

    expect(container.read(scanningModeProvider), ScanningMode.sender);
  });

  testWidgets('a horizontal strip keeps its own horizontal drag', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        axis: Axis.horizontal,
        onBranchSelected: (_) {},
        child: horizontalList(),
      ),
    );

    await tester.fling(find.byType(ListView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();

    expect(container.read(scanningModeProvider), ScanningMode.normal);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, greaterThan(0));
  });
}
