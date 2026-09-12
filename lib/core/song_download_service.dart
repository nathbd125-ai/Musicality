import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:musicality/core/globals.dart';
import 'package:musicality/core/my_audio_handler.dart';

class SongDownloadService {
  static final ValueNotifier<Set<String>> downloadedSongsNotifier =
      ValueNotifier<Set<String>>({});
  static final ValueNotifier<Set<String>> downloadingSongsNotifier =
      ValueNotifier<Set<String>>({});

  static Set<String> get downloadedSongs => downloadedSongsNotifier.value;
  static Set<String> get downloadingSongs => downloadingSongsNotifier.value;

  static bool isDownloaded(String id) => downloadedSongs.contains(id);
  static bool isDownloading(String id) => downloadingSongs.contains(id);

  /// Vérifie si la qualité locale actuelle du titre est inférieure aux préférences choisies par l'utilisateur.
  static bool checkNeedsUpgrade(MediaItem item) {
    if (!isDownloaded(item.id)) return false;

    final docPath = globalDocumentPath;
    final safeName = item.id.split('/').last.replaceAll(RegExp(r'(-hires)?\.(flac|mp3)$'), '');
    final localHiRes = File('$docPath/$safeName-hires.flac');
    final localFlac = File('$docPath/$safeName.flac');
    final localMp3 = File('$docPath/$safeName.mp3');

    final bool wantHiRes = isDownloadHiResNotifier.value;
    final bool wantFlac = isDownloadLosslessNotifier.value;
    final bool itemHasHiRes = item.extras?['hasHiRes'] as bool? ?? false;
    final bool itemHasFlac = item.extras?['hasFlac'] as bool? ?? true;

    bool targetHiRes = false;
    bool targetFlac = false;

    if (wantHiRes && itemHasHiRes) {
      targetHiRes = true;
    } else if ((wantHiRes || wantFlac) && itemHasFlac) {
      targetFlac = true;
    }

    final bool hasLocalHiRes = localHiRes.existsSync();
    final bool hasLocalFlac = localFlac.existsSync();
    final bool hasLocalMp3 = localMp3.existsSync();

    final int targetQuality = targetHiRes ? 3 : (targetFlac ? 2 : 1);
    final int currentQuality =
        hasLocalHiRes ? 3 : (hasLocalFlac ? 2 : (hasLocalMp3 ? 1 : 0));

    return (currentQuality > 0) && (targetQuality > currentQuality);
  }

  /// Renvoie le chemin d'accès local du fichier audio s'il est téléchargé, ou une chaîne vide.
  static String getLocalFilePath(MediaItem item) {
    final docPath = globalDocumentPath;
    final safeName = item.id.split('/').last.replaceAll(RegExp(r'(-hires)?\.(flac|mp3)$'), '');
    final localHiRes = File('$docPath/$safeName-hires.flac');
    if (localHiRes.existsSync()) return localHiRes.path;
    final localFlac = File('$docPath/$safeName.flac');
    if (localFlac.existsSync()) return localFlac.path;
    final localMp3 = File('$docPath/$safeName.mp3');
    if (localMp3.existsSync()) return localMp3.path;
    return '';
  }

  static final RegExp _audioExtRegex = RegExp(r'(-hires)?\.(flac|mp3)$');

  /// Scanne le répertoire local des documents pour identifier les musiques téléchargées.
  static Future<void> scanLocalFiles(List<MediaItem> playlist) async {
    if (playlist.isEmpty) return;
    final docDir = await getApplicationDocumentsDirectory();
    final Set<String> localIds = {};

    final Set<String> existingFiles = {};
    try {
      if (await docDir.exists()) {
        final entities = await docDir.list().toList();
        for (final entity in entities) {
          if (entity is File) {
            existingFiles.add(entity.uri.pathSegments.last);
          }
        }
      }
    } catch (e) {
      debugPrint("Erreur scan dossier local: $e");
    }

    for (var item in playlist) {
      final safeName = item.id.split('/').last.replaceAll(_audioExtRegex, '');
      if (existingFiles.contains('$safeName-hires.flac') ||
          existingFiles.contains('$safeName.flac') ||
          existingFiles.contains('$safeName.mp3')) {
        localIds.add(item.id);
      }
    }

    downloadedSongsNotifier.value = {...downloadedSongsNotifier.value, ...localIds};
  }

  /// Lance le téléchargement, la mise à niveau de qualité ou la suppression d'un titre.
  static Future<void> toggleDownload(MediaItem item) async {
    final docDir = await getApplicationDocumentsDirectory();
    final safeName = item.id.split('/').last.replaceAll(_audioExtRegex, '');

    final localHiRes = File('${docDir.path}/$safeName-hires.flac');
    final localFlac = File('${docDir.path}/$safeName.flac');
    final localMp3 = File('${docDir.path}/$safeName.mp3');

    final cacheHiRes = File('${docDir.path}/cache/$safeName-hires.flac');
    final cacheFlac = File('${docDir.path}/cache/$safeName.flac');
    final cacheMp3 = File('${docDir.path}/cache/$safeName.mp3');

    final bool wantHiRes = isDownloadHiResNotifier.value;
    final bool wantFlac = isDownloadLosslessNotifier.value;
    final bool hasFlac = item.extras?['hasFlac'] as bool? ?? true;
    final bool hasHiRes = item.extras?['hasHiRes'] as bool? ?? false;

    bool targetHiRes = false;
    bool targetFlac = false;

    if (wantHiRes && hasHiRes) {
      targetHiRes = true;
    } else if ((wantHiRes || wantFlac) && hasFlac) {
      targetFlac = true;
    }

    final bool hasLocalHiRes = localHiRes.existsSync();
    final bool hasLocalFlac = localFlac.existsSync();
    final bool hasLocalMp3 = localMp3.existsSync();

    final int targetQuality = targetHiRes ? 3 : (targetFlac ? 2 : 1);
    final int currentQuality =
        hasLocalHiRes ? 3 : (hasLocalFlac ? 2 : (hasLocalMp3 ? 1 : 0));

    final bool needsUpgrade =
        (currentQuality > 0) && (targetQuality > currentQuality);

    final bool downloadHiRes = targetHiRes;
    final bool downloadFlac = targetFlac;

    if (downloadedSongs.contains(item.id) && !needsUpgrade) {
      if (localHiRes.existsSync()) localHiRes.deleteSync();
      if (localFlac.existsSync()) localFlac.deleteSync();
      if (localMp3.existsSync()) localMp3.deleteSync();

      final updated = Set<String>.from(downloadedSongsNotifier.value)..remove(item.id);
      downloadedSongsNotifier.value = updated;

      if (globalAudioHandler is MyAudioHandler) {
        (globalAudioHandler as MyAudioHandler).updateSourceForId(item.id);
      }
    } else {
      if (downloadingSongs.contains(item.id)) return;

      if (needsUpgrade) {
        if (localHiRes.existsSync()) localHiRes.deleteSync();
        if (localFlac.existsSync()) localFlac.deleteSync();
        if (localMp3.existsSync()) localMp3.deleteSync();

        final updated = Set<String>.from(downloadedSongsNotifier.value)..remove(item.id);
        downloadedSongsNotifier.value = updated;
      }

      final updatedDownloading = Set<String>.from(downloadingSongsNotifier.value)..add(item.id);
      downloadingSongsNotifier.value = updatedDownloading;

      try {
        final baseUri = item.id.replaceAll(RegExp(r'(-hires)?\.(flac|mp3)$'), '');
        String downloadUrl;
        File fileToSave;
        File candidateCache;

        if (downloadHiRes) {
          downloadUrl = '$baseUri-hires.flac';
          fileToSave = localHiRes;
          candidateCache = cacheHiRes;
          // Si téléchargement en Hi-Res, suppression automatique des caches de qualité inférieure
          if (cacheFlac.existsSync()) {
            try {
              cacheFlac.deleteSync();
            } catch (_) {}
          }
          if (cacheMp3.existsSync()) {
            try {
              cacheMp3.deleteSync();
            } catch (_) {}
          }
        } else if (downloadFlac) {
          downloadUrl = '$baseUri.flac';
          fileToSave = localFlac;
          if (cacheHiRes.existsSync()) {
            candidateCache = cacheHiRes;
            fileToSave = localHiRes;
          } else {
            candidateCache = cacheFlac;
          }
          // Si téléchargement en FLAC, suppression automatique du cache MP3 inférieur
          if (cacheMp3.existsSync()) {
            try {
              cacheMp3.deleteSync();
            } catch (_) {}
          }
        } else {
          downloadUrl = '$baseUri.mp3';
          fileToSave = localMp3;
          candidateCache = cacheMp3;
        }

        bool extractedFromCache = false;

        // Extraction intelligente depuis le cache sans réseau si le fichier est complet
        if (candidateCache.existsSync()) {
          try {
            final client = HttpClient()
              ..connectionTimeout = const Duration(seconds: 3);
            final headReq = await client.headUrl(
              Uri.parse(downloadUrl.replaceAll('#', '%23')),
            );
            final headRes = await headReq.close();
            final expectedLength = headRes.contentLength;

            if (expectedLength > 0 &&
                candidateCache.lengthSync() >= expectedLength) {
              await candidateCache.copy(fileToSave.path);
              try {
                candidateCache.deleteSync();
              } catch (_) {}
              extractedFromCache = true;
            }
          } catch (_) {
            if (candidateCache.lengthSync() > 3 * 1024 * 1024) {
              await candidateCache.copy(fileToSave.path);
              try {
                candidateCache.deleteSync();
              } catch (_) {}
              extractedFromCache = true;
            }
          }
        }

        // Si non extrait du cache (fichier absent ou partiel), téléchargement réseau
        if (!extractedFromCache) {
          if (candidateCache.existsSync()) {
            try {
              candidateCache.deleteSync();
            } catch (_) {}
          }

          final client = HttpClient();
          final request = await client.getUrl(
            Uri.parse(downloadUrl.replaceAll('#', '%23')),
          );
          final response = await request.close();
          await response.pipe(fileToSave.openWrite());
        }

        if (fileToSave == localHiRes) {
          if (localFlac.existsSync()) localFlac.deleteSync();
          if (localMp3.existsSync()) localMp3.deleteSync();
        } else if (fileToSave == localFlac) {
          if (localHiRes.existsSync()) localHiRes.deleteSync();
          if (localMp3.existsSync()) localMp3.deleteSync();
        } else {
          if (localHiRes.existsSync()) localHiRes.deleteSync();
          if (localFlac.existsSync()) localFlac.deleteSync();
        }

        final nextDl = Set<String>.from(downloadingSongsNotifier.value)..remove(item.id);
        final nextDone = Set<String>.from(downloadedSongsNotifier.value)..add(item.id);
        downloadingSongsNotifier.value = nextDl;
        downloadedSongsNotifier.value = nextDone;

        if (globalAudioHandler is MyAudioHandler) {
          (globalAudioHandler as MyAudioHandler).updateSourceForId(item.id);
        }
      } catch (e) {
        debugPrint("Erreur téléchargement: $e");
        final nextDl = Set<String>.from(downloadingSongsNotifier.value)..remove(item.id);
        downloadingSongsNotifier.value = nextDl;
      }
    }
  }
}
