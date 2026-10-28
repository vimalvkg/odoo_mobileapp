import 'package:flutter_test/flutter_test.dart';

import 'package:tailorline_mobile/main.dart';

void main() {
  testWidgets('App boots to splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const TailorlineApp());
    expect(find.text('Tailorline'), findsOneWidget);
  });
}
