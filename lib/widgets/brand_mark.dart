import 'package:flutter/material.dart';

import '../theme.dart';

/// The app's logo: the company logo when [logoUrl] is known (Odoo serves it
/// publicly per database), else a neutral mark.
class BrandMark extends StatelessWidget {
  final double size;

  /// On the coloured brand background (login header, splash).
  final bool onBrand;
  final String? logoUrl;

  const BrandMark({super.key, this.size = 56, this.onBrand = true, this.logoUrl});

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onBrand ? Colors.white.withValues(alpha: 0.16) : brandOf(context),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(Icons.apps_rounded, color: Colors.white, size: size * 0.56),
    );
    final url = logoUrl;
    if (url == null) return mark;
    return Container(
      height: size,
      constraints: BoxConstraints(minWidth: size, maxWidth: size * 3.2),
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(size * 0.28)),
      child: Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Icon(Icons.apps_rounded, color: brandOf(context), size: size * 0.5),
      ),
    );
  }
}
