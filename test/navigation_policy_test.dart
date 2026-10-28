import 'package:flutter_test/flutter_test.dart';

import 'package:odoo_mobileapp/navigation_policy.dart';

void main() {
  final server = Uri.parse('https://shop.example.com');

  NavigationTarget classify(String url) => classifyNavigation(Uri.parse(url), server);

  group('classifyNavigation', () {
    test('keeps pages on the Odoo server in the app', () {
      expect(classify('https://shop.example.com/web'), NavigationTarget.inApp);
      expect(classify('https://shop.example.com/odoo/action-123'), NavigationTarget.inApp);
      expect(classify('https://shop.example.com/my/orders?page=2'), NavigationTarget.inApp);
      expect(classify('about:blank'), NavigationTarget.inApp);
    });

    test('detects the Odoo login page as signed out', () {
      expect(classify('https://shop.example.com/web/login'), NavigationTarget.signedOut);
      expect(classify('https://shop.example.com/web/login/?redirect=%2Fweb'), NavigationTarget.signedOut);
    });

    test('sends WhatsApp, phone, email and other sites outside the app', () {
      expect(classify('https://wa.me/919999999999?text=Hi'), NavigationTarget.external);
      expect(classify('https://api.whatsapp.com/send?phone=91999'), NavigationTarget.external);
      expect(classify('whatsapp://send?phone=91999'), NavigationTarget.external);
      expect(classify('tel:+919999999999'), NavigationTarget.external);
      expect(classify('mailto:a@b.com'), NavigationTarget.external);
      expect(classify('https://www.odoo.com'), NavigationTarget.external);
    });
  });

  test('isLoginPage ignores other /web routes', () {
    expect(isLoginPage(Uri.parse('https://x/web/login')), isTrue);
    expect(isLoginPage(Uri.parse('https://x/web/login_successful')), isFalse);
    expect(isLoginPage(Uri.parse('https://x/web')), isFalse);
  });
}
