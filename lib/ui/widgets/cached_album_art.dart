import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:musicality/core/globals.dart';

Widget getLocalOrNetworkImage(MediaItem item, {double? width, double? height}) {
  final String fileName = item.artUri?.pathSegments.last ?? '${getSafeFileName(getBaseId(item.id))}.jpg';
  final coverFile = File(
    '$globalDocumentPath/$fileName',
  );
  final int dynamicCacheWidth = width != null ? (width * 3).toInt() : 300;

  if (coverFile.existsSync()) {
    return Image.file(
      coverFile,
      width: width,
      height: height,
      cacheWidth: dynamicCacheWidth,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) {
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
  if (coverFile.existsSync()) {
    try {
      return FileImage(coverFile);
    } catch (e) {
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
  if (coverFile.existsSync()) {
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
