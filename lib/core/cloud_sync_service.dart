import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mmkv/mmkv.dart';
import 'package:musicality/core/globals.dart';

Timer? _autoSyncTimer;

Future<void> performCloudBackup() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    Map<String, List<String>> firestoreContents = {};
    playlistContentsNotifier.value.forEach((key, value) {
      firestoreContents[key] = value.toList();
    });
    final data = {
      'likedSongs': likedSongsNotifier.value.toList(),
      'customPlaylists': customPlaylistsNotifier.value,
      'playlistContents': firestoreContents,
      'playlistImages': playlistImagesNotifier.value,
      'searchHistory': searchHistoryNotifier.value,
      'artistScores': artistScoresNotifier.value,
      'artistListeningTime': artistListeningTimeNotifier.value,
      'songPlayCount': songPlayCountNotifier.value,
      'settings': {
        'isLossless': isLosslessNotifier.value,
        'isHiRes': isHiResNotifier.value,
        'isDownloadLossless': isDownloadLosslessNotifier.value,
        'isDownloadHiRes': isDownloadHiResNotifier.value,
        'isCacheEnabled': isCacheEnabledNotifier.value,
        'cacheLimit': cacheLimitNotifier.value,
        'isCrossfadeEnabled': isCrossfadeEnabledNotifier.value,
        'crossfadeDuration': crossfadeDurationNotifier.value,
        'isHapticFeedbackEnabled': isHapticFeedbackEnabledNotifier.value,
      },
      'lastSync': FieldValue.serverTimestamp(),
    };
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set(data);
    final mmkv = MMKV.defaultMMKV();
    mmkv.encodeBool('pendingCloudSync', false);
    debugPrint("☁️ Sauvegarde auto réussie");
  } catch (e) {
    debugPrint("❌ Erreur de sauvegarde auto : $e");
  }
}

void triggerAutoSync() {
  if (FirebaseAuth.instance.currentUser == null) return;

  final mmkv = MMKV.defaultMMKV();
  mmkv.encodeBool('pendingCloudSync', true);

  _autoSyncTimer?.cancel();
  _autoSyncTimer = Timer(const Duration(seconds: 5), () {
    performCloudBackup();
  });
}

Future<void> performCloudRestore() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    final mmkv = MMKV.defaultMMKV();
    final hasPendingSync = mmkv.decodeBool('pendingCloudSync');

    if (hasPendingSync) {
      debugPrint("Sync pending, pushing local to cloud instead of restoring");
      await performCloudBackup();
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (doc.exists && doc.data() != null) {
      final data = doc.data()!;

      if (data['likedSongs'] != null) {
        likedSongsNotifier.value = List<String>.from(
          data['likedSongs'],
        ).map(normalizeSongId).toSet();
      }
      if (data['customPlaylists'] != null) {
        customPlaylistsNotifier.value = List<String>.from(
          data['customPlaylists'],
        );
      }
      if (data['searchHistory'] != null) {
        searchHistoryNotifier.value = List<String>.from(data['searchHistory']);
      }
      if (data['artistScores'] != null) {
        final Map<String, int> rawScores = Map<String, int>.from(data['artistScores']);
        final Map<String, int> cleanScores = {};
        for (var entry in rawScores.entries) {
          String key = entry.key;
          if (key.toLowerCase() == 'the creator') continue; // Avoid double-counting
          if (key == 'Tyler') {
            key = 'Tyler The Creator';
          }
          final correctArtists = extractArtists(key);
          for (var a in correctArtists) {
            if (a == 'Inconnu') continue;
            cleanScores[a] = (cleanScores[a] ?? 0) + entry.value;
          }
        }
        artistScoresNotifier.value = cleanScores;
      }
      if (data['artistListeningTime'] != null) {
        final Map<String, int> rawTimes = Map<String, int>.from(data['artistListeningTime']);
        final Map<String, int> cleanTimes = {};
        for (var entry in rawTimes.entries) {
          String key = entry.key;
          if (key.toLowerCase() == 'the creator') continue; // Avoid double-counting
          if (key == 'Tyler') {
            key = 'Tyler The Creator';
          }
          final correctArtists = extractArtists(key);
          for (var a in correctArtists) {
            if (a == 'Inconnu') continue;
            cleanTimes[a] = (cleanTimes[a] ?? 0) + entry.value;
          }
        }
        artistListeningTimeNotifier.value = cleanTimes;
        triggerAutoSync(); // Re-push the cleaned data to the cloud
      }
      if (data['songPlayCount'] != null) {
        final Map<String, dynamic> rawCounts = data['songPlayCount'];
        final Map<String, int> cleanCounts = {};
        rawCounts.forEach((key, value) {
          cleanCounts[normalizeSongId(key)] = (cleanCounts[normalizeSongId(key)] ?? 0) + (value as int);
        });
        songPlayCountNotifier.value = cleanCounts;
      }
      if (data['playlistImages'] != null) {
        playlistImagesNotifier.value = Map<String, String>.from(
          data['playlistImages'],
        );
      }

      if (data['playlistContents'] != null) {
        final Map<String, dynamic> rawContents = data['playlistContents'];
        Map<String, Set<String>> restoredContents = {};
        rawContents.forEach((key, value) {
          restoredContents[key] = List<String>.from(value).map(normalizeSongId).toSet();
        });
        playlistContentsNotifier.value = restoredContents;
      }

      if (data['settings'] != null) {
        final settings = data['settings'];
        if (settings['isLossless'] != null) {
          isLosslessNotifier.value = settings['isLossless'] as bool;
        }
        if (settings['isHiRes'] != null) {
          isHiResNotifier.value = settings['isHiRes'] as bool;
        }
        if (settings['isDownloadLossless'] != null) {
          isDownloadLosslessNotifier.value =
              settings['isDownloadLossless'] as bool;
        }
        if (settings['isDownloadHiRes'] != null) {
          isDownloadHiResNotifier.value = settings['isDownloadHiRes'] as bool;
        }
        if (settings['isCacheEnabled'] != null) {
          isCacheEnabledNotifier.value = settings['isCacheEnabled'] as bool;
        }
        if (settings['cacheLimit'] != null) {
          cacheLimitNotifier.value = settings['cacheLimit'] as int;
        }
        if (settings['isCrossfadeEnabled'] != null) {
          isCrossfadeEnabledNotifier.value = settings['isCrossfadeEnabled'] as bool;
        }
        if (settings['crossfadeDuration'] != null) {
          final int cd = (settings['crossfadeDuration'] as num).toInt();
          crossfadeDurationNotifier.value = (cd < 1 || cd > 12) ? 5 : cd;
        }
        if (settings['isHapticFeedbackEnabled'] != null) {
          isHapticFeedbackEnabledNotifier.value =
              settings['isHapticFeedbackEnabled'] as bool;
        }
      }

      // Force la sauvegarde locale immédiate pour que le téléphone soit à jour
      final mmkv = MMKV.defaultMMKV();
      mmkv.encodeBool('isCrossfadeEnabled', isCrossfadeEnabledNotifier.value);
      mmkv.encodeInt('crossfadeDuration', crossfadeDurationNotifier.value);
      mmkv.encodeBool(
        'isHapticFeedbackEnabled',
        isHapticFeedbackEnabledNotifier.value,
      );
      mmkv.encodeString(
        'likedSongs',
        json.encode(likedSongsNotifier.value.toList()),
      );
      mmkv.encodeString(
        'customPlaylists',
        json.encode(customPlaylistsNotifier.value),
      );
      mmkv.encodeString(
        'searchHistory',
        json.encode(searchHistoryNotifier.value),
      );
      mmkv.encodeString(
        'artistScores',
        json.encode(artistScoresNotifier.value),
      );
      mmkv.encodeString(
        'artistTimes',
        json.encode(artistListeningTimeNotifier.value),
      );
      mmkv.encodeString(
        'songPlayCounts',
        json.encode(songPlayCountNotifier.value),
      );

      debugPrint("☁️ Restauration auto réussie au démarrage");
    }
  } catch (e) {
    debugPrint("❌ Erreur de restauration auto : $e");
  }
}

void initAutoSyncListeners() {
  // Dès qu'une de ces valeurs change dans l'application, ça déclenche 'triggerAutoSync'
  likedSongsNotifier.addListener(triggerAutoSync);
  customPlaylistsNotifier.addListener(triggerAutoSync);
  playlistContentsNotifier.addListener(triggerAutoSync);
  playlistImagesNotifier.addListener(triggerAutoSync);
  searchHistoryNotifier.addListener(triggerAutoSync);
  artistScoresNotifier.addListener(triggerAutoSync);
  artistListeningTimeNotifier.addListener(triggerAutoSync);
  songPlayCountNotifier.addListener(triggerAutoSync);
  isLosslessNotifier.addListener(triggerAutoSync);
  isHiResNotifier.addListener(triggerAutoSync);
  isDownloadLosslessNotifier.addListener(triggerAutoSync);
  isDownloadHiResNotifier.addListener(triggerAutoSync);
  isCacheEnabledNotifier.addListener(triggerAutoSync);
  cacheLimitNotifier.addListener(triggerAutoSync);
  isCrossfadeEnabledNotifier.addListener(triggerAutoSync);
  crossfadeDurationNotifier.addListener(triggerAutoSync);
  isHapticFeedbackEnabledNotifier.addListener(triggerAutoSync);
}
