// Local UI preview only: flutter run -d web-server -t tool/arcadelink_ui_preview.dart
import 'package:flutter/material.dart';
import 'package:hinata_go/features/arcadelink/arcadelink_machine_content.dart';
import 'package:hinata_go/services/arcadelink_api.dart';

void main() {
  var signedIn = false;
  String? active;
  var busy = false;
  var sending = false;
  var success = false;
  var completed = false;
  const cards = [
    ArcadeLinkCard(
      id: '1',
      label: '红黑卡',
      accessCode: '12345678901234566958',
      disabledAt: null,
    ),
    ArcadeLinkCard(
      id: '2',
      label: '蓝白卡',
      accessCode: '12345678901234560225',
      disabledAt: null,
    ),
    ArcadeLinkCard(
      id: '3',
      label: 'Nimo 卡',
      accessCode: '12345678901234563317',
      disabledAt: null,
    ),
  ];
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: StatefulBuilder(
                  builder: (context, setState) => ArcadeLinkMachineContent(
                    session: const ArcadeLinkMachineSession(
                      ticket: 'local-preview',
                      expiresIn: 300,
                      machine: ArcadeLinkMachine(
                        publicId: 'preview',
                        name: '舞萌',
                        shopName: '月宫',
                      ),
                    ),
                    cards: cards,
                    authRequired: !signedIn,
                    authenticating: false,
                    passkeyAuthenticating: false,
                    loggingIn: busy,
                    sending: sending,
                    success: success,
                    completed: completed,
                    activeCardId: active,
                    webAuthStarted: false,
                    error: null,
                    passkeyAvailable: true,
                    nativeMunetAvailable: true,
                    onAuthenticate: () => setState(() => signedIn = true),
                    onAuthenticatePasskey: () =>
                        setState(() => signedIn = true),
                    onReloadCards: () {},
                    onContinue: () {},
                    onLogin: (card) async {
                      setState(() {
                        busy = true;
                        active = card.id;
                      });
                      await Future<void>.delayed(const Duration(seconds: 1));
                      if (!context.mounted) return;
                      setState(() => sending = true);
                      await Future<void>.delayed(const Duration(seconds: 1));
                      if (!context.mounted) return;
                      setState(() {
                        busy = false;
                        success = true;
                      });
                      await Future<void>.delayed(
                        const Duration(milliseconds: 2500),
                      );
                      if (context.mounted) setState(() => completed = true);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
