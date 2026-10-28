import 'package:flutter/material.dart';

import '../odoo/rpc.dart';
import 'odoo_image.dart';

/// A record's photo from Odoo (`avatar_128`/`image_128`), loaded lazily with
/// the session; falls back to a coloured initial when the record has no
/// photo (Odoo's default avatars are SVGs, which also fall back).
class RecordAvatar extends StatelessWidget {
  final OdooRpc rpc;
  final String model;
  final int? id;

  /// Image field to load, or null when the model has none.
  final String? imageField;
  final String text;
  final double size;
  final bool circle;

  const RecordAvatar({
    super.key,
    required this.rpc,
    required this.model,
    required this.id,
    required this.imageField,
    required this.text,
    this.size = 40,
    this.circle = true,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = LetterAvatar(text: text, size: size, circle: circle);
    final field = imageField;
    final recordId = id;
    if (field == null || recordId == null) return fallback;
    final image = Image.network(
      rpc.imageUrl(model, recordId, field),
      headers: rpc.imageHeaders,
      width: size,
      height: size,
      fit: BoxFit.cover,
      frameBuilder: (_, child, frame, sync) => frame == null && !sync ? fallback : child,
      errorBuilder: (_, _, _) => fallback,
    );
    return circle
        ? ClipOval(child: image)
        : ClipRRect(borderRadius: BorderRadius.circular(size / 4), child: image);
  }
}

/// The best small image field a model offers, if any.
String? imageFieldOf(Map<String, Map<String, dynamic>> fields) {
  for (final name in const ['avatar_128', 'image_128']) {
    if (fields.containsKey(name)) return name;
  }
  return null;
}
