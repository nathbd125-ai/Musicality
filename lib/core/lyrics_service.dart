import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:musicality/core/models.dart';
import 'package:musicality/core/api_config.dart';
import 'package:musicality/core/lyrics_parser.dart';

class LyricsService {
  static final Map<String, List<LyricLine>> _lyricsCache = {};

  static bool hasCached(String songId) => _lyricsCache.containsKey(songId);

  static List<LyricLine>? getCached(String songId) => _lyricsCache[songId];

  static void setCached(String songId, List<LyricLine> lyrics) {
    _lyricsCache[songId] = lyrics;
  }

  static void clearCache() {
    _lyricsCache.clear();
  }

  static Future<List<LyricLine>> fetchLyrics(MediaItem item) async {
    final songId = item.id;
    if (_lyricsCache.containsKey(songId)) {
      return _lyricsCache[songId]!;
    }

    final decodedName = Uri.decodeComponent(item.id.split('/').last);
    final baseName = decodedName
        .replaceAll(RegExp(r'-hires\.(flac|mp3)$'), '')
        .replaceAll(RegExp(r'\.(flac|mp3)$'), '');

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final localTtml = File('${docDir.path}/$baseName.ttml');
      final localLrc = File('${docDir.path}/$baseName.lrc');
      String lyricsContent = "";

      if (localTtml.existsSync()) {
        try {
          lyricsContent = await localTtml.readAsString();
        } catch (_) {
          try {
            lyricsContent = utf8.decode(await localTtml.readAsBytes(), allowMalformed: true);
          } catch (_) {
            localTtml.deleteSync();
          }
        }
      } else if (localLrc.existsSync()) {
        try {
          lyricsContent = await localLrc.readAsString();
        } catch (_) {
          try {
            final bytes = await localLrc.readAsBytes();
            try {
              lyricsContent = utf8.decode(bytes);
            } catch (_) {
              lyricsContent = latin1
                  .decode(bytes)
                  .replaceAll('\u009C', 'œ')
                  .replaceAll('\u008C', 'Œ')
                  .replaceAll('\u0092', '’');
            }
          } catch (_) {
            localLrc.deleteSync();
          }
        }
        // Purge de sécurité si un cache local contient les mauvaises paroles (ex: Afro Trap 11 avec les paroles de Part 7)
        if (baseName.contains('11') &&
            lyricsContent.toLowerCase().contains('puissance')) {
          lyricsContent = "";
          localLrc.deleteSync();
        }
      }

      if (lyricsContent.contains('<!DOCTYPE')) {
        lyricsContent = "";
      }

      // Si pas encore de paroles en local, téléchargement distant
      if (lyricsContent.isEmpty) {
        // 1. Essai de téléchargement du fichier officiel Apple Music .ttml
        try {
          final ttmlUrl = Uri.parse(
            '${ApiConfig.baseUrl}/${Uri.encodeComponent('$baseName.ttml')}',
          );
          final ttmlRes =
              await http.get(ttmlUrl).timeout(const Duration(seconds: 2));
          final bool isTtmlHtml = ttmlRes.bodyBytes.length >= 9 &&
              String.fromCharCodes(ttmlRes.bodyBytes.take(64)).toLowerCase().contains('<!doctype');
          if (ttmlRes.statusCode == 200 &&
              ttmlRes.bodyBytes.isNotEmpty &&
              !isTtmlHtml) {
            lyricsContent = utf8.decode(ttmlRes.bodyBytes, allowMalformed: true);
            await localTtml.writeAsString(lyricsContent);
          }
        } catch (_) {}

        // 2. Si pas de .ttml, téléchargement du fichier .lrc
        if (lyricsContent.isEmpty) {
          try {
            final lrcUrl = Uri.parse(
              '${ApiConfig.baseUrl}/${Uri.encodeComponent('$baseName.lrc')}',
            );
            final response =
                await http.get(lrcUrl).timeout(const Duration(seconds: 4));
            final bool isLrcHtml = response.bodyBytes.length >= 9 &&
                String.fromCharCodes(response.bodyBytes.take(64)).toLowerCase().contains('<!doctype');
            if (response.statusCode == 200 &&
                response.bodyBytes.isNotEmpty &&
                !isLrcHtml) {
              String downloaded = "";
              try {
                downloaded = utf8.decode(response.bodyBytes);
              } catch (_) {
                downloaded = latin1
                    .decode(response.bodyBytes)
                    .replaceAll('\u009C', 'œ')
                    .replaceAll('\u008C', 'Œ')
                    .replaceAll('\u0092', '’');
              }
              if (downloaded.isNotEmpty) {
                lyricsContent = downloaded;
                await localLrc.writeAsString(lyricsContent);
              }
            }
          } catch (_) {}
        }
      }

      if (lyricsContent.isNotEmpty) {
        final parsed = LyricsParser.parse(lyricsContent);
        _lyricsCache[songId] = parsed;
        return parsed;
      }
    } catch (e) {
      debugPrint("Erreur de récupération des paroles: $e");
    }

    final fallback = [
      LyricLine(
        time: Duration.zero,
        text: "Paroles indisponibles pour ce titre",
      ),
    ];
    return fallback;
  }
}
