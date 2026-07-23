import 'dart:io';

import 'package:flutter/services.dart';

typedef MapStyleLoader = Future<String> Function(String path);

/// Resolves the style formats accepted by `maplibre_gl` to a URL or raw JSON.
///
/// Remote/custom-scheme URLs and raw JSON pass through unchanged. Absolute
/// files become `file:` URLs; other relative strings are loaded from the
/// Flutter asset bundle.
Future<String> resolveMapStyleString(
  String styleString, {
  MapStyleLoader? assetLoader,
}) async {
  final trimmed = styleString.trimLeft();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(styleString, 'styleString', 'must not be empty');
  }
  if (trimmed.startsWith('{')) return styleString;

  final uri = Uri.tryParse(styleString);
  if (uri != null && uri.scheme == 'file') return styleString;
  if (uri != null && uri.hasScheme) return styleString;
  if (File(styleString).isAbsolute) return Uri.file(styleString).toString();
  return (assetLoader ?? rootBundle.loadString)(styleString);
}
