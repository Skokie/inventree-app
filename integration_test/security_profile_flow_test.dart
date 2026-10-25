import "package:flutter_test/flutter_test.dart";
import "package:integration_test/integration_test.dart";

import "../test/support/profile_security_flow.dart";

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("rejects remote HTTP and accepts a loopback server", (
    tester,
  ) async {
    await runProfileSecurityFlow(tester);
  });
}
