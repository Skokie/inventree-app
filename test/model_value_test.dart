import "package:flutter_test/flutter_test.dart";
import "package:inventree/inventree/model.dart";

import "setup.dart";

void main() {
  setupTestEnv();

  group("InvenTreeModel JSON accessors", () {
    late InvenTreeModel model;

    setUp(() {
      model = InvenTreeModel.fromJson({
        "id": 99,
        "text": "value",
        "integer": 42,
        "decimal": 3.25,
        "boolean": true,
        "falseBoolean": false,
        "truthText": "TRUE",
        "falseText": "false",
        "misleadingText": "not true",
        "date": "2025-04-03T12:30:00Z",
        "invalidDate": "not-a-date",
        "nested": {"id": 7, "name": "nested value"},
        "nullable": null,
      });
    });

    test("reads values and applies missing-value fallbacks", () {
      expect(model.getValue("text"), "value");
      expect(model.getValue("missing", backup: "fallback"), "fallback");
      expect(model.getValue("id", subKey: "nested"), 7);
      expect(
        model.getValue("id", backup: -1, subKey: "missing"),
        -1,
      );
      expect(model.getValue("id", backup: -1, subKey: "text"), -1);
      expect(model.getValue("nullable", backup: "fallback"), null);
    });

    test("returns map fallbacks when data is absent or malformed", () {
      expect(model.getMap("nested"), {"id": 7, "name": "nested value"});
      expect(model.getMap("missing", backup: {"fallback": true}), {
        "fallback": true,
      });
      expect(model.getMap("text", backup: {"fallback": true}), {
        "fallback": true,
      });
    });

    test("converts strings, integers, and floating-point values", () {
      expect(model.getString("integer"), "42");
      expect(model.getString("missing", backup: "fallback"), "fallback");
      expect(model.getInt("integer"), 42);
      expect(model.getInt("text", backup: 9), 9);
      expect(model.getDouble("decimal"), 3.25);
      expect(model.getDoubleOrNull("decimal"), 3.25);
      expect(model.getDoubleOrNull("text"), isNull);
      expect(model.getDoubleOrNull("missing", backup: 2.5), 2.5);
    });

    test("parses booleans without treating unrelated text as true", () {
      expect(model.getBool("boolean"), isTrue);
      expect(model.getBool("falseBoolean", backup: true), isFalse);
      expect(model.getBool("truthText"), isTrue);
      expect(model.getBool("falseText", backup: true), isFalse);
      expect(model.getBool("misleadingText"), isFalse);
      expect(model.getBool("missing", backup: true), isTrue);
    });

    test("parses dates and formats date-only values", () {
      expect(model.getDate("date"), DateTime.utc(2025, 4, 3, 12, 30));
      expect(model.getDate("invalidDate"), isNull);
      expect(model.getDate("missing", backup: DateTime.utc(2024)),
          DateTime.utc(2024));
      expect(model.getDateString("date"), "2025-04-03");
      expect(model.getDateString("invalidDate"), "");
    });

    test("sets values and reports cache freshness", () {
      model.setValue("new", "stored");
      expect(model.getString("new"), "stored");

      expect(model.reloadedWithin(const Duration(minutes: 1)), isFalse);
      model.lastReload = DateTime.now();
      expect(model.reloadedWithin(const Duration(minutes: 1)), isTrue);
      model.lastReload = DateTime.now().subtract(const Duration(minutes: 2));
      expect(model.reloadedWithin(const Duration(minutes: 1)), isFalse);
    });
  });

  test("InvenTreePageResponse tracks result count and entries", () {
    final response = InvenTreePageResponse()..count = 3;
    final first = InvenTreeModel.fromJson({"id": 1});
    final second = InvenTreeModel.fromJson({"id": 2});

    expect(response.length, 0);
    response
      ..addResult(first)
      ..addResult(second);

    expect(response.count, 3);
    expect(response.length, 2);
    expect(response.results, [first, second]);
  });
}