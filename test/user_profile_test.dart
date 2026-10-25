/*
 * Unit tests for the API class
 */

import "package:test/test.dart";
import "package:inventree/preferences.dart";
import "package:inventree/user_profile.dart";
import "package:sembast/sembast.dart";

import "setup.dart";

void main() {
  setupTestEnv();

  setUp(() async {
    // Ensure we have a user profile available
    // This profile will match the dockerized InvenTree setup, running locally

    // To start with, there should not be *any* profiles available
    var profiles = await UserProfileDBManager().getAllProfiles();

    for (var prf in profiles) {
      await UserProfileDBManager().deleteProfile(prf);
    }

    // Check that there are *no* profiles in the database
    profiles = await UserProfileDBManager().getAllProfiles();
    expect(profiles.length, equals(0));

    // Now, create one!
    bool result = await UserProfileDBManager().addProfile(
      UserProfile(
        name: testServerName,
        server: testServerAddress,
        selected: true,
      ),
    );

    expect(result, equals(true));

    // Ensure we have one profile available
    // expect(profiles.length, equals(1));
    profiles = await UserProfileDBManager().getAllProfiles();

    expect(profiles.length, equals(1));

    int key = -1;

    // Find the first available profile
    for (var p in profiles) {
      if (p.key != null) {
        key = p.key ?? key;
        break;
      }
    }

    // Select the profile
    await UserProfileDBManager().selectProfile(key);
  });

  // Run a set of tests for user profile functionality
  group("Profile Tests:", () {
    test("Add Invalid Profiles", () async {
      // Add a profile with missing data
      bool result = await UserProfileDBManager().addProfile(UserProfile());

      expect(result, equals(false));

      // Add a profile with a new name
      result = await UserProfileDBManager().addProfile(
        UserProfile(name: "Another Test Profile"),
      );

      expect(result, equals(true));

      // Check that the number of protocols available is still the same
      var profiles = await UserProfileDBManager().getAllProfiles();

      expect(profiles.length, equals(2));
    });

    test("Profile Name Check", () async {
      bool result = await UserProfileDBManager().profileNameExists(
        "doesnotexist",
      );
      expect(result, equals(false));

      result = await UserProfileDBManager().profileNameExists("Test Server");
      expect(result, equals(true));
    });

    test("Select Profile", () async {
      // Ensure that we can select a user profile
      final prf = await UserProfileDBManager().getSelectedProfile();

      expect(prf, isNot(null));

      if (prf != null) {
        UserProfile p = prf;

        expect(p.name, equals(testServerName));
        expect(p.server, equals(testServerAddress));

        expect(
          p.toString(),
          equals("<${p.key}> Test Server : http://localhost:8000/"),
        );

        // Test that we can update the profile
        p.name = "different name";

        bool result = await UserProfileDBManager().updateProfile(p);
        expect(result, equals(true));
      }
    });

    test(
      "Serializes endpoint-bound trust without persisting the API token",
      () {
        final profile = UserProfile(
          name: "Secure profile",
          server: "https://inventory.example.com",
          token: "secret-token",
          trustedCertificateHost: "inventory.example.com",
          trustedCertificatePort: 443,
          trustedCertificateFingerprint: "certificate-sha256",
        );

        final json = profile.toJson();
        final restored = UserProfile.fromJson(1, json, false);

        expect(json.containsKey("token"), isFalse);
        expect(restored.token, isEmpty);
        expect(restored.trustedCertificateHost, "inventory.example.com");
        expect(restored.trustedCertificatePort, 443);
        expect(restored.trustedCertificateFingerprint, "certificate-sha256");
        expect(
          restored.trustsCertificate(
            "inventory.example.com",
            443,
            "certificate-sha256",
          ),
          isTrue,
        );

        final legacyTrust = UserProfile.fromJson(2, {
          "name": "Legacy profile",
          "server": "https://inventory.example.com",
          "trustedCertificate": true,
        }, false);
        expect(legacyTrust.trustedCertificateFingerprint, isEmpty);
      },
    );

    test("Stores API tokens outside the plain profile record", () async {
      final manager = UserProfileDBManager();
      final profile = UserProfile(
        name: "Token profile",
        server: "https://inventory.example.com",
        token: "secret-token",
      );

      expect(await manager.addProfile(profile), isTrue);

      final Database database = await InvenTreePreferencesDB.instance.database;
      final record = await manager.store.record(profile.key).get(database);
      expect(record, isA<Map<String, dynamic>>());
      if (record is! Map<String, dynamic>) {
        fail("Expected a persisted profile map");
      }

      expect(record.containsKey("token"), isFalse);
      expect(
        (await manager.getProfileByKey(profile.key!))?.token,
        "secret-token",
      );

      profile.token = "";
      expect(await manager.updateProfile(profile), isTrue);
      expect((await manager.getProfileByKey(profile.key!))?.token, isEmpty);
    });

    test("Migrates legacy plaintext tokens once", () async {
      final manager = UserProfileDBManager();
      final Database database = await InvenTreePreferencesDB.instance.database;
      final key = await manager.store.add(database, {
        "name": "Legacy token profile",
        "server": "https://inventory.example.com",
        "token": "legacy-token",
      });
      expect(key, isA<int>());
      if (key is! int) {
        fail("Expected the legacy profile to have an integer key");
      }

      final profile = await manager.getProfileByKey(key);
      expect(profile?.token, "legacy-token");

      final migrated = await manager.store.record(key).get(database);
      expect(migrated, isA<Map<String, dynamic>>());
      if (migrated is! Map<String, dynamic>) {
        fail("Expected a migrated profile map");
      }
      expect(migrated.containsKey("token"), isFalse);
      expect((await manager.getProfileByKey(key))?.token, "legacy-token");
    });
  });
}
