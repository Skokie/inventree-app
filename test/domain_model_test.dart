import "package:flutter_test/flutter_test.dart";
import "package:inventree/api.dart";
import "package:inventree/inventree/company.dart";
import "package:inventree/inventree/build.dart";
import "package:inventree/inventree/orders.dart";
import "package:inventree/inventree/part.dart";
import "package:inventree/inventree/purchase_order.dart";
import "package:inventree/inventree/sales_order.dart";
import "package:inventree/inventree/stock.dart";

import "setup.dart";

void main() {
  setupTestEnv();

  group("Part models", () {
    test("category supports current and legacy part counts", () {
      final category = InvenTreePartCategory.fromJson({
        "pathstring": "Electronics/Audio",
        "part_count": 12,
        "parts": 5,
      });
      final legacyCategory = InvenTreePartCategory.fromJson({"parts": 4});

      expect(category.URL, "part/category/");
      expect(category.pathstring, "Electronics/Audio");
      expect(category.parentPathString, "Electronics");
      expect(category.partcount, 12);
      expect(legacyCategory.partcount, 4);
    });

    test(
      "part uses current inventory fields and clamps negative availability",
      () {
        final part = InvenTreePart.fromJson({
          "pk": 7,
          "total_in_stock": "5.5",
          "in_stock": "4",
          "unallocated_stock": -2,
          "ordering": "3",
          "units": "pcs",
          "assembly": true,
          "component": false,
          "active": true,
        });

        expect(part.pk, 7);
        expect(part.inStock, 5.5);
        expect(part.onOrder, 3);
        expect(part.unallocatedStock, 0);
        expect(part.stockString(), "0 / 5.5 pcs");
        expect(part.stockString(includeUnits: false), "0 / 5.5");
        expect(part.isAssembly, isTrue);
        expect(part.isComponent, isFalse);
        expect(part.isActive, isTrue);
        expect(part.defaultFilters(), {"category_detail": "true"});
      },
    );

    test("part falls back to legacy stock fields", () {
      final part = InvenTreePart.fromJson({"in_stock": 6});

      expect(part.inStock, 6);
      expect(part.unallocatedStock, 6);
      expect(part.stockString(), "6");
    });

    test("part builds a display name and image fallbacks", () {
      final part = InvenTreePart.fromJson({
        "IPN": "PN-10",
        "name": "Widget",
        "revision": "B",
        "category": 4,
        "category_detail": {"name": "Hardware", "description": "Fasteners"},
      });
      final fallback = InvenTreePart.fromJson({});

      expect(part.fullname, "PN-10 | Widget | B");
      expect(part.categoryName, "Hardware");
      expect(part.categoryDescription, "Fasteners");
      expect(part.image, InvenTreeAPI.staticImage);
      expect(part.thumbnail, InvenTreeAPI.staticThumb);
      expect(fallback.categoryName, isEmpty);
      expect(fallback.fullname, isEmpty);
    });

    test("requirements and pricing records expose numeric values", () {
      final requirements = InvenTreePartRequirements.fromJson({
        "can_build": "4",
        "ordering": 2,
        "building": 1,
        "scheduled_to_build": 3,
        "required_for_build_orders": 5,
        "allocated_to_build_orders": 2,
        "required_for_sales_orders": 6,
        "allocated_to_sales_orders": 4,
      });
      final pricing = InvenTreePartPricing.fromJson({
        "currency": "EUR",
        "overall_min": "1.2",
        "overall_max": 3.4,
        "override_min": "bad-price",
      });

      expect(requirements.canBuild, 4);
      expect(requirements.ordering, 2);
      expect(requirements.building, 1);
      expect(requirements.scheduledToBuild, 3);
      expect(requirements.requiredForBuildOrders, 5);
      expect(requirements.allocatedToBuildOrders, 2);
      expect(requirements.requiredForSalesOrders, 6);
      expect(requirements.allocatedToSalesOrders, 4);
      expect(pricing.currency, "EUR");
      expect(pricing.overallMin, 1.2);
      expect(pricing.overallMax, 3.4);
      expect(pricing.overrideMin, isNull);
      expect(pricing.overrideMinCurrency, "EUR");
      expect(InvenTreePartPricing.fromJson({}).currency, "USD");
    });
  });

  group("Stock models", () {
    test("stock item computes allocation and serialized display", () {
      final item = InvenTreeStockItem.fromJson({
        "pk": 9,
        "quantity": 1,
        "allocated": 0.25,
        "serial": "SN-09",
        "location": -1,
        "purchase_price": "2.50",
        "part_detail": {
          "units": "pcs",
          "thumbnail": "/media/part.png",
          "full_name": "Widget",
        },
      });

      expect(item.available, 0.75);
      expect(item.isSerialized(), isTrue);
      expect(item.serialOrQuantityDisplay(), "SN SN-09");
      expect(item.quantityString(), "0.75 / 1 pcs");
      expect(item.purchasePrice, 2.5);
      expect(item.hasPurchasePrice, isTrue);
      expect(item.locationName, "Unknown Location");
      expect(item.partName, "Widget");
      expect(item.partThumbnail, "/media/part.png");
      expect(item.defaultFilters()["cascade"], "false");
    });

    test("stock item falls back to legacy part and location fields", () {
      final item = InvenTreeStockItem.fromJson({
        "quantity": 3,
        "part__name": "Legacy widget",
        "part__thumbnail": "/legacy.png",
        "location": 2,
        "location__name": "Shelf 2",
      });

      expect(item.partName, "Legacy widget");
      expect(item.partThumbnail, "/legacy.png");
      expect(item.locationName, "Shelf 2");
      expect(item.isSerialized(), isFalse);
      expect(item.serialOrQuantityDisplay(), "3");
    });

    test("stock history formats quantity deltas and dates", () {
      final history = InvenTreeStockItemHistory.fromJson({
        "date": "2025-01-02T03:04:05Z",
        "deltas": {"quantity": "-1.5"},
        "user": 4,
        "user_detail": {"username": "operator"},
      });

      expect(history.date, DateTime.utc(2025, 1, 2, 3, 4, 5));
      expect(history.dateString, "2025-01-02");
      expect(history.quantityString, "-1.5");
      expect(history.userString, "operator");
      expect(history.defaultFilters(), {
        "ordering": "-date",
        "user_detail": "true",
      });
    });

    test("location path and stock-test details use nested data", () {
      final location = InvenTreeStockLocation.fromJson({
        "pk": 3,
        "pathstring": "Warehouse/Aisle 2/Bin 4",
        "items": 6,
      });
      final topLevel = InvenTreeStockLocation.fromJson({"pathstring": "Main"});
      final result = InvenTreeStockItemTestResult.fromJson({
        "template": 8,
        "test": "Voltage",
        "result": true,
        "value": "5V",
        "user_detail": {"username": "tech"},
      });

      expect(location.parentPathString, "Warehouse/Aisle 2");
      expect(location.itemcount, 6);
      expect(topLevel.parentPathString, "Top level stock location");
      expect(result.templateId, 8);
      expect(result.testName, "Voltage");
      expect(result.result, isTrue);
      expect(result.value, "5V");
      expect(result.username, "tech");
    });
  });

  test("company fields provide image fallbacks and default active state", () {
    final company = InvenTreeCompany.fromJson({
      "name": "Acme",
      "thumbnail": "/thumb.png",
      "is_supplier": true,
      "is_customer": false,
    });

    expect(company.name, "Acme");
    expect(company.image, "/thumb.png");
    expect(company.thumbnail, "/thumb.png");
    expect(company.active, isTrue);
    expect(company.isSupplier, isTrue);
    expect(company.isCustomer, isFalse);
    expect(company.formFields().containsKey("name"), isTrue);

    final emptyCompany = InvenTreeCompany.fromJson({});
    expect(emptyCompany.image, InvenTreeAPI.staticImage);
    expect(emptyCompany.thumbnail, InvenTreeAPI.staticThumb);
  });

  test("orders calculate completion and read date-only fields", () {
    final order = InvenTreeOrder.fromJson({
      "line_items": 4,
      "completed_lines": 4,
      "issue_date": "2025-01-01",
      "target_date": "2025-02-01T18:00:00Z",
      "total_price": "125.50",
      "order_currency": "USD",
      "project_code_detail": {"code": "PRJ-1", "description": "Prototype"},
    });

    expect(order.complete, isTrue);
    expect(order.issueDate, "2025-01-01");
    expect(order.targetDate, "2025-02-01");
    expect(order.totalPrice, 125.5);
    expect(order.totalPriceCurrency, "USD");
    expect(order.projectCode, "PRJ-1");
    expect(order.hasProjectCode, isTrue);
  });

  test("build progress is bounded and handles empty quantities", () {
    final partial = InvenTreeBuildOrder.fromJson({
      "quantity": 4,
      "completed": 2,
      "item_count": 2,
      "allocated_line_count": 2,
      "output_count": 1,
    });
    final overbuilt = InvenTreeBuildOrder.fromJson({
      "quantity": 2,
      "completed": 3,
    });
    final empty = InvenTreeBuildOrder.fromJson({"quantity": 0});

    expect(partial.progressPercent, 50);
    expect(partial.remaining, 2);
    expect(partial.areAllLinesAllocated, isTrue);
    expect(partial.canCompleteOrder, isFalse);
    expect(overbuilt.progressPercent, 100);
    expect(empty.progressPercent, 0);
  });

  test("sales and purchase order lines calculate progress boundaries", () {
    final salesLine = InvenTreeSOLineItem.fromJson({
      "quantity": 4,
      "allocated": 3,
      "shipped": 2,
      "available_stock": 5,
      "available_variant_stock": 1,
    });
    final emptyLine = InvenTreeSOLineItem.fromJson({"quantity": 0});
    final purchaseLine = InvenTreePOLineItem.fromJson({
      "quantity": 4,
      "received": 2,
    });

    expect(salesLine.allocatedRatio, 0.75);
    expect(salesLine.unallocatedQuantity, 1);
    expect(salesLine.progressRatio, 0.5);
    expect(salesLine.available, 6);
    expect(salesLine.isComplete, isFalse);
    expect(emptyLine.allocatedRatio, 0);
    expect(emptyLine.progressRatio, 0);
    expect(purchaseLine.progressRatio, 0.5);
    expect(purchaseLine.outstanding, 2);
    expect(purchaseLine.isComplete, isFalse);
  });
}
