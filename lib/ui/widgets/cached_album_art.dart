import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:http/http.dart' as http;
import 'package:musicality/core/globals.dart';

final Set<String> _knownExistingCovers = {};
final Set<String> _knownMissingCovers = {};
final Set<String> _pendingCoverDownloads = {};

bool _isCoverCacheInitialized = false;

/// Scans the document directory asynchronously in the background to populate the in-memory cover cache.
/// Completely prevents synchronous file system calls during list scrolling.
Future<void> initCoverCache() async {
  if (_isCoverCacheInitialized) return;
  _isCoverCacheInitialized = true;
  try {
    final dir = Directory(globalDocumentPath);
    if (await dir.exists()) {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.jpg')) {
          final segments = entity.uri.pathSegments;
          if (segments.isNotEmpty) {
            final name = segments.last.isNotEmpty ? segments.last : segments[segments.length - 2];
            _knownExistingCovers.add(name);
          }
        }
      }
    }
  } catch (e) {
    debugPrint("Erreur initCoverCache: $e");
  }
}

void registerExistingCover(String fileName) {
  _knownMissingCovers.remove(fileName);
  _knownExistingCovers.add(fileName);
}

void _triggerBackgroundCoverDownload(MediaItem item, String fileName, File coverFile) {
  if (item.artUri == null || _pendingCoverDownloads.contains(fileName)) return;
  _pendingCoverDownloads.add(fileName);
  http.get(item.artUri!).then((response) async {
    if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
      await coverFile.writeAsBytes(response.bodyBytes);
      registerExistingCover(fileName);
    }
  }).catchError((e) {
    debugPrint("Erreur téléchargement cover $fileName : $e");
  }).whenComplete(() {
    _pendingCoverDownloads.remove(fileName);
  });
}

bool _checkCoverExists(String fileName, File file) {
  if (_knownExistingCovers.contains(fileName)) return true;
  if (_knownMissingCovers.contains(fileName)) return false;
  if (file.existsSync()) {
    _knownExistingCovers.add(fileName);
    return true;
  } else {
    _knownMissingCovers.add(fileName);
    return false;
  }
}

String _getCoverFileName(MediaItem item) {
  if (item.artUri != null && item.artUri!.pathSegments.isNotEmpty) {
    return item.artUri!.pathSegments.last;
  }
  return '${getSafeFileName(getBaseId(item.id))}.jpg';
}

Widget getLocalOrNetworkImage(MediaItem item, {double? width, double? height}) {
  final String fileName = _getCoverFileName(item);
  final coverFile = File(
    '$globalDocumentPath/$fileName',
  );
  final int dynamicCacheWidth = width != null ? (width * 3).toInt() : 300;
  final FilterQuality quality =
      (width != null && width <= 80) ? FilterQuality.medium : FilterQuality.high;

  if (_checkCoverExists(fileName, coverFile)) {
    return Image.file(
      coverFile,
      width: width,
      height: height,
      cacheWidth: dynamicCacheWidth,
      fit: BoxFit.cover,
      filterQuality: quality,
      errorBuilder: (context, error, stackTrace) {
        _knownExistingCovers.remove(fileName);
        _knownMissingCovers.add(fileName);
        // En cas de fichier corrompu en cache, on fallback sur le réseau et re-téléchargement
        _triggerBackgroundCoverDownload(item, fileName, coverFile);
        return Image.network(item.artUri.toString(), fit: BoxFit.cover, filterQuality: quality);
      },
    );
  } else {
    _triggerBackgroundCoverDownload(item, fileName, coverFile);
    return Image.network(
      item.artUri.toString(),
      width: width,
      height: height,
      cacheWidth: dynamicCacheWidth,
      fit: BoxFit.cover,
      filterQuality: quality,
    );
  }
}

ImageProvider getLocalOrNetworkImageProvider(MediaItem item) {
  final String fileName = _getCoverFileName(item);
  final coverFile = File(
    '$globalDocumentPath/$fileName',
  );
  if (_checkCoverExists(fileName, coverFile)) {
    try {
      return FileImage(coverFile);
    } catch (e) {
      _knownExistingCovers.remove(fileName);
      _triggerBackgroundCoverDownload(item, fileName, coverFile);
      return NetworkImage(item.artUri.toString());
    }
  } else {
    _triggerBackgroundCoverDownload(item, fileName, coverFile);
    return NetworkImage(item.artUri.toString());
  }
}

Widget getLocalOrNetworkImageSuperBlurred(MediaItem item) {
  final String fileName = _getCoverFileName(item);
  final coverFile = File(
    '$globalDocumentPath/$fileName',
  );
  if (_checkCoverExists(fileName, coverFile)) {
    return Image.file(
      coverFile,
      cacheWidth: 32, // Downsample for DLSS-style hardware blur
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) {
        _triggerBackgroundCoverDownload(item, fileName, coverFile);
        return Image.network(item.artUri.toString(), fit: BoxFit.cover, cacheWidth: 32);
      },
    );
  } else {
    _triggerBackgroundCoverDownload(item, fileName, coverFile);
    return Image.network(
      item.artUri.toString(),
      cacheWidth: 32,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) =>
          Container(color: Colors.black),
    );
  }
}

/// Précharge en mémoire vive (RAM) les pochettes d'albums spécifiées
/// pour éliminer tout micro-temps de chargement visuel au défilement ou à la lecture.
void precacheSongCovers(
  BuildContext context,
  List<MediaItem> items, {
  int count = 10,
}) {
  if (items.isEmpty || !context.mounted) return;
  final toPreload = items.take(count);
  for (final item in toPreload) {
    try {
      final provider = getLocalOrNetworkImageProvider(item);
      precacheImage(provider, context).catchError((_) {});
    } catch (_) {}
  }
}

