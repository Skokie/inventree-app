/*
 * Unit tests for the preferences manager
 */

import "package:flutter_test/flutter_test.dart";
import "package:inventree/l10n/supported_locales.dart";
import "package:inventree/preferences.dart";

import "setup.dart";

void main() {
  setupTestEnv();

  setUp(() async {});

  group("Settings Tests:", () {
    test("Default Values", () async {
      // Boolean values
      expect(
        await InvenTreeSettingsManager().getBool("test", false),
        equals(false),
      );
      expect(
        await InvenTreeSettingsManager().getBool("test", true),
        equals(true),
      );

      // String values
      expect(
        await InvenTreeSettingsManager().getValue("test", "x"),
        equals("x"),
      );
    });

    test("Set value", () async {
      await InvenTreeSettingsManager().setValue("abc", "xyz");

      expect(
        await InvenTreeSettingsManager().getValue("abc", "123"),
        equals("xyz"),
      );
    });

    test("Null values use the supplied fallback and can be removed", () async {
      final manager = InvenTreeSettingsManager();
      await manager.setValue("nullable-setting", null);

      expect(
        await manager.getValue("nullable-setting", "fallback"),
        "fallback",
      );

      await manager.setValue("nullable-setting", "value");
      expect(await manager.getValue("nullable-setting", "fallback"), "value");

      await manager.removeValue("nullable-setting");
      expect(
        await manager.getValue("nullable-setting", "fallback"),
        "fallback",
      );
    });

    test(
      "Selected locale round-trips and rejects unsupported values",
      () async {
        final manager = InvenTreeSettingsManager();
        final locale = supported_locales.firstWhere(
          (supported) => supported.languageCode == "fr",
        );

        await manager.setSelectedLocale(locale);
        expect(await manager.getSelectedLocale(), locale);

        await manager.setSelectedLocale(null);
        expect(await manager.getSelectedLocale(), isNull);

        await manager.setValue("customLocale", "xx_YY");
        expect(await manager.getSelectedLocale(), isNull);
      },
    );

    test("Booleans", () async {
      // Tests for boolean values

      await InvenTreeSettingsManager().removeValue("chicken");

      // Use default values when a setting does not exist
      assert(await InvenTreeSettingsManager().getBool("chicken", true) == true);
      assert(
        await InvenTreeSettingsManager().getBool("chicken", false) == false,
      );

      // Explicitly set to true
      await InvenTreeSettingsManager().setValue("chicken", true);
      assert(
        await InvenTreeSettingsManager().getBool("chicken", false) == true,
      );

      // Explicitly set to false
      await InvenTreeSettingsManager().setValue("chicken", false);
      assert(
        await InvenTreeSettingsManager().getBool("chicken", true) == false,
      );

      await InvenTreeSettingsManager().setValue("text-bool", "TRUE");
      expect(
        await InvenTreeSettingsManager().getBool("text-bool", false),
        isTrue,
      );

      await InvenTreeSettingsManager().setValue("text-bool", "false");
      expect(
        await InvenTreeSettingsManager().getBool("text-bool", true),
        isFalse,
      );

      await InvenTreeSettingsManager().setValue("text-bool", "not true");
      expect(
        await InvenTreeSettingsManager().getBool("text-bool", false),
        isFalse,
      );
    });
  });
}
