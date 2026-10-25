import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:flutter_tabler_icons/flutter_tabler_icons.dart";
import "package:inventree/l10n/collected/app_localizations_en.dart";
import "package:inventree/settings/select_server.dart";
import "package:inventree/user_profile.dart";

Future<void> runProfileSecurityFlow(WidgetTester tester) async {
  final String profileName =
      "Security UI test ${DateTime.now().microsecondsSinceEpoch}";

  await tester.pumpWidget(const MaterialApp(home: ProfileEditWidget(null)));

  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), profileName);
  await tester.enterText(fields.at(1), "http://example.invalid");
  await tester.tap(find.byIcon(TablerIcons.circle_check));
  await tester.pumpAndSettle();

  expect(find.text(I18NEn().invalidHost), findsOneWidget);
  expect(
    await tester.runAsync(
      () => UserProfileDBManager().getProfileByName(profileName),
    ),
    isNull,
  );

  await tester.enterText(fields.at(1), "http://127.0.0.1:8000");
  await tester.runAsync(() async {
    await tester.tap(find.byIcon(TablerIcons.circle_check));
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    UserProfile? profile;
    while (profile == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      profile = await UserProfileDBManager().getProfileByName(profileName);
    }
    try {
      expect(profile, isNotNull);
      expect(profile?.server, "http://127.0.0.1:8000");
    } finally {
      if (profile != null) {
        await UserProfileDBManager().deleteProfile(profile);
      }
    }
  });
  await tester.pumpAndSettle();
}
