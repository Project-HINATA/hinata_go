import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/l10n/app_localizations.dart';
import 'package:hinata_go/ui/components/instances/instance_dialog.dart';
import 'package:hinata_go/utils/constants.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('prefills the public HTTPS endpoint for a new HINATA IO', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: InstanceDialog()),
        ),
      ),
    );

    expect(find.text(AppConstants.defaultHinataIoUrl), findsOneWidget);
  });
}
