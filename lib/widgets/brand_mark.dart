import 'package:flutter/material.dart';

import '../theme.dart';

/// The app's logo. Swap the icon for the company logo asset here and every
/// screen (splash, login) follows.
class BrandMark extends StatelessWidget {
  final double size;

  /// On the coloured brand background (login header, splash).
  final bool onBrand;

  const BrandMark({super.key, this.size = 56, this.onBrand = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onBrand ? Colors.white.withValues(alpha: 0.16) : brandColor,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(Icons.apps_rounded, color: Colors.white, size: size * 0.56),
    );
  }
}
