import "package:flutter_test/flutter_test.dart";

import "../setup.dart";
import "../support/profile_security_flow.dart";

void main() {
  setupTestEnv();

  testWidgets("server profile UI rejects remote HTTP", (tester) async {
    await runProfileSecurityFlow(tester);
  });
}
