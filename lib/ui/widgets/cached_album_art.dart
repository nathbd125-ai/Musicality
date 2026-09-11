import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:musicality/core/globals.dart';

final Set<String> _knownExistingCovers = {};

void registerExistingCover(String fileName) {
  _knownExistingCovers.add(fileName);
}

bool _checkCoverExists(String fileName, File file) {
  if (_knownExistingCovers.contains(fileName)) return true;
  if (file.existsSync()) {
    _knownExistingCovers.add(fileName);
    return true;
  }
  return false;
}

Widget getLocalOrNetworkImage(MediaItem item, {double? width, double? height}) {
  final String fileName = item.artUri?.pathSegments.last ?? '${getSafeFileName(getBaseId(item.id))}.jpg';
  final coverFile = File(
    '$globalDocumentPath/$fileName',
  );
  final int dynamicCacheWidth = width != null ? (width * 3).toInt() : 300;

  if (_checkCoverExists(fileName, coverFile)) {
    return Image.file(
      coverFile,
      width: width,
      height: height,
      cacheWidth: dynamicCacheWidth,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) {
        _knownExistingCovers.remove(fileName);
        // En cas de fichier corrompu en cache, on fallback sur le réseau
        return Image.network(item.artUri.toString(), fit: BoxFit.cover);
      },
    );
  } else {
    return Image.network(
      item.artUri.toString(),
      width: width,
      height: height,
      cacheWidth: dynamicCacheWidth,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
    );
  }
}

ImageProvider getLocalOrNetworkImageProvider(MediaItem item) {
  final String fileName = item.artUri?.pathSegments.last ?? '${getSafeFileName(getBaseId(item.id))}.jpg';
  final coverFile = File(
    '$globalDocumentPath/$fileName',
  );
  if (_checkCoverExists(fileName, coverFile)) {
    try {
      return FileImage(coverFile);
    } catch (e) {
      _knownExistingCovers.remove(fileName);
      return NetworkImage(item.artUri.toString());
    }
  } else {
    return NetworkImage(item.artUri.toString());
  }
}

Widget getLocalOrNetworkImageSuperBlurred(MediaItem item) {
  final String fileName = item.artUri?.pathSegments.last ?? '${getSafeFileName(getBaseId(item.id))}.jpg';
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
        return Image.network(item.artUri.toString(), fit: BoxFit.cover, cacheWidth: 32);
      },
    );
  } else {
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
