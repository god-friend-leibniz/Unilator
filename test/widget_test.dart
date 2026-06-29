import 'package:flutter_test/flutter_test.dart';
import 'package:offline_dict/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const OfflineDictApp());

    // Verify that we see the app title.
    expect(find.text('Оффлайн Словари'), findsOneWidget);
  });
}
