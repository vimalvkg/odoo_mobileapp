import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../odoo/menus.dart';
import '../theme.dart';

/// Decodes a base64 image, accepting a `data:` URI prefix.
Uint8List? decodeOdooImage(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  final comma = value.indexOf(',');
  final b64 = value.startsWith('data:') && comma >= 0 ? value.substring(comma + 1) : value;
  try {
    return base64Decode(b64.replaceAll(RegExp(r'\s'), ''));
  } on FormatException {
    return null;
  }
}

bool _looksLikeSvg(Uint8List bytes) {
  final head = utf8.decode(bytes.take(256).toList(), allowMalformed: true).trimLeft();
  return head.startsWith('<?xml') || head.startsWith('<svg');
}

/// Odoo serves both raster images and SVGs (default avatars, app icons).
class OdooImage extends StatelessWidget {
  final Uint8List bytes;
  final double size;
  final Widget fallback;

  const OdooImage({super.key, required this.bytes, required this.size, required this.fallback});

  @override
  Widget build(BuildContext context) {
    if (_looksLikeSvg(bytes)) {
      return SvgPicture.memory(bytes, width: size, height: size, fit: BoxFit.contain);
    }
    return Image.memory(
      bytes,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

class LetterAvatar extends StatelessWidget {
  final String text;
  final double size;
  final bool circle;

  const LetterAvatar({super.key, required this.text, required this.size, this.circle = false});

  @override
  Widget build(BuildContext context) {
    final color = colorFor(text);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, 0.15)!, color],
        ),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(size / 4),
      ),
      child: Text(
        text.trim().isEmpty ? '?' : text.trim().characters.first.toUpperCase(),
        style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}

/// An installed app's icon: uploaded icon data, else the module's static
/// icon file, else the first letter of its name.
class AppIcon extends StatelessWidget {
  final OdooMenu app;
  final String serverUrl;
  final double size;

  const AppIcon({super.key, required this.app, required this.serverUrl, this.size = 56});

  @override
  Widget build(BuildContext context) {
    final fallback = LetterAvatar(text: app.name, size: size);
    final Widget image;
    final bytes = decodeOdooImage(app.iconData);
    final parts = app.webIcon?.split(',');
    if (bytes != null) {
      image = OdooImage(bytes: bytes, size: size, fallback: fallback);
    } else if (parts != null && parts.length == 2 && parts[1].contains('/')) {
      final url = '$serverUrl/${parts[0]}/${parts[1]}';
      image = url.endsWith('.svg')
          ? SvgPicture.network(url, width: size, height: size, placeholderBuilder: (_) => fallback)
          : Image.network(url, width: size, height: size, errorBuilder: (_, _, _) => fallback);
    } else {
      return fallback;
    }
    return ClipRRect(borderRadius: BorderRadius.circular(size / 4), child: image);
  }
}
