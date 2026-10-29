import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n.dart';

/// Field names Odoo modules commonly use for phone numbers and emails.
const phoneFieldNames = {'phone', 'mobile', 'partner_phone', 'work_phone', 'mobile_phone', 'phone_mobile_search'};
const emailFieldNames = {'email', 'email_from', 'work_email', 'partner_email', 'email_normalized'};

enum ContactKind { phone, email, url }

/// How a char field should be treated, from its widget or (as Odoo modules
/// are inconsistent) its name.
ContactKind? contactKindOf(String name, String? widget) {
  if (widget == 'phone' || phoneFieldNames.contains(name)) return ContactKind.phone;
  if (widget == 'email' || emailFieldNames.contains(name)) return ContactKind.email;
  if (widget == 'url' || name == 'website') return ContactKind.url;
  return null;
}

String _digits(String phone) => phone.replaceAll(RegExp(r'[^0-9]'), '');

Future<void> _launch(BuildContext context, Uri uri) async {
  HapticFeedback.selectionClick();
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // No app for this scheme.
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('No app available to open this.'))));
  }
}

Future<void> callPhone(BuildContext context, String phone) => _launch(context, Uri(scheme: 'tel', path: phone));

Future<void> whatsApp(BuildContext context, String phone) =>
    _launch(context, Uri.parse('https://wa.me/${_digits(phone)}'));

Future<void> sendEmail(BuildContext context, String email) => _launch(context, Uri(scheme: 'mailto', path: email));

Future<void> openUrl(BuildContext context, String url) =>
    _launch(context, Uri.parse(url.startsWith('http') ? url : 'https://$url'));

Future<void> openMap(BuildContext context, String address) =>
    _launch(context, Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': address}));

/// Compact action buttons for a phone/email/url value.
class ContactButtons extends StatelessWidget {
  final ContactKind kind;
  final String value;

  const ContactButtons({super.key, required this.kind, required this.value});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    Widget button(IconData icon, String tip, VoidCallback onTap) => IconButton(
          icon: Icon(icon, size: 20, color: color),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: switch (kind) {
        ContactKind.phone => [
            button(Icons.call_outlined, tr('Call'), () => callPhone(context, value)),
            button(Icons.chat_outlined, tr('WhatsApp'), () => whatsApp(context, value)),
          ],
        ContactKind.email => [button(Icons.mail_outline, tr('Email'), () => sendEmail(context, value))],
        ContactKind.url => [button(Icons.open_in_new, tr('Open'), () => openUrl(context, value))],
      },
    );
  }
}

/// Bottom sheet offering call / WhatsApp / email for a record.
Future<void> showContactSheet(BuildContext context, {required String title, String? phone, String? email}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          if (phone != null) ...[
            ListTile(
              leading: const Icon(Icons.call_outlined),
              title: Text(tr('Call')),
              subtitle: Text(phone),
              onTap: () {
                Navigator.of(sheet).pop();
                callPhone(context, phone);
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: Text(tr('WhatsApp')),
              subtitle: Text(phone),
              onTap: () {
                Navigator.of(sheet).pop();
                whatsApp(context, phone);
              },
            ),
          ],
          if (email != null)
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: Text(tr('Email')),
              subtitle: Text(email),
              onTap: () {
                Navigator.of(sheet).pop();
                sendEmail(context, email);
              },
            ),
        ],
      ),
    ),
  );
}
