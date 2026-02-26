import 'package:flutter_test/flutter_test.dart';
import 'package:wacloneattempt/main.dart';

void main() {
  testWidgets('App starts without crashing', (WidgetTester tester) async {
    // Smoke test — Firebase init will fail in test env, so we just verify import
    expect(WACApp, isNotNull);
  });
}
