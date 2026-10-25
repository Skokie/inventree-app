import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:inventree/api.dart";
import "package:inventree/inventree/part.dart";
import "package:inventree/user_profile.dart";

import "setup.dart";

void main() {
  setupTestEnv();

  group("API and model HTTP behavior", () {
    late HttpServer server;
    late StreamSubscription<HttpRequest> subscription;
    late InvenTreeAPI api;
    final List<Map<String, dynamic>> requests = [];

    setUp(() async {
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      subscription = server.listen((request) async {
        final String body = await utf8.decoder.bind(request).join();
        requests.add({
          "method": request.method,
          "path": request.uri.path,
          "query": request.uri.queryParameters,
          "authorization": request.headers.value(
            HttpHeaders.authorizationHeader,
          ),
          "body": body.isEmpty ? null : jsonDecode(body),
        });

        int statusCode = HttpStatus.ok;
        Object responseBody = <String, dynamic>{};

        if (request.method == "GET" && request.uri.path == "/api/part/7/") {
          responseBody = {"pk": 7, "name": "Resistor", "active": true};
        } else if (request.method == "GET" &&
            request.uri.path == "/api/part/") {
          responseBody = {
            "count": 2,
            "results": [
              {"pk": 7, "name": "Resistor"},
              {"pk": 8, "name": "Capacitor"},
            ],
          };
        } else if (request.method == "POST" &&
            request.uri.path == "/api/part/") {
          statusCode = HttpStatus.created;
          responseBody = {"pk": 12, "name": "New Part"};
        } else if (request.method == "PATCH" &&
            request.uri.path == "/api/part/7/") {
          responseBody = {"pk": 7, "name": "Updated Resistor"};
        } else if (request.method == "DELETE" &&
            request.uri.path == "/api/part/7/") {
          statusCode = HttpStatus.noContent;
        } else if (request.method == "GET" &&
            request.uri.path == "/api/error/") {
          statusCode = HttpStatus.badRequest;
          responseBody = {"detail": "invalid request"};
        } else {
          statusCode = HttpStatus.notFound;
          responseBody = {"detail": "not found"};
        }

        request.response.statusCode = statusCode;
        request.response.headers.contentType = ContentType.json;
        if (statusCode != HttpStatus.noContent) {
          request.response.write(jsonEncode(responseBody));
        }
        await request.response.close();
      });

      api = InvenTreeAPI();
      api.profile = UserProfile(
        name: "Local API test",
        server: "http://127.0.0.1:${server.port}/",
        token: "test-api-token",
      );
    });

    tearDown(() async {
      api.disconnectFromServer();
      await subscription.cancel();
      await server.close(force: true);
    });

    test("GET sends scoped auth and parses paginated model results", () async {
      final List<dynamic> results = await InvenTreePart().list(
        filters: {"search": "resistor", "active": "true"},
      );

      expect(results, hasLength(2));
      expect(results.first, isA<InvenTreePart>());
      expect((results.first as InvenTreePart).name, "Resistor");
      expect(requests.single["method"], "GET");
      expect(requests.single["path"], "/api/part/");
      expect(requests.single["query"], {
        "category_detail": "true",
        "search": "resistor",
        "active": "true",
      });
      expect(requests.single["authorization"], "Token test-api-token");
    });

    test(
      "GET detail, reload, update, create, and delete use model URLs",
      () async {
        final retrieved = await InvenTreePart().get(7);
        expect(retrieved, isA<InvenTreePart>());
        if (retrieved is! InvenTreePart) {
          fail("Expected the part endpoint to return an InvenTreePart");
        }
        final part = retrieved;
        expect(part.name, "Resistor");

        expect(await part.reload(), isTrue);
        expect(part.name, "Resistor");

        final updated = await part.update(values: {"name": "Updated Resistor"});
        expect(updated.statusCode, HttpStatus.ok);
        expect(requests.last["method"], "PATCH");
        expect(requests.last["body"], {"name": "Updated Resistor"});

        final createData = {"pk": 99, "id": 99, "name": "New Part"};
        final created = await InvenTreePart().create(createData);
        expect(created?.pk, 12);
        expect(requests.last["method"], "POST");
        expect(requests.last["body"], {"name": "New Part"});
        expect(createData.containsKey("pk"), isFalse);
        expect(createData.containsKey("id"), isFalse);

        expect(await part.delete(), isTrue);
        expect(requests.last["method"], "DELETE");
        expect(requests.last["path"], "/api/part/7/");
      },
    );

    test("API returns structured client errors", () async {
      final response = await api.get("error/", expectedStatusCode: 200);

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.clientError(), isTrue);
      expect(response.asMap(), {"detail": "invalid request"});
      expect(requests.single["authorization"], "Token test-api-token");
    });
  });
}
