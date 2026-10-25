/*
 * Unit tests for the InvenTree API code
 */

import "package:flutter_test/flutter_test.dart";

import "package:inventree/api.dart";
import "package:inventree/helpers.dart";
import "package:inventree/user_profile.dart";

import "setup.dart";

void main() {
  setupTestEnv();

  setUp(() async {
    await setupServerProfile(select: true);

    // Ensure the profile is selected
    assert(
      !await UserProfileDBManager().selectProfileByName("Missing Profile"),
    );
    assert(await UserProfileDBManager().selectProfileByName(testServerName));
  });

  // Ensure that generated URLs are correct
  group("URL Tests:", () {
    test("Generate URLs", () async {
      UserProfile profile = await setupServerProfile();
      var api = InvenTreeAPI();

      api.profile = profile;

      Map<String, String> tests = {
        "": "http://localhost:8000/api/",
        "barcode/": "http://localhost:8000/api/barcode/",
        "https://remote-server.com/media/image.png":
            "https://remote-server.com/media/image.png",
      };

      for (var test in tests.entries) {
        expect(api.makeApiUrl(test.key), equals(test.value));
      }
    });

    test("Require HTTPS except for loopback servers", () {
      expect(isAllowedServerAddress("https://inventory.example.com"), isTrue);
      expect(isAllowedServerAddress("http://localhost:8000"), isTrue);
      expect(isAllowedServerAddress("http://127.0.0.1:8000"), isTrue);
      expect(isAllowedServerAddress("http://inventory.example.com"), isFalse);
      expect(
        isAllowedServerAddress("https://user:pass@inventory.example.com"),
        isFalse,
      );
      expect(isAllowedServerAddress("javascript:alert(1)"), isFalse);
    });

    test("Scope API tokens to the configured origin", () async {
      final profile = await setupServerProfile();
      profile.token = "test-token";
      final api = InvenTreeAPI()..profile = profile;

      expect(
        api.defaultHeaders(
          requestUri: Uri.parse(testServerAddress),
        )["authorization"],
        "Token test-token",
      );
      expect(
        api.defaultHeaders(
          requestUri: Uri.parse("https://external.example/image.png"),
        )["authorization"],
        isNull,
      );
    });

    test("Trust a certificate only for its exact endpoint and fingerprint", () {
      final profile = UserProfile(
        trustedCertificateHost: "inventory.example.com",
        trustedCertificatePort: 443,
        trustedCertificateFingerprint: "trusted-fingerprint",
      );

      expect(
        profile.trustsCertificate(
          "inventory.example.com",
          443,
          "trusted-fingerprint",
        ),
        isTrue,
      );
      expect(
        profile.trustsCertificate(
          "other.example.com",
          443,
          "trusted-fingerprint",
        ),
        isFalse,
      );
      expect(
        profile.trustsCertificate(
          "inventory.example.com",
          8443,
          "trusted-fingerprint",
        ),
        isFalse,
      );
      expect(
        profile.trustsCertificate(
          "inventory.example.com",
          443,
          "different-fingerprint",
        ),
        isFalse,
      );
    });
  });

  group("APIResponse:", () {
    test("classifies successful and client error responses", () {
      final success = APIResponse(statusCode: 201, data: {"created": true});
      expect(success.isValid(), isTrue);
      expect(success.successful(), isTrue);
      expect(success.clientError(), isFalse);
      expect(success.asMap(), {"created": true});

      final clientError = APIResponse(statusCode: 404, data: ["missing"]);
      expect(clientError.isValid(), isTrue);
      expect(clientError.successful(), isFalse);
      expect(clientError.clientError(), isTrue);
      expect(clientError.asList(), ["missing"]);

      final serverError = APIResponse(statusCode: 503);
      expect(serverError.isValid(), isFalse);
      expect(serverError.serverError(), isTrue);
      expect(serverError.asMap(), isEmpty);
      expect(serverError.asList(), isEmpty);
    });

    test("supports empty and invalid response defaults", () {
      final response = APIResponse();
      expect(response.isValid(), isFalse);
      expect(response.successful(), isFalse);
      expect(response.redirected(), isFalse);
      expect(response.clientError(), isFalse);
      expect(response.serverError(), isFalse);
    });
  });

  group("Login Tests:", skip: !runServerIntegrationTests, () {
    test("Disconnected", () async {
      // Test that calling disconnect() does the right thing
      var api = InvenTreeAPI();

      api.disconnectFromServer();

      // Check expected values
      expect(api.isConnected(), equals(false));
      expect(api.isConnecting(), equals(false));
      expect(api.hasToken, equals(false));
    });

    test("Login Failure", () async {
      // Tests for various types of login failures
      var api = InvenTreeAPI();

      // Incorrect server address
      var profile = await setupServerProfile();

      profile.server = "http://localhost:5555";

      bool result = await api.connectToServer(profile);
      assert(!result);

      debugContains("SocketException at");

      // Test incorrect login details
      profile.server = testServerAddress;

      final response = await api.fetchToken(profile, "baduser", "badpassword");
      assert(!response.successful());

      debugContains("Token request failed");

      assert(!api.checkConnection());

      debugContains("Token request failed: STATUS 401");
      debugContains("showSnackIcon: 'Not Connected'");
    });

    test("Bad Token", () async {
      // Test that login fails with a bad token
      var profile = await setupServerProfile();

      profile.token = "bad-token";

      bool result = await InvenTreeAPI().connectToServer(profile);
      assert(!result);
    });

    test("Login Success", () async {
      // Test that we can login to the server successfully
      var api = InvenTreeAPI();

      final profile = await setupServerProfile(select: true, fetchToken: true);
      assert(profile.hasToken);

      // Now, connect to the server
      bool result = await api.connectToServer(profile);

      // Check expected values
      assert(result);
      assert(api.hasToken);

      expect(api.baseUrl, equals(testServerAddress));

      assert(api.hasToken);
      assert(api.isConnected());
      assert(!api.isConnecting());
      assert(api.checkConnection());
    });

    test("Version Checks", () async {
      // Test server version information
      var api = InvenTreeAPI();

      final profile = await setupServerProfile(fetchToken: true);
      assert(await api.connectToServer(profile));

      // Check supported functions
      assert(api.apiVersion >= 50);
      assert(api.serverInstance.isNotEmpty);
      assert(api.serverVersion.isNotEmpty);

      // Ensure we can have user role data
      assert(api.roles.isNotEmpty);

      // Check available permissions
      assert(api.checkRole("part", "change"));
      assert(api.checkRole("stock", "delete"));
      assert(!api.checkRole("part", "weirdpermission"));
      assert(api.checkRole("blah", "bloo"));

      // Pricing role (or legacy server with no pricing role)
      assert(api.canViewPricing);

      debugContains("Received token from server");
      debugContains("showSnackIcon: 'Connected to Server'");
    });
  });
}
