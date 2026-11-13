import 'package:demonify/core/theme/theme.dart';
import 'package:demonify/features/auth/login_screen.dart';
import 'package:demonify/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Login zeigt Demonify-Branding und deutsche Texte, auch bei großer Schrift', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildDemonifyTheme(),
        locale: const Locale('de'),
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: const MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(1.6)), child: LoginScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Demonify'), findsOneWidget);
    expect(find.text('Anmeldename oder E-Mail'), findsOneWidget);
    expect(find.text('Passwort vergessen?'), findsOneWidget);
    expect(find.text('Anmelden'), findsOneWidget);
    // Leere Eingaben → Validierung statt Netzwerkaufruf
    await tester.ensureVisible(find.text('Anmelden'));
    await tester.tap(find.text('Anmelden'));
    await tester.pump();
    expect(find.text('Pflichtfeld'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
