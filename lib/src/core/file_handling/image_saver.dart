import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Saves raw image bytes (original format) to the device photo gallery.
class ImageSaver {
  static const MethodChannel _channel = MethodChannel('ereader/save_image');

  /// Saves [bytes] (the image's original format) to the gallery.
  ///
  /// [mimeType] and [fileName] are used to pick the right extension and
  /// display name in the gallery. Returns `true` on success.
  static Future<bool> saveToGallery({
    required Uint8List bytes,
    required String mimeType,
    required String fileName,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('saveImage', {
        'bytes': bytes,
        'mimeType': mimeType,
        'fileName': fileName,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Best-effort MIME type from a file path/url (e.g. `images/a.jpg`).
  static String mimeTypeFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.avif')) return 'image/avif';
    return 'image/jpeg';
  }

  /// Extracts a safe file name (basename with extension) from a url/path.
  static String fileNameFromUrl(String url) {
    final cleaned = url.split('?').first.split('#').first;
    final segments = cleaned.split('/');
    final last = segments.isEmpty ? '' : segments.last;
    if (last.isNotEmpty && last.contains('.')) return last;
    final ext = switch (mimeTypeFromUrl(url)) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      'image/svg+xml' => 'svg',
      _ => 'jpg',
    };
    return 'ereader_image_${DateTime.now().millisecondsSinceEpoch}.$ext';
  }
}
