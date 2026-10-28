import 'package:flutter_test/flutter_test.dart';

import 'package:odoo_mobileapp/main.dart';
import 'package:odoo_mobileapp/widgets/brand_mark.dart';

void main() {
  testWidgets('App boots to splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MobileApp());
    expect(find.byType(BrandMark), findsOneWidget);
  });
}
