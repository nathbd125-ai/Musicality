import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:mmkv/mmkv.dart';
import 'package:musicality/core/models.dart';
import 'package:musicality/core/api_config.dart';
import 'package:musicality/core/lyrics_parser.dart';

class LyricsService {
  static final Map<String, List<LyricLine>> _lyricsCache = {};

  /// Notifie les écouteurs (UI du lecteur, mode studio, etc.) quand un LRC a été mis à jour
  static final ValueNotifier<String?> onLyricsUpdated = ValueNotifier<String?>(null);

  static const _channel = MethodChannel('com.musicality/cross_app_sync');
  static bool _crossAppSyncInitialized = false;

  /// Initialise l'écouteur de synchronisation inter-applications (Musicality <-> Musicality Studio)
  static void initCrossAppSync() {
    if (_crossAppSyncInitialized || kIsWeb || !Platform.isAndroid) return;
    _crossAppSyncInitialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLyricsReceived') {
        try {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final songId = args['songId'] as String? ?? '';
          final baseName = args['baseName'] as String? ?? '';
          final lrcContent = args['lrcContent'] as String? ?? '';

          if (baseName.isNotEmpty && lrcContent.isNotEmpty) {
            debugPrint(
                '>> [CrossAppSync] Paroles reçues de l\'autre version pour "$baseName" !');
            final parsed = LyricsParser.parse(lrcContent);
            await updateAndSaveLyrics(
              songId: songId.isNotEmpty ? songId : baseName,
              baseName: baseName,
              lrcContent: lrcContent,
              newLyrics: parsed,
              broadcast: false, // Évite la boucle infinie de broadcast
            );
          }
        } catch (e) {
          debugPrint('Erreur lors du traitement onLyricsReceived: $e');
        }
      }
    });
  }

  static bool hasCached(String songId) => _lyricsCache.containsKey(songId);

  static List<LyricLine>? getCached(String songId) => _lyricsCache[songId];

  static void setCached(String songId, List<LyricLine> lyrics) {
    _lyricsCache[songId] = lyrics;
    final baseName = getBaseName(songId);
    _lyricsCache[baseName] = lyrics;
  }

  static void clearCache() {
    _lyricsCache.clear();
  }

  static final RegExp _hiresExtRegex = RegExp(r'-hires\.(flac|mp3)$');
  static final RegExp _audioExtRegex = RegExp(r'\.(flac|mp3)$');

  static String getBaseName(String itemId) {
    String fileName;
    try {
      final uri = Uri.tryParse(itemId);
      fileName = (uri != null && uri.pathSegments.isNotEmpty)
          ? uri.pathSegments.last
          : itemId.split('/').last;
    } catch (_) {
      fileName = itemId.split('/').last;
    }
    return fileName
        .replaceAll(_hiresExtRegex, '')
        .replaceAll(_audioExtRegex, '');
  }

  /// Sauvegarde les nouvelles paroles en local, met à jour le cache mémoire,
  /// supprime tout ancien TTML, notifie l'UI et diffuse à l'autre application sur l'appareil.
  static Future<void> updateAndSaveLyrics({
    required String songId,
    required String baseName,
    required String lrcContent,
    required List<LyricLine> newLyrics,
    bool broadcast = true,
  }) async {
    _lyricsCache[songId] = newLyrics;
    _lyricsCache[baseName] = newLyrics;

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final localLrc = File('${docDir.path}/$baseName.lrc');
      await localLrc.writeAsString(lrcContent, flush: true);

      final localTtml = File('${docDir.path}/$baseName.ttml');
      if (localTtml.existsSync()) {
        try {
          localTtml.deleteSync();
        } catch (_) {}
      }

      try {
        final mmkv = MMKV.defaultMMKV();
        mmkv.encodeInt(
          'lrc_saved_time_$baseName',
          DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('Erreur de sauvegarde locale des paroles: $e');
    }

    // Notification réactive instantanée pour le lecteur courant
    onLyricsUpdated.value = baseName;

    // Diffusion vers l'autre package sur Android (com.musicality <-> com.musicality.studio)
    if (broadcast && !kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('broadcastLyricsUpdate', {
          'songId': songId,
          'baseName': baseName,
          'lrcContent': lrcContent,
        });
      } catch (e) {
        debugPrint('Erreur lors du broadcast cross-app: $e');
      }
    }
  }

  /// Récupération des paroles avec affichage immédiat 0ms (cache/local)
  /// et revalidation automatique en arrière-plan depuis le serveur VPS.
  static Future<List<LyricLine>> fetchLyrics(MediaItem item) async {
    final songId = item.id;
    final baseName = getBaseName(item.id);

    // 1. Cache mémoire : retour immédiat 0ms + revalidation distante en arrière-plan
    if (_lyricsCache.containsKey(songId)) {
      unawaited(revalidateLyrics(item));
      return _lyricsCache[songId]!;
    }
    if (_lyricsCache.containsKey(baseName)) {
      unawaited(revalidateLyrics(item));
      return _lyricsCache[baseName]!;
    }

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final localTtml = File('${docDir.path}/$baseName.ttml');
      final localLrc = File('${docDir.path}/$baseName.lrc');
      String lyricsContent = '';

      // 2. Cache disque local : affichage immédiat + revalidation distante en tâche de fond
      if (localLrc.existsSync()) {
        try {
          lyricsContent = await localLrc.readAsString();
        } catch (_) {
          try {
            final bytes = await localLrc.readAsBytes();
            lyricsContent = _decodeLyricsBytes(bytes);
          } catch (_) {
            localLrc.deleteSync();
          }
        }
      } else if (localTtml.existsSync()) {
        try {
          lyricsContent = await localTtml.readAsString();
        } catch (_) {
          try {
            lyricsContent = utf8.decode(await localTtml.readAsBytes(), allowMalformed: true);
          } catch (_) {
            localTtml.deleteSync();
          }
        }
      }

      if (lyricsContent.contains('<!DOCTYPE')) {
        lyricsContent = '';
      }

      if (lyricsContent.isNotEmpty) {
        final parsed = LyricsParser.parse(lyricsContent);
        _lyricsCache[songId] = parsed;
        _lyricsCache[baseName] = parsed;
        unawaited(revalidateLyrics(item));
        return parsed;
      }

      // 3. Aucun cache local : téléchargement direct depuis le VPS
      final downloaded = await _downloadFromRemote(baseName);
      if (downloaded != null && downloaded.isNotEmpty) {
        final parsed = LyricsParser.parse(downloaded);
        _lyricsCache[songId] = parsed;
        _lyricsCache[baseName] = parsed;
        return parsed;
      }
    } catch (e) {
      debugPrint('Erreur de récupération des paroles: $e');
    }

    final fallback = [
      LyricLine(
        time: Duration.zero,
        text: 'Paroles indisponibles pour ce titre',
      ),
    ];
    return fallback;
  }

  static final Set<String> _revalidating = {};

  /// Revalidation intelligente via HTTP conditionnel (ETag / If-Modified-Since).
  /// Si le VPS a un LRC modifié, il est téléchargé, sauvegardé et appliqué en direct sur les 2 versions.
  static Future<void> revalidateLyrics(MediaItem item) async {
    final baseName = getBaseName(item.id);
    final songId = item.id;
    if (_revalidating.contains(baseName)) return;
    _revalidating.add(baseName);

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final localLrc = File('${docDir.path}/$baseName.lrc');
      final localTtml = File('${docDir.path}/$baseName.ttml');

      final lrcUrl = Uri.parse(
        '${ApiConfig.baseUrl}/${Uri.encodeComponent('$baseName.lrc')}',
      );

      final headers = <String, String>{};
      String? savedEtag;
      try {
        final mmkv = MMKV.defaultMMKV();
        savedEtag = mmkv.decodeString('etag_$baseName');
      } catch (_) {}

      if (savedEtag != null && savedEtag.isNotEmpty) {
        headers['If-None-Match'] = savedEtag;
      } else if (localLrc.existsSync()) {
        try {
          final lastMod = localLrc.lastModifiedSync().toUtc();
          headers['If-Modified-Since'] = HttpDate.format(lastMod);
        } catch (_) {}
      }

      final response = await http
          .get(lrcUrl, headers: headers)
          .timeout(const Duration(seconds: 4));

      // 304 Not Modified : Le fichier sur le VPS est strictement identique
      if (response.statusCode == 304) {
        return;
      }

      // 200 OK : Le fichier a été mis à jour sur le VPS !
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final bool isLrcHtml = response.bodyBytes.length >= 9 &&
            String.fromCharCodes(response.bodyBytes.take(64))
                .toLowerCase()
                .contains('<!doctype');
        if (isLrcHtml) return;

        final newEtag = response.headers['etag'];
        if (newEtag != null && newEtag.isNotEmpty) {
          try {
            final mmkv = MMKV.defaultMMKV();
            mmkv.encodeString('etag_$baseName', newEtag);
          } catch (_) {}
        }

        final downloaded = _decodeLyricsBytes(response.bodyBytes);
        if (downloaded.trim().isEmpty) return;

        String currentLocal = '';
        if (localLrc.existsSync()) {
          try {
            currentLocal = await localLrc.readAsString();
          } catch (_) {}
        }

        // Si le contenu est différent du fichier local OU si on avait un ancien TTML
        if (downloaded.trim() != currentLocal.trim() || localTtml.existsSync()) {
          debugPrint(
              '>> [LyricsService] Nouveau LRC distant détecté pour "$baseName" ! Remplacement immédiat...');
          final parsed = LyricsParser.parse(downloaded);
          await updateAndSaveLyrics(
            songId: songId,
            baseName: baseName,
            lrcContent: downloaded,
            newLyrics: parsed,
            broadcast: true,
          );
        }
      }
    } catch (e) {
      debugPrint('Revalidation des paroles ($baseName) ignorée ou hors-ligne: $e');
    } finally {
      _revalidating.remove(baseName);
    }
  }

  /// Télécharge un fichier LRC ou TTML depuis le VPS
  static Future<String?> _downloadFromRemote(String baseName) async {
    final docDir = await getApplicationDocumentsDirectory();
    final localLrc = File('${docDir.path}/$baseName.lrc');

    // 1. Essai de téléchargement direct du fichier .lrc
    try {
      final lrcUrl = Uri.parse(
        '${ApiConfig.baseUrl}/${Uri.encodeComponent('$baseName.lrc')}',
      );
      final response =
          await http.get(lrcUrl).timeout(const Duration(seconds: 4));
      final bool isLrcHtml = response.bodyBytes.length >= 9 &&
          String.fromCharCodes(response.bodyBytes.take(64))
              .toLowerCase()
              .contains('<!doctype');

      if (response.statusCode == 200 &&
          response.bodyBytes.isNotEmpty &&
          !isLrcHtml) {
        final etag = response.headers['etag'];
        if (etag != null && etag.isNotEmpty) {
          try {
            final mmkv = MMKV.defaultMMKV();
            mmkv.encodeString('etag_$baseName', etag);
          } catch (_) {}
        }

        final downloaded = _decodeLyricsBytes(response.bodyBytes);
        if (downloaded.isNotEmpty) {
          await localLrc.writeAsString(downloaded, flush: true);
          return downloaded;
        }
      }
    } catch (_) {}

    // 2. Fallback ancien TTML si présent
    try {
      final localTtml = File('${docDir.path}/$baseName.ttml');
      final ttmlUrl = Uri.parse(
        '${ApiConfig.baseUrl}/${Uri.encodeComponent('$baseName.ttml')}',
      );
      final ttmlRes =
          await http.get(ttmlUrl).timeout(const Duration(seconds: 2));
      final bool isTtmlHtml = ttmlRes.bodyBytes.length >= 9 &&
          String.fromCharCodes(ttmlRes.bodyBytes.take(64))
              .toLowerCase()
              .contains('<!doctype');

      if (ttmlRes.statusCode == 200 &&
          ttmlRes.bodyBytes.isNotEmpty &&
          !isTtmlHtml) {
        final ttmlContent = utf8.decode(ttmlRes.bodyBytes, allowMalformed: true);
        await localTtml.writeAsString(ttmlContent, flush: true);
        return ttmlContent;
      }
    } catch (_) {}

    return null;
  }

  static String _decodeLyricsBytes(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1
          .decode(bytes)
          .replaceAll('\u009C', 'œ')
          .replaceAll('\u008C', 'Œ')
          .replaceAll('\u0092', '’');
    }
  }
}
