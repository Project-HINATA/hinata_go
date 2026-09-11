import 'package:hinata_go/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hinata_go/features/arcadelink/arcadelink_machine_content.dart';
import 'package:hinata_go/services/arcadelink_api.dart';

const session = ArcadeLinkMachineSession(
  ticket: 'test',
  expiresIn: 300,
  machine: ArcadeLinkMachine(publicId: 'test', name: '舞萌 DX', shopName: '月宫'),
);
const card = ArcadeLinkCard(
  id: '1',
  label: '一张名称比较长的测试卡片',
  accessCode: '12345678901234567890',
  disabledAt: null,
);

Widget content({
  String? heroUrl,
  bool auth = false,
  bool busy = false,
  bool browserOnly = false,
  bool passkey = false,
  String? passkeyLabel,
  bool success = false,
  List<ArcadeLinkCard> cards = const [],
  ValueChanged<ArcadeLinkCard>? onLogin,
}) => ArcadeLinkMachineContent(
  session: ArcadeLinkMachineSession(
    ticket: session.ticket,
    expiresIn: session.expiresIn,
    machine: ArcadeLinkMachine(
      publicId: 'test',
      name: '舞萌 DX',
      shopName: '月宫',
      heroUrl: heroUrl,
    ),
  ),
  cards: cards,
  authRequired: auth,
  authenticating: false,
  passkeyAuthenticating: false,
  loggingIn: busy,
  activeCardId: busy || success ? '1' : null,
  success: success,
  webAuthStarted: false,
  error: null,
  browserOnly: browserOnly,
  passkeyAvailable: passkey,
  passkeyActionLabel: passkeyLabel,
  onAuthenticate: () {},
  onAuthenticatePasskey: () {},
  onReloadCards: () {},
  onLogin: onLogin ?? (_) {},
  onContinue: () {},
);

Future<void> show(
  WidgetTester tester,
  Widget child, {
  double scale = 1,
  Locale locale = const Locale('zh'),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: brightness,
        ),
      ),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(320, 640),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'cover and tint share a loaded image; missing cover keeps one title',
    (tester) async {
      const url = 'https://example.com/hero.jpg';
      const provider = CachedNetworkImageProvider(url);
      final image = await tester.runAsync(() async {
        final data = await rootBundle.load('assets/munet-logo.png');
        return decodeImageFromList(data.buffer.asUint8List());
      });
      PaintingBinding.instance.imageCache.putIfAbsent(
        provider,
        () => OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: image!)),
        ),
      );
      addTearDown(provider.evict);
      for (final brightness in Brightness.values) {
        await show(tester, content(heroUrl: url), brightness: brightness);
        await tester.pumpAndSettle();
        expect(find.byType(ImageFiltered), findsOneWidget);
        expect(find.byType(RawImage), findsNWidgets(2));
        expect(find.text('月宫'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await show(tester, content());
      await tester.pumpAndSettle();
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.text('月宫'), findsOneWidget);
    },
  );

  testWidgets(
    'English actions and large text fit without translating card data',
    (tester) async {
      await show(
        tester,
        content(auth: true, passkey: true),
        locale: const Locale('en'),
      );
      expect(find.text('Sign in with MuNET'), findsOneWidget);
      expect(find.text('Sign in with a passkey'), findsOneWidget);
      expect(find.text('使用 MuNET 登录'), findsNothing);
      await show(
        tester,
        content(cards: [card]),
        locale: const Locale('en'),
        scale: 2,
      );
      expect(find.text('Select a card'), findsOneWidget);
      expect(find.text('Ending in 7890'), findsOneWidget);
      expect(find.text(card.label), findsOneWidget);
      expect(find.byTooltip('Sign out'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('MuNET is primary and Passkey remains available', (tester) async {
    await show(tester, content(auth: true, passkey: true));
    expect(find.text('使用 Passkey 登录'), findsOneWidget);
    expect(find.text('使用 MuNET 登录'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('使用 MuNET 登录')).dy,
      lessThan(tester.getTopLeft(find.text('使用 Passkey 登录')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed-out state has one large primary action and no error', (
    tester,
  ) async {
    await show(tester, content(auth: true));
    expect(find.text('请先登录'), findsNothing);
    expect(find.text('使用 MuNET 登录'), findsOneWidget);
    expect(
      tester.getSize(find.byType(FilledButton).first).height,
      greaterThanOrEqualTo(56),
    );
    expect(find.text('打开网页版'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'large text and long card name fit narrow screen; full row is tappable',
    (tester) async {
      var tapped = 0;
      await show(
        tester,
        content(cards: [card], onLogin: (_) => tapped++),
        scale: 2,
      );
      await tester.ensureVisible(find.text(card.label));
      await tester.tap(find.text(card.label));
      expect(tapped, 1);
      expect(find.text('尾号 7890'), findsOneWidget);
      expect(find.text(card.accessCode), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending login disables all card actions', (tester) async {
    var tapped = 0;
    await show(
      tester,
      content(cards: [card], busy: true, onLogin: (_) => tapped++),
    );
    await tester.ensureVisible(find.text('确认位置…'));
    await tester.tap(find.text(card.label));
    expect(tapped, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
    'browser-only platforms do not pretend the account has no cards',
    (tester) async {
      await show(
        tester,
        content(browserOnly: true),
        brightness: Brightness.dark,
      );
      expect(find.text('继续登录'), findsOneWidget);
      expect(find.text('还没有添加卡片'), findsNothing);
      expect(find.text('打开网页版'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('successful session does not expose an expired login action', (
    tester,
  ) async {
    await show(tester, content(success: true, cards: [card]));
    expect(find.text('已登录'), findsOneWidget);
    expect(find.text('打开网页版'), findsNothing);
    expect(find.text('登录'), findsNothing);
  });
}
