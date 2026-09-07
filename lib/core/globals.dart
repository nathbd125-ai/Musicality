
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:audio_service/audio_service.dart';
import 'package:musicality/core/my_audio_handler.dart';
import 'package:mmkv/mmkv.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:musicality/core/api_config.dart';
import 'package:musicality/core/objectbox_service.dart';
import 'package:musicality/core/models/objectbox_entities.dart';
import 'package:musicality/objectbox.g.dart';

late AudioHandler globalAudioHandler;
late String globalDocumentPath;

// --- CONFIGURATION VPS ---

// GESTIONNAIRES GLOBAUX
final ValueNotifier<Set<String>> likedSongsNotifier =
    ValueNotifier<Set<String>>({});
final ValueNotifier<List<String>> customPlaylistsNotifier =
    ValueNotifier<List<String>>([]);
final ValueNotifier<Map<String, Set<String>>> playlistContentsNotifier =
    ValueNotifier<Map<String, Set<String>>>({});
final ValueNotifier<Map<String, String>> playlistImagesNotifier =
    ValueNotifier<Map<String, String>>({});
final ValueNotifier<List<String>> searchHistoryNotifier =
    ValueNotifier<List<String>>([]);
final ValueNotifier<Map<String, int>> songPlayCountNotifier =
    ValueNotifier<Map<String, int>>({});

// GESTION COMPTE & PARAMÈTRES
final ValueNotifier<String?> userProfileImageNotifier = ValueNotifier<String?>(
  null,
);
final ValueNotifier<bool> isLosslessNotifier = ValueNotifier<bool>(false);
final ValueNotifier<bool> isHiResNotifier = ValueNotifier<bool>(false);
final ValueNotifier<bool> isDownloadLosslessNotifier = ValueNotifier<bool>(
  true,
);
final ValueNotifier<bool> isDownloadHiResNotifier = ValueNotifier<bool>(false);
final ValueNotifier<bool> isCacheEnabledNotifier = ValueNotifier<bool>(false);
final ValueNotifier<bool> isLiquidGlassEnabledNotifier = ValueNotifier<bool>(
  true,
);
final ValueNotifier<bool> isBatterySaverEnabledNotifier = ValueNotifier<bool>(
  false,
);
final ValueNotifier<int> cacheLimitNotifier = ValueNotifier<int>(100);
final ValueNotifier<bool> isCrossfadeEnabledNotifier = ValueNotifier<bool>(false);
final ValueNotifier<int> crossfadeDurationNotifier = ValueNotifier<int>(5);

// ALGORITHME
final ValueNotifier<Map<String, int>> artistScoresNotifier =
    ValueNotifier<Map<String, int>>({});
final ValueNotifier<Map<String, int>> artistListeningTimeNotifier =
    ValueNotifier<Map<String, int>>({});

// FONCTION DE MISE À JOUR DES SCORES
void updateArtistScore(String artist, int points) {
  if (artist.isEmpty) return;
  final current = Map<String, int>.from(artistScoresNotifier.value);
  for (var a in extractArtists(artist)) {
    current[a] = (current[a] ?? 0) + points;
    if (current[a]! < 0) current[a] = 0;
  }
  artistScoresNotifier.value = current;
}

// FORMATAGE DU TEMPS D'ÉCOUTE
String formatArtistTime(int totalSeconds) {
  if (totalSeconds < 60) return "< 1 min";
  int m = totalSeconds ~/ 60;
  int h = m ~/ 60;
  m = m % 60;
  if (h >= 10) return "$h h";
  if (h > 0) return "$h h ${m.toString().padLeft(2, '0')} min";
  return "$m min";
}

// APPEL API INTELLIGENT
Future<List<Map<String, dynamic>>> fetchArtistRecommendations(
  String artist, {
  bool isDiscover = false,
}) async {
  if (artist.isEmpty) artist = "Damso";

  String targetSearch = artist;

  if (isDiscover) {
    final diverseArtists = [
      "Ninho",
      "Orelsan",
      "Stromae",
      "PNL",
      "Gazo",
      "Angèle",
      "Tiakola",
      "The Weeknd",
      "Djadja & Dinaz",
      "Josman",
      "Booba",
      "Dua Lipa",
    ];
    diverseArtists.removeWhere((a) => a.toLowerCase() == artist.toLowerCase());
    diverseArtists.shuffle();
    targetSearch = diverseArtists.first;
  }

  try {
    final url = Uri.parse(
      'https://itunes.apple.com/search?term=${Uri.encodeComponent(targetSearch)}&entity=song&limit=15',
    );
    final response = await http.get(url).timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final results = data['results'] as List;
      List<Map<String, dynamic>> recs = [];

      for (var track in results) {
        final title = track['trackName'].toString();
        final trackArtist = track['artistName'].toString();

        int localIndex = globalPlaylist.indexWhere(
          (item) =>
              normalizeString(item.title) == normalizeString(title) ||
              normalizeString(title).contains(normalizeString(item.title)),
        );

        if (localIndex != -1) {
          final localItem = globalPlaylist[localIndex];
          if (!recs.any((r) => r['localId'] == localItem.id)) {
            recs.add({
              'title': localItem.title,
              'artist': localItem.artist,
              'artUri': localItem.artUri.toString(),
              'isLocal': true,
              'localId': localItem.id,
              'localIndex': localIndex,
            });
          }
        } else {
          if (!recs.any(
            (r) => r['title'].toString().toLowerCase() == title.toLowerCase(),
          )) {
            recs.add({
              'title': title,
              'artist': trackArtist,
              'artUri': track['artworkUrl100'].toString().replaceAll(
                '100x100',
                '300x300',
              ),
              'isLocal': false,
            });
          }
        }
        if (recs.length >= 10) break;
      }
      return recs;
    }
  } catch (e) {
    debugPrint("Erreur API de recommandation : $e");
  }
  return [];
}

Future<void> initPersistence() async {
  final mmkv = MMKV.defaultMMKV();
  globalDocumentPath = (await getApplicationDocumentsDirectory()).path;

  // Création du dossier cache s'il n'existe pas
  final cacheDir = Directory('$globalDocumentPath/cache');
  if (!cacheDir.existsSync()) {
    cacheDir.createSync();
  }

  // Chargement paramètres Compte
  final savedProfile = mmkv.decodeString('userProfileImage');
  if (savedProfile != null && savedProfile.isNotEmpty) {
    userProfileImageNotifier.value = savedProfile;
  }

  isLosslessNotifier.value = mmkv.decodeBool('isLossless');
  isHiResNotifier.value = mmkv.decodeBool('isHiRes');
  isDownloadLosslessNotifier.value = mmkv.decodeBool(
    'isDownloadLossless',
    defaultValue: true,
  );
  isDownloadHiResNotifier.value = mmkv.decodeBool('isDownloadHiRes');
  isCacheEnabledNotifier.value = mmkv.decodeBool('isCacheEnabled');
  isLiquidGlassEnabledNotifier.value = false; // mmkv.decodeBool('isLiquidGlassEnabled', defaultValue: true);
  isBatterySaverEnabledNotifier.value = mmkv.decodeBool('isBatterySaverEnabled', defaultValue: false);
  final loadedLimit = mmkv.decodeInt('cacheLimit', defaultValue: 100);
  cacheLimitNotifier.value = (loadedLimit == 50 || ![100, 500, 1024, 5120].contains(loadedLimit)) ? 100 : loadedLimit;

  isLosslessNotifier.addListener(() {
    mmkv.encodeBool('isLossless', isLosslessNotifier.value);
    if (globalAudioHandler is MyAudioHandler) {
      (globalAudioHandler as MyAudioHandler).reloadAudioSourcesForQuality();
    }
  });

  isHiResNotifier.addListener(() {
    mmkv.encodeBool('isHiRes', isHiResNotifier.value);
    if (globalAudioHandler is MyAudioHandler) {
      (globalAudioHandler as MyAudioHandler).reloadAudioSourcesForQuality();
    }
  });

  isDownloadLosslessNotifier.addListener(() {
    mmkv.encodeBool('isDownloadLossless', isDownloadLosslessNotifier.value);
  });

  isDownloadHiResNotifier.addListener(() {
    mmkv.encodeBool('isDownloadHiRes', isDownloadHiResNotifier.value);
  });

  isLiquidGlassEnabledNotifier.addListener(() {
    mmkv.encodeBool('isLiquidGlassEnabled', isLiquidGlassEnabledNotifier.value);
  });

  isBatterySaverEnabledNotifier.addListener(() {
    mmkv.encodeBool('isBatterySaverEnabled', isBatterySaverEnabledNotifier.value);
  });

  isCacheEnabledNotifier.addListener(() {
    mmkv.encodeBool('isCacheEnabled', isCacheEnabledNotifier.value);
    if (globalAudioHandler is MyAudioHandler) {
      (globalAudioHandler as MyAudioHandler).reloadAudioSourcesForQuality();
    }
  });

  cacheLimitNotifier.addListener(() {
    mmkv.encodeInt('cacheLimit', cacheLimitNotifier.value);
    if (globalAudioHandler is MyAudioHandler) {
      (globalAudioHandler as MyAudioHandler).manageCacheSize();
    }
  });

  isCrossfadeEnabledNotifier.value = mmkv.decodeBool('isCrossfadeEnabled', defaultValue: false);
  final loadedCrossfade = mmkv.decodeInt('crossfadeDuration', defaultValue: 5);
  crossfadeDurationNotifier.value = (loadedCrossfade < 1 || loadedCrossfade > 12) ? 5 : loadedCrossfade;

  isCrossfadeEnabledNotifier.addListener(() {
    mmkv.encodeBool('isCrossfadeEnabled', isCrossfadeEnabledNotifier.value);
  });

  crossfadeDurationNotifier.addListener(() {
    mmkv.encodeInt('crossfadeDuration', crossfadeDurationNotifier.value);
  });

  userProfileImageNotifier.addListener(() {
    if (userProfileImageNotifier.value != null) {
      mmkv.encodeString('userProfileImage', userProfileImageNotifier.value!);
    }
  });

  for (var item in globalPlaylist) {
    final String fileName = item.artUri?.pathSegments.last ?? '${getSafeFileName(getBaseId(item.id))}.jpg';
    final coverFile = File('$globalDocumentPath/$fileName');
    if (!coverFile.existsSync() && item.artUri != null) {
      http
          .get(item.artUri!)
          .then((response) {
            if (response.statusCode == 200) {
              coverFile.writeAsBytesSync(response.bodyBytes);
            }
          })
          .catchError((e) {
            debugPrint("Erreur téléchargement cover : $e");
          });
    }
  }

  obx.migrateFromMMKV(mmkv);


  // SANITIZATION LOGIC
  final allEntities = obx.artistScoreBox.getAll();
  bool changed = false;
  for (var entity in allEntities) {
    String oldKey = entity.artist;
    if (oldKey.toLowerCase() == 'the creator') {
      obx.artistScoreBox.remove(entity.id); // Drop the duplicate immediately
      changed = true;
      continue;
    }
    String originalKey = oldKey;
    if (oldKey == 'Tyler') {
      oldKey = 'Tyler The Creator';
    }
    final correctArtists = extractArtists(oldKey);
    if (correctArtists.length != 1 || correctArtists.first != originalKey) {
      changed = true;
      obx.artistScoreBox.remove(entity.id);
      for (var a in correctArtists) {
        if (a == 'Inconnu') continue;
        var newEntity = obx.artistScoreBox.query(ArtistScoreEntity_.artist.equals(a)).build().findFirst();
        if (newEntity != null) {
          newEntity.listeningTimeSeconds += entity.listeningTimeSeconds;
          newEntity.score += entity.score;
          obx.artistScoreBox.put(newEntity);
        } else {
          obx.artistScoreBox.put(ArtistScoreEntity(artist: a, score: entity.score, listeningTimeSeconds: entity.listeningTimeSeconds));
        }
      }
    }
  }
  if (changed) {
    triggerAutoSync(); // To push clean data to Firebase if connected
  }

  final dbScores = obx.artistScoreBox.getAll();
  Map<String, int> loadedScores = { for (var e in dbScores) e.artist : e.score };

  final dbTimes = obx.artistScoreBox.getAll();
  artistListeningTimeNotifier.value = { for (var e in dbTimes) e.artist : e.listeningTimeSeconds };

  artistListeningTimeNotifier.addListener(() {
    for (var entry in artistListeningTimeNotifier.value.entries) {
      var entity = obx.artistScoreBox.query(ArtistScoreEntity_.artist.equals(entry.key)).build().findFirst();
      if (entity != null) {
        entity.listeningTimeSeconds = entry.value;
        obx.artistScoreBox.put(entity);
      } else {
        obx.artistScoreBox.put(ArtistScoreEntity(artist: entry.key, score: 0, listeningTimeSeconds: entry.value));
      }
    }
  });

  final dbCounts = obx.playCountBox.getAll();
  final Map<String, int> migratedCounts = {};
  bool countsChanged = false;
  for (var e in dbCounts) {
    final normId = normalizeSongId(e.songId);
    migratedCounts[normId] = (migratedCounts[normId] ?? 0) + e.count;
    if (e.songId != normId) countsChanged = true;
  }
  songPlayCountNotifier.value = migratedCounts;
  if (countsChanged) {
    obx.playCountBox.removeAll();
    obx.playCountBox.putMany(migratedCounts.entries.map((e) => PlayCountEntity(songId: e.key, count: e.value)).toList());
  }

  songPlayCountNotifier.addListener(() {
    obx.playCountBox.removeAll();
    obx.playCountBox.putMany(songPlayCountNotifier.value.entries.map((e) => PlayCountEntity(songId: normalizeSongId(e.key), count: e.value)).toList());
  });

  final savedLikes = obx.likedSongBox.getAll().map((e) => e.songId).toSet();
  final migratedLikes = <String>{};
  bool likesChanged = false;
  for (var id in savedLikes) {
    final normId = normalizeSongId(id);
    migratedLikes.add(normId);
    if (id != normId) likesChanged = true;
  }

  bool hasMigrated = mmkv.decodeBool('hasMigratedOldLikes');
  if (!hasMigrated && migratedLikes.isNotEmpty) {
    for (String songId in migratedLikes) {
      try {
        final item = globalPlaylist.firstWhere((e) => getBaseId(e.id) == getBaseId(songId));
        if (item.artist != null) {
          loadedScores[item.artist!] = (loadedScores[item.artist!] ?? 0) + 10;
        }
      } catch (e) {
        debugPrint("Erreur migration favoris : $e");
      }
    }
    mmkv.encodeBool('hasMigratedOldLikes', true);
  }

  artistScoresNotifier.value = loadedScores;
  artistScoresNotifier.addListener(() {
    for (var entry in artistScoresNotifier.value.entries) {
      var entity = obx.artistScoreBox.query(ArtistScoreEntity_.artist.equals(entry.key)).build().findFirst();
      if (entity != null) {
        entity.score = entry.value;
        obx.artistScoreBox.put(entity);
      } else {
        obx.artistScoreBox.put(ArtistScoreEntity(artist: entry.key, score: entry.value));
      }
    }
  });

  likedSongsNotifier.value = migratedLikes;
  if (likesChanged) {
    obx.likedSongBox.removeAll();
    obx.likedSongBox.putMany(migratedLikes.map((id) => LikedSongEntity(songId: id)).toList());
  }
  likedSongsNotifier.addListener(() {
    obx.likedSongBox.removeAll();
    obx.likedSongBox.putMany(likedSongsNotifier.value.map((id) => LikedSongEntity(songId: normalizeSongId(id))).toList());
  });

  final savedSearchHistory = obx.searchHistoryBox.getAll();
  searchHistoryNotifier.value = savedSearchHistory.map((e) => e.query).toList();
  searchHistoryNotifier.addListener(() {
    obx.searchHistoryBox.removeAll();
    obx.searchHistoryBox.putMany(searchHistoryNotifier.value.map((query) => SearchHistoryEntity(query: query, timestamp: DateTime.now().millisecondsSinceEpoch)).toList());
  });

  Map<String, Set<String>> initialContents = {};
  Map<String, String> initialImages = {};
  List<String> validPlaylists = [];

  // Chargement 100% MMKV (haute performance, mmap sans overhead de base de données)
  final savedPlaylistsStr = mmkv.decodeString('customPlaylists');
  if (savedPlaylistsStr != null) {
    try {
      final List decoded = json.decode(savedPlaylistsStr);
      validPlaylists = decoded.cast<String>();
    } catch (_) {}
  } else {
    // Migration ponctuelle depuis ObjectBox si existant
    final dbPlaylists = obx.playlistBox.getAll();
    if (dbPlaylists.isNotEmpty) {
      for (var playlist in dbPlaylists) {
        if (!validPlaylists.contains(playlist.name)) {
          validPlaylists.add(playlist.name);
          if (playlist.imagePath != null) {
            mmkv.encodeString('playlist_image_${playlist.name}', playlist.imagePath!);
          }
          final songIds = playlist.songs.map((s) => s.songId).toList();
          mmkv.encodeString('playlist_content_${playlist.name}', json.encode(songIds));
        }
      }
      mmkv.encodeString('customPlaylists', json.encode(validPlaylists));
    }
  }

  // Chargement ultra-rapide des morceaux et images depuis MMKV (avec normalisation HTTPS)
  for (var pName in validPlaylists) {
    final contentStr = mmkv.decodeString('playlist_content_$pName');
    if (contentStr != null) {
      try {
        final List decoded = json.decode(contentStr);
        final normalizedSet = decoded.cast<String>().map(normalizeSongId).toSet();
        initialContents[pName] = normalizedSet;
        mmkv.encodeString('playlist_content_$pName', json.encode(normalizedSet.toList()));
      } catch (_) {}
    }

    final imgStr = mmkv.decodeString('playlist_image_$pName');
    if (imgStr != null && imgStr.isNotEmpty) {
      initialImages[pName] = imgStr;
    }
  }

  customPlaylistsNotifier.value = validPlaylists;
  customPlaylistsNotifier.addListener(() {
    mmkv.encodeString('customPlaylists', json.encode(customPlaylistsNotifier.value));

    // Nettoyage des playlists supprimées dans MMKV
    final currentNames = customPlaylistsNotifier.value.toSet();
    final savedStr = mmkv.decodeString('customPlaylists_all_known');
    final Set<String> allKnown = savedStr != null
        ? (json.decode(savedStr) as List).cast<String>().toSet()
        : <String>{};
    for (var oldP in allKnown) {
      if (!currentNames.contains(oldP)) {
        mmkv.removeValue('playlist_content_$oldP');
        mmkv.removeValue('playlist_image_$oldP');
      }
    }
    mmkv.encodeString('customPlaylists_all_known', json.encode(currentNames.toList()));
  });

  playlistContentsNotifier.value = initialContents;
  playlistContentsNotifier.addListener(() {
    final contents = playlistContentsNotifier.value;
    for (var entry in contents.entries) {
      final normalized = entry.value.map(normalizeSongId).toList();
      mmkv.encodeString('playlist_content_${entry.key}', json.encode(normalized));
    }
  });

  playlistImagesNotifier.value = initialImages;
  playlistImagesNotifier.addListener(() {
    final images = playlistImagesNotifier.value;
    for (var entry in images.entries) {
      mmkv.encodeString('playlist_image_${entry.key}', entry.value);
    }
  });
}

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

List<MediaItem> globalPlaylist = [];

String _extractEnrichedArtist(String rawTitle, String rawArtist) {
  final match = RegExp(r'\s*[(\[]\s*f(?:ea)?t\.?\s+([^()\]]+)[)\]]', caseSensitive: false).firstMatch(rawTitle)
      ?? RegExp(r'\s+f(?:ea)?t\.?\s+(.*)', caseSensitive: false).firstMatch(rawTitle);
  if (match != null) {
    final featArtist = match.group(1)?.trim();
    if (featArtist != null && featArtist.isNotEmpty && !rawArtist.toLowerCase().contains(featArtist.toLowerCase())) {
      return '$rawArtist & $featArtist';
    }
  }
  return rawArtist;
}

void _parseMusiquesFromJson(List<dynamic> data) {
  globalPlaylist.clear();
  for (var jsonItem in data) {
    final id = jsonItem['id'] as String;
    var albumName = jsonItem['album'] ?? 'Inconnu';
    var rawTitle = jsonItem['title'] ?? id;
    if (id.toLowerCase() == 'afro_trap,_part.7_(la_puissance)') {
      rawTitle = "Afro Trap Part. 7 (La Puissance)";
    }
    var rawArtist = jsonItem['artist'] ?? 'Inconnu';
    if (id.toLowerCase().contains('my_salsa')) {
      rawArtist = 'Franglish & Tory Lanez';
    } else if (id.toLowerCase().contains('look_don') && id.toLowerCase().contains('touch')) {
      rawArtist = 'Odetari & Cade Clair';
    }

    if (id.toLowerCase().contains("can't_feel_my_face") || id.toLowerCase().contains('cant_feel_my_face')) {
      if (albumName.toString().toLowerCase().contains('now that')) {
        albumName = 'Beauty Behind the Madness';
      }
    } else if (id.toLowerCase().contains('despacito')) {
      if (albumName.toString().toLowerCase().contains('summer')) {
        albumName = 'VIDA';
      }
    } else if (id.toLowerCase().contains('shy')) {
      if (albumName.toString().toLowerCase().contains('rmf')) {
        albumName = 'The Wrong Kind of War';
      }
    } else if (id.toLowerCase().contains('friday')) {
      if (albumName.toString().toLowerCase().contains('now that')) {
        albumName = 'Friday (Dopamine re-edit)';
      }
    } else if (id.toLowerCase().contains('gypsy_woman')) {
      if (albumName.toString().toLowerCase().contains('firstclass')) {
        albumName = 'Surprise';
      }
    } else if (id.toLowerCase().contains('my_salsa')) {
      if (albumName.toString().toLowerCase().contains('nrj')) {
        albumName = 'Monsieur (Mood Edition)';
      }
    } else if (id.toLowerCase().contains('mi_gente')) {
      if (albumName.toString().toLowerCase().contains('now that')) {
        albumName = 'Vibras';
      }
    } else if (id.toLowerCase().contains('no_lie')) {
      if (albumName.toString().toLowerCase().contains('now that')) {
        albumName = 'Mad Love The Prequel';
      }
    } else if (id.toLowerCase().contains('lucie_from_paris')) {
      if (albumName.toString().toLowerCase().contains('inconnu')) {
        albumName = 'Lucie from Paris';
      }
    } else if (id.toLowerCase().contains('lean_on')) {
      if (albumName.toString().toLowerCase().contains('now that')) {
        albumName = 'Peace Is the Mission';
      }
    } else if (id.toLowerCase() == 'solo' || id.toLowerCase() == 'rockabye') {
      if (albumName.toString().toLowerCase().contains('now that') ||
          albumName.toString().toLowerCase().contains('summer party')) {
        albumName = 'What Is Love?';
      }
    } else if (id.toLowerCase() == 'tuesday') {
      if (albumName.toString().toLowerCase().contains('bravo')) {
        albumName = 'Tuesday';
      }
    }

    String safeImageName = jsonItem['coverName'] != null
        ? jsonItem['coverName'] as String
        : getSafeFileName(albumName);

    if (id.toLowerCase() == 'zoo' || id.toLowerCase() == 'charge') {
      safeImageName = 'or_noir';
    } else if (id.toLowerCase() == 'pa_pa_paw') {
      safeImageName = 'beyah';
    } else if (id.toLowerCase() == 'nouvelles' || safeImageName == '2069') {
      safeImageName = "2069'";
    } else if (id.toLowerCase().contains("can't_feel_my_face") || id.toLowerCase().contains('cant_feel_my_face')) {
      safeImageName = 'beauty_behind_the_madness';
    } else if (id.toLowerCase() == 'charger' || safeImageName.contains('franchement')) {
      safeImageName = 'franchement';
    } else if (id.toLowerCase() == 'rockabye') {
      safeImageName = 'what_is_love';
    } else if (id.toLowerCase().contains('despacito') || safeImageName.contains('we_love_summer')) {
      safeImageName = 'vida';
    } else if (id.toLowerCase().contains('shy') || safeImageName.contains('rmf')) {
      safeImageName = 'the_wrong_kind_of_war';
    } else if (id.toLowerCase().contains('drop_it_like') || id.toLowerCase().contains('masterpiece') || safeImageName.contains('masterpiece')) {
      safeImageName = 'rg_the_masterpiece';
    } else if (id.toLowerCase().contains('falling_down') || safeImageName.contains('sober')) {
      safeImageName = 'come_over_when_youre_sober_pt_2';
    } else if (id.toLowerCase().contains('friday') || safeImageName.contains('friday')) {
      safeImageName = 'friday';
    } else if (id.toLowerCase().contains('gypsy_woman') || safeImageName.contains('firstclass')) {
      safeImageName = 'surprise';
    } else if (id.toLowerCase().contains('my_salsa') || safeImageName.contains('nrj')) {
      safeImageName = 'my_salsa';
    } else if (id.toLowerCase().contains('mi_gente')) {
      safeImageName = 'vibras';
    } else if (id.toLowerCase().contains('no_lie')) {
      safeImageName = 'mad_love_the_prequel';
    } else if (id.toLowerCase().contains('lucie_from_paris')) {
      safeImageName = 'lucie_from_paris';
    } else if (id.toLowerCase().contains('lean_on')) {
      safeImageName = 'peace_is_the_mission';
    } else if (id.toLowerCase().contains('pour_deux_ames_solitaires') && id.contains('1')) {
      safeImageName = 'pour_deux_ames_solitaires_part_1';
    } else if (id.toLowerCase().contains('pour_deux_ames_solitaires') && id.contains('2')) {
      safeImageName = 'pour_deux_ames_solitaires_part_2';
    } else if (id.toLowerCase() == 'solo') {
      safeImageName = 'what_is_love';
    } else if (id.toLowerCase() == 'tuesday') {
      safeImageName = 'tuesday';
    } else if (id.toLowerCase().contains('swimming_pools') || safeImageName.contains('maad')) {
      safeImageName = 'good_kid_maad_city';
    }

    final mediaItem = MediaItem(
      id: '${ApiConfig.baseUrl}/$id.flac',
      album: albumName,
      title: _cleanTitle(rawTitle),
      artist: _extractEnrichedArtist(rawTitle, rawArtist),
      artUri: Uri.parse('${ApiConfig.baseUrl}/$safeImageName.jpg'),
      duration: Duration(seconds: jsonItem['durationSeconds'] ?? 0),
      extras: {
        'hasFlac': jsonItem['hasFlac'] ?? true,
        'hasHiRes': jsonItem['hasHiRes'] ?? false,
      },
    );
    
    globalPlaylist.add(mediaItem);
  }
}

Future<void> fetchMusiques() async {
  try {
    final response = await http
        .get(Uri.parse('${ApiConfig.baseUrl}/musiques.json'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      final List<dynamic> data = jsonDecode(responseBody);
      
      // Mettre en cache dans ObjectBox
      final List<SongEntity> entities = [];
      for (var jsonItem in data) {
        final id = jsonItem['id'] as String;
        var albumName = jsonItem['album'] ?? 'Inconnu';
        var rawTitle = jsonItem['title'] ?? id;
    if (id.toLowerCase() == 'afro_trap,_part.7_(la_puissance)') {
      rawTitle = "Afro Trap Part. 7 (La Puissance)";
    }
        var rawArtist = jsonItem['artist'] ?? 'Inconnu';
        if (id.toLowerCase().contains('my_salsa')) {
          rawArtist = 'Franglish & Tory Lanez';
        } else if (id.toLowerCase().contains('look_don') && id.toLowerCase().contains('touch')) {
          rawArtist = 'Odetari & Cade Clair';
        }

        if (id.toLowerCase().contains("can't_feel_my_face") || id.toLowerCase().contains('cant_feel_my_face')) {
          if (albumName.toString().toLowerCase().contains('now that')) {
            albumName = 'Beauty Behind the Madness';
          }
        } else if (id.toLowerCase().contains('despacito')) {
          if (albumName.toString().toLowerCase().contains('summer')) {
            albumName = 'VIDA';
          }
        } else if (id.toLowerCase().contains('shy')) {
          if (albumName.toString().toLowerCase().contains('rmf')) {
            albumName = 'The Wrong Kind of War';
          }
        } else if (id.toLowerCase().contains('friday')) {
          if (albumName.toString().toLowerCase().contains('now that')) {
            albumName = 'Friday (Dopamine re-edit)';
          }
        } else if (id.toLowerCase().contains('gypsy_woman')) {
          if (albumName.toString().toLowerCase().contains('firstclass')) {
            albumName = 'Surprise';
          }
        } else if (id.toLowerCase().contains('my_salsa')) {
          if (albumName.toString().toLowerCase().contains('nrj')) {
            albumName = 'Monsieur (Mood Edition)';
          }
        } else if (id.toLowerCase().contains('mi_gente')) {
          if (albumName.toString().toLowerCase().contains('now that')) {
            albumName = 'Vibras';
          }
        } else if (id.toLowerCase().contains('no_lie')) {
          if (albumName.toString().toLowerCase().contains('now that')) {
            albumName = 'Mad Love The Prequel';
          }
        } else if (id.toLowerCase().contains('lucie_from_paris')) {
          if (albumName.toString().toLowerCase().contains('inconnu')) {
            albumName = 'Lucie from Paris';
          }
        } else if (id.toLowerCase().contains('lean_on')) {
          if (albumName.toString().toLowerCase().contains('now that')) {
            albumName = 'Peace Is the Mission';
          }
        } else if (id.toLowerCase() == 'solo' || id.toLowerCase() == 'rockabye') {
          if (albumName.toString().toLowerCase().contains('now that') ||
              albumName.toString().toLowerCase().contains('summer party')) {
            albumName = 'What Is Love?';
          }
        } else if (id.toLowerCase() == 'tuesday') {
          if (albumName.toString().toLowerCase().contains('bravo')) {
            albumName = 'Tuesday';
          }
        }

        String safeImageName = jsonItem['coverName'] != null
            ? jsonItem['coverName'] as String
            : getSafeFileName(albumName);

        if (id.toLowerCase() == 'zoo' || id.toLowerCase() == 'charge') {
          safeImageName = 'or_noir';
        } else if (id.toLowerCase() == 'pa_pa_paw') {
          safeImageName = 'beyah';
        } else if (id.toLowerCase() == 'nouvelles' || safeImageName == '2069') {
          safeImageName = "2069'";
        } else if (id.toLowerCase().contains("can't_feel_my_face") || id.toLowerCase().contains('cant_feel_my_face')) {
          safeImageName = 'beauty_behind_the_madness';
        } else if (id.toLowerCase() == 'charger' || safeImageName.contains('franchement')) {
          safeImageName = 'franchement';
        } else if (id.toLowerCase() == 'rockabye') {
          safeImageName = 'what_is_love';
        } else if (id.toLowerCase().contains('despacito') || safeImageName.contains('we_love_summer')) {
          safeImageName = 'vida';
        } else if (id.toLowerCase().contains('shy') || safeImageName.contains('rmf')) {
          safeImageName = 'the_wrong_kind_of_war';
        } else if (id.toLowerCase().contains('drop_it_like') || id.toLowerCase().contains('masterpiece') || safeImageName.contains('masterpiece')) {
          safeImageName = 'rg_the_masterpiece';
        } else if (id.toLowerCase().contains('falling_down') || safeImageName.contains('sober')) {
          safeImageName = 'come_over_when_youre_sober_pt_2';
        } else if (id.toLowerCase().contains('friday') || safeImageName.contains('friday')) {
          safeImageName = 'friday';
        } else if (id.toLowerCase().contains('gypsy_woman') || safeImageName.contains('firstclass')) {
          safeImageName = 'surprise';
        } else if (id.toLowerCase().contains('my_salsa') || safeImageName.contains('nrj')) {
          safeImageName = 'my_salsa';
        } else if (id.toLowerCase().contains('mi_gente')) {
          safeImageName = 'vibras';
        } else if (id.toLowerCase().contains('no_lie')) {
          safeImageName = 'mad_love_the_prequel';
        } else if (id.toLowerCase().contains('lucie_from_paris')) {
          safeImageName = 'lucie_from_paris';
        } else if (id.toLowerCase().contains('lean_on')) {
          safeImageName = 'peace_is_the_mission';
        } else if (id.toLowerCase().contains('pour_deux_ames_solitaires') && id.contains('1')) {
          safeImageName = 'pour_deux_ames_solitaires_part_1';
        } else if (id.toLowerCase().contains('pour_deux_ames_solitaires') && id.contains('2')) {
          safeImageName = 'pour_deux_ames_solitaires_part_2';
        } else if (id.toLowerCase() == 'solo') {
          safeImageName = 'what_is_love';
        } else if (id.toLowerCase() == 'tuesday') {
          safeImageName = 'tuesday';
        } else if (id.toLowerCase().contains('swimming_pools') || safeImageName.contains('maad')) {
          safeImageName = 'good_kid_maad_city';
        }
        
        entities.add(SongEntity(
          songId: id,
          title: rawTitle,
          artist: _extractEnrichedArtist(rawTitle, rawArtist),
          album: albumName,
          artUri: '${ApiConfig.baseUrl}/$safeImageName.jpg',
          durationSeconds: jsonItem['durationSeconds'] ?? 0,
          hasFlac: jsonItem['hasFlac'] ?? true,
          hasHiRes: jsonItem['hasHiRes'] ?? false,
        ));
      }
      
      // On vide l'ancienne boîte et on insère les nouvelles données
      obx.songBox.removeAll();
      obx.songBox.putMany(entities);

      _parseMusiquesFromJson(data);
      debugPrint('Musiques chargées avec succès : ${globalPlaylist.length}');
    } else {
      throw Exception(
        'Erreur réseau lors du chargement des musiques : ${response.statusCode}',
      );
    }
  } catch (e) {
    debugPrint('Erreur HTTP, tentative de lecture depuis le cache ObjectBox : $e');
    
    // Lecture depuis ObjectBox
    final cachedSongs = obx.songBox.getAll();
    if (cachedSongs.isNotEmpty) {
      globalPlaylist.clear();
      for (var entity in cachedSongs) {
        var album = entity.album;
        if (entity.songId.toLowerCase().contains("can't_feel_my_face") ||
            entity.songId.toLowerCase().contains('cant_feel_my_face')) {
          if (album.toLowerCase().contains('now that')) {
            album = 'Beauty Behind the Madness';
          }
        }
        final mediaItem = MediaItem(
          id: '${ApiConfig.baseUrl}/${entity.songId}.flac',
          album: album,
          title: _cleanTitle(entity.title),
          artist: _extractEnrichedArtist(entity.title, entity.artist),
          artUri: entity.artUri != null ? Uri.parse(entity.artUri!) : null,
          duration: Duration(seconds: entity.durationSeconds),
          extras: {
            'hasFlac': entity.hasFlac,
            'hasHiRes': entity.hasHiRes,
          },
        );
        
        globalPlaylist.add(mediaItem);
      }
      debugPrint('Musiques chargées depuis le CACHE LOCAL (ObjectBox) : ${globalPlaylist.length}');
    } else {
      debugPrint('Aucun cache local disponible pour les musiques.');
    }
  }
}

List<double>? getGradientStops(int count) {
  if (count <= 1) return null;
  if (count == 2) return const [0.0, 1.0];
  if (count == 3) return const [0.25, 0.5, 0.75];
  if (count == 4) return const [0.15, 0.38, 0.61, 0.85];
  if (count == 5) return const [0.1, 0.3, 0.5, 0.7, 0.9];
  final step = 1.0 / (count - 1);
  return List<double>.generate(count, (i) => (i * step).clamp(0.0, 1.0));
}

List<Color> getAlbumGradientColors(MediaItem item) {
  final artUriStr = item.artUri?.toString().toLowerCase() ?? '';
  final a = getSafeFileName(item.album ?? '');
  final albumNorm = normalizeString(item.album ?? '');
  final idStr = item.id.toLowerCase();
  final titleNorm = normalizeString(item.title);

  // 1. EXCEPTIONS TITRES / SINGLES SPÉCIAUX (qui gardent leur gradient spécifique)
  // Ariana Grande - 7 Rings (Rose fin pastel/néon sans violet)
  if (titleNorm.contains('7 rings') || idStr.contains('7_rings') || idStr.contains('7 rings')) {
    return const [
      Color(0xFFFFB6C1), // Rose poudré clair
      Color(0xFFFF7DA7), // Rose fin
      Color(0xFFFF4D88), // Rose pochette
    ];
  }

  // Frou Frou - A New Kind of Love (demo) (Violet à rosé)
  if (titleNorm.contains('new kind of love') || idStr.contains('new_kind_of_love') || idStr.contains('kind_of_love')) {
    return const [
      Color(0xFF7B1FA2), // Violet profond
      Color(0xFFAB47BC), // Violet intermédiaire
      Color(0xFFEC407A), // Rosé
    ];
  }

  // MHD - Afro Trap Part. 11 (King Kong) (Noir à blanc)
  if (titleNorm.contains('king kong') || idStr.contains('king_kong') || (titleNorm.contains('afro trap') && titleNorm.contains('11'))) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFF555555), // Gris anthracite
      Color(0xFFCCCCCC), // Gris clair
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // MHD - Afro Trap Part. 7 (La puissance) (Noir à blanc à rouge)
  if (titleNorm.contains('la puissance') || idStr.contains('la_puissance') || (titleNorm.contains('afro trap') && titleNorm.contains('7'))) {
    return const [
      Color(0xFF1A1A1A), // Noir
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFE53935), // Rouge
    ];
  }

  // All I Need (Jaune clair à bleu à orange à vert à jaune foncé à rouge à bleu cyan)
  if (titleNorm.contains('all i need') || idStr.contains('all_i_need')) {
    return const [
      Color(0xFFFFF59D), // Jaune clair
      Color(0xFF1E88E5), // Bleu
      Color(0xFFFF9800), // Orange
      Color(0xFF43A047), // Vert
      Color(0xFFFBC02D), // Jaune foncé
      Color(0xFFE53935), // Rouge
      Color(0xFF00E5FF), // Bleu cyan
    ];
  }

  // Metro Boomin, A$AP Rocky, Roisee - Am I Dreaming (Exception : 10% jaune, 10% vert, 30% rouge, 50% violet)
  if (titleNorm.contains('am i dreaming') || idStr.contains('am_i_dreaming')) {
    return const [
      Color(0xFF00E676), // 10% Vert néon
      Color(0xFFFFEA00), // 10% Jaune
      Color(0xFFE53935), // 30% Rouge (3 paliers)
      Color(0xFFE53935),
      Color(0xFFE53935),
      Color(0xFF7B1FA2), // 50% Violet (5 paliers)
      Color(0xFF7B1FA2),
      Color(0xFF7B1FA2),
      Color(0xFF7B1FA2),
      Color(0xFF7B1FA2),
    ];
  }

  // Heuss L'enfoiré - Bar-Mitzvah (Jaune doré à blanc)
  if (titleNorm.contains('bar-mitzvah') ||
      titleNorm.contains('bar mitzvah') ||
      idStr.contains('bar-mitzvah') ||
      a.contains('bar-mitzvah')) {
    return const [
      Color(0xFFFFD700), // Jaune doré
      Color(0xFFFFE082), // Jaune doré clair
      Color(0xFFFFF9C4), // Blanc cassé doré
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Lacrim - Barbade (Blanc à gris à rouge)
  if (titleNorm.contains('barbade') || idStr.contains('barbade')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF9E9E9E), // Gris
      Color(0xFFE53935), // Rouge
    ];
  }

  // Niska - Bâtiment (Vert gris à blanc à orange)
  if (titleNorm.contains('batiment') || idStr.contains('batiment')) {
    return const [
      Color(0xFF607D8B), // Vert gris
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFFF6D00), // Orange
    ];
  }

  // Michael Jackson - Billie Jean (Blanc à doré à marron)
  if (titleNorm.contains('billie jean') || idStr.contains('billie_jean')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFFFD700), // Doré
      Color(0xFF5D4037), // Marron
    ];
  }

  // Phantogram - Black Out Days (Blanc à doré)
  if (titleNorm.contains('black out days') || idStr.contains('black_out_days')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFFFF8E1), // Blanc doré
      Color(0xFFFFE082), // Doré clair
      Color(0xFFFFD700), // Doré
    ];
  }

  // Jok'Air - Bonbon à la menthe (Bleu à jaune à rouge à rose)
  if (titleNorm.contains('bonbon') || idStr.contains('bonbon_a_la_menthe') || a.contains('jok_travolta') || albumNorm.contains('jok')) {
    return const [
      Color(0xFF1E88E5), // Bleu
      Color(0xFFFFEA00), // Jaune
      Color(0xFFE53935), // Rouge
      Color(0xFFE91E63), // Rose
    ];
  }

  // Daddy Yankee - Con Calma (Rose rouge plus rouge)
  if (titleNorm.contains('con calma') ||
      idStr.contains('con_calma') ||
      a.contains('con_calma') ||
      albumNorm.contains('con calma')) {
    return const [
      Color(0xFFE91E63), // Rose rouge vif
      Color(0xFFD32F2F), // Rouge framboise profond
      Color(0xFFB71C1C), // Rouge carmin intense
    ];
  }

  // Luis Fonsi - Despacito / VIDA (Jaune doré)
  if (titleNorm.contains('despacito') ||
      idStr.contains('despacito') ||
      a.contains('vida')) {
    return const [
      Color(0xFFFFF59D), // Jaune clair doré
      Color(0xFFFFEA00), // Jaune éclatant
      Color(0xFFFFD700), // Doré
      Color(0xFFFFA000), // Doré ambré
    ];
  }

  // do i clench my fists? (Gris noir à marron gris à blanc)
  if (titleNorm.contains('do i clench my fists') ||
      idStr.contains('do_i_clench_my_fists') ||
      a.contains('do_i_clench_my_fists')) {
    return const [
      Color(0xFF1C1C1C), // Gris noir
      Color(0xFF5D534E), // Marron gris
      Color(0xFF9E948F), // Marron gris clair
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Imany - Don't Be So Shy / The Wrong Kind of War (Blanc à rouge à noir)
  if (titleNorm.contains("don't be so shy") ||
      titleNorm.contains("dont be so shy") ||
      idStr.contains('shy') ||
      a.contains('the_wrong_kind_of_war')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFE53935), // Rouge
      Color(0xFFB71C1C), // Rouge foncé
      Color(0xFF111111), // Noir
    ];
  }

  // Jul - Drôle de dame / Album Gratuit Vol.4 (Blanc à doré)
  if (titleNorm.contains('drole de dame') ||
      idStr.contains('drole_de_dame') ||
      a.contains('album_gratuit_vol4') ||
      a.contains('album_gratuit_vol_4')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFFFF8E1), // Blanc doré
      Color(0xFFFFD54F), // Doré clair
      Color(0xFFFFC107), // Doré
    ];
  }

  // Snoop Dogg - Drop It Like It's Hot / R&G: The Masterpiece (Noir clair à marron à gris vert)
  if (titleNorm.contains('drop it like') ||
      idStr.contains('drop_it_like') ||
      a.contains('masterpiece') ||
      a.contains('rg_the_masterpiece')) {
    return const [
      Color(0xFF262626), // Noir clair
      Color(0xFF6D4C41), // Marron
      Color(0xFF8D6E63), // Marron intermédiaire
      Color(0xFF5A6860), // Gris vert
    ];
  }

  // Lil Peep & XXXTENTACION - Falling Down / Come Over When You're Sober Pt. 2 (Rouge à bleu grisâtre à vert clair)
  if (titleNorm.contains('falling down') ||
      idStr.contains('falling_down') ||
      a.contains('sober') ||
      a.contains('come_over_when_youre_sober_pt_2')) {
    return const [
      Color(0xFFE53935), // Rouge
      Color(0xFF607D8B), // Bleu grisâtre
      Color(0xFFA5D6A7), // Vert clair
    ];
  }

  // The Weeknd - Can't Feel My Face (Blanc à gris à noir)
  if (titleNorm.contains("can't feel my face") ||
      titleNorm.contains("cant feel my face") ||
      idStr.contains("can't_feel_my_face") ||
      idStr.contains("cant_feel_my_face")) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFB0BEC5), // Gris clair
      Color(0xFF616161), // Gris
      Color(0xFF111111), // Noir
    ];
  }

  // DJ Kawest & Attachingboy - Chambre 04 (Bleu à marron)
  if (titleNorm.contains('chambre 04') ||
      idStr.contains('chambre_04') ||
      a.contains('chambre_04')) {
    return const [
      Color(0xFF1976D2), // Bleu
      Color(0xFF0D47A1), // Bleu nuit
      Color(0xFF6D4C41), // Marron chaud
      Color(0xFF4E342E), // Marron
    ];
  }

  // Blood Orange - Champagne Coast (Blanc à gris à noir, comme Can't Feel My Face)
  if (titleNorm.contains('champagne coast') ||
      idStr.contains('champagne_coast')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFB0BEC5), // Gris clair
      Color(0xFF616161), // Gris
      Color(0xFF111111), // Noir
    ];
  }

  // TRIANGLE DES BERMUDES - Charger (Noir à rouge)
  if (titleNorm.contains('charger') || idStr.contains('charger')) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFF212121), // Noir anthracite
      Color(0xFFB71C1C), // Rouge foncé
      Color(0xFFE53935), // Rouge
    ];
  }

  // TV Girl - Who Really Cares / Cigarettes Out the Window (Bleu foncé à rose dégradé fluide)
  if (titleNorm.contains('cigarettes out the window') ||
      idStr.contains('cigarettes_out_the_window') ||
      a.contains('who_really_cares') ||
      albumNorm.contains('who really cares') ||
      titleNorm.contains('tv girl') ||
      idStr.contains('tv_girl')) {
    return const [
      Color(0xFF0D47A1), // Bleu foncé
      Color(0xFF1E88E5), // Bleu moyen
      Color(0xFFAB47BC), // Transition violet rosé
      Color(0xFFE91E63), // Rose
    ];
  }

  // Hatik - Angela (Blanc à beige)
  if (titleNorm.contains('angela') || idStr.contains('angela')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFF5EBE1), // Blanc cassé / beige très clair
      Color(0xFFD4B896), // Beige chaleureux
    ];
  }

  // PLK - Attentat (Beige foncé à jaune doré à rouge)
  if (titleNorm.contains('attentat') || idStr.contains('attentat')) {
    return const [
      Color(0xFFBA966C), // Beige foncé
      Color(0xFFFFC107), // Jaune doré
      Color(0xFFD32F2F), // Rouge
    ];
  }

  if (titleNorm.contains('levitating') && (titleNorm.contains('dababy') || idStr.contains('dababy') || artUriStr.contains('levitating_dababy'))) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF2196F3), // Bleu
      Color(0xFFC89B3C), // Jaune/Marron (Chaise)
    ];
  }

  if (titleNorm.contains('fever') || idStr.contains('fever') || artUriStr.contains('fever')) {
    return const [
      Color(0xFFFF9800), // Orange
      Color(0xFFD32F2F), // Rouge
      Color(0xFFB71C1C), // Rouge foncé
      Color(0xFF212121), // Noir
    ];
  }

  // 2. GRADIENTS ASSOCIÉS AUX NOMS DES ALBUMS
  // C418 - Minecraft Volume Beta (Jaune à orange foncé)
  if (a.contains('volume_beta') ||
      albumNorm.contains('volume beta') ||
      titleNorm.contains('biome fest') ||
      idStr.contains('biome_fest') ||
      titleNorm.contains('dreiton') ||
      idStr.contains('dreiton')) {
    return const [
      Color(0xFFFFEA00), // Jaune
      Color(0xFFFF9800), // Orange
      Color(0xFFE65100), // Orange foncé
    ];
  }

  // The Weeknd - After Hours / Blinding Lights (Vert gris à beige marron à rouge)
  if (a.contains('after_hours') ||
      albumNorm.contains('after hours') ||
      titleNorm.contains('blinding lights') ||
      idStr.contains('blinding_lights')) {
    return const [
      Color(0xFF455A64), // Vert gris
      Color(0xFF8D6E63), // Beige marron
      Color(0xFFD32F2F), // Rouge
    ];
  }

  // Kanye West - Graduation / Flashing Lights (Orangé à jaune à violet)
  if (a.contains('graduation') ||
      albumNorm.contains('graduation') ||
      titleNorm.contains('flashing lights') ||
      idStr.contains('flashing_lights')) {
    return const [
      Color(0xFFFF7043), // Orangé
      Color(0xFFFFCA28), // Jaune
      Color(0xFF8E24AA), // Violet
    ];
  }

  // Riton x Nightcrawlers - Friday (Vert à orange profond à jaune clair)
  if (titleNorm.contains('friday') ||
      idStr.contains('friday') ||
      a.contains('friday') ||
      albumNorm.contains('friday')) {
    return const [
      Color(0xFF2E7D32), // Vert
      Color(0xFFE65100), // Orange profond
      Color(0xFFFFF59D), // Jaune clair
    ];
  }

  // Travis Scott - Birds in the Trap Sing McKnight / goosebumps (Noir à bleu foncé à marron rosé)
  if (a.contains('birds_in_the_trap') ||
      albumNorm.contains('birds in the trap') ||
      titleNorm.contains('goosebumps') ||
      idStr.contains('goosebumps')) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFF0D233A), // Bleu foncé
      Color(0xFF9E716B), // Marron rosé
    ];
  }

  // Crystal Waters - Surprise / Gypsy Woman (Violet noir à violet gris à blanc)
  if (a.contains('surprise') ||
      albumNorm.contains('surprise') ||
      titleNorm.contains('gypsy woman') ||
      idStr.contains('gypsy_woman')) {
    return const [
      Color(0xFF1E1035), // Violet noir
      Color(0xFF75658C), // Violet gris
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Camila Cabello - Camila / Havana (Vert à orange à beige foncé à blanc)
  if (a.contains('camila') ||
      albumNorm.contains('camila') ||
      titleNorm.contains('havana') ||
      idStr.contains('havana')) {
    return const [
      Color(0xFF2E5A36), // Vert
      Color(0xFFE65100), // Orange
      Color(0xFF8D6E63), // Beige foncé
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Gambi - LA VIE EST BELLE / HÉ OH (Bleu foncé à violet clair à marron clair à jaune orangé à blanc)
  if (a.contains('la_vie_est_belle') ||
      albumNorm.contains('la vie est belle') ||
      titleNorm.contains('he oh') ||
      idStr.contains('he_oh')) {
    return const [
      Color(0xFF101935), // Bleu foncé
      Color(0xFF9C6B98), // Violet clair
      Color(0xFF8D6E63), // Marron clair
      Color(0xFFFFB74D), // Jaune orangé
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Childish Gambino - Camp / Heartbeat (Blanc à jaune à vert)
  if (a.contains('camp') ||
      albumNorm == 'camp' ||
      titleNorm.contains('heartbeat') ||
      idStr.contains('heartbeat')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFFFEE58), // Jaune
      Color(0xFF43A047), // Vert
    ];
  }

  // Travis Scott - HIGHEST IN THE ROOM (Blanc à bleu clair à marron clair orangé à orange feu)
  if (a.contains('highest_in_the_room') ||
      albumNorm.contains('highest in the room') ||
      titleNorm.contains('highest in the room') ||
      idStr.contains('highest_in_the_room')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF4FC3F7), // Bleu clair
      Color(0xFFA16B47), // Marron clair orangé
      Color(0xFFFF5722), // Orange feu
    ];
  }

  // The Weeknd - House of Balloons (Blanc à gris à noir)
  if (a.contains('house_of_balloons') ||
      albumNorm.contains('house of balloons') ||
      titleNorm.contains('house of balloons') ||
      idStr.contains('house_of_balloons')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF757575), // Gris
      Color(0xFF111111), // Noir
    ];
  }

  // Calvin Harris & Disciples - How Deep Is Your Love (Blanc à rouge)
  if (titleNorm.contains('how deep is your love') ||
      idStr.contains('how_deep_is_your_love') ||
      a.contains('how_deep_is_your_love') ||
      albumNorm.contains('how deep is your love')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFFFEBEE), // Blanc rosé
      Color(0xFFE53935), // Rouge
      Color(0xFFC62828), // Rouge profond
    ];
  }

  // A$AP Rocky - I Smoked Away My Brain (Noir à gris à blanc)
  if (titleNorm.contains('i smoked away my brain') ||
      idStr.contains('i_smoked_away_my_brain') ||
      a.contains('dont_be_dumb') ||
      albumNorm.contains('dont be dumb')) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFF757575), // Gris
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Romeo Santos - Golden / Imitadora (Doré)
  if (a.contains('golden') ||
      albumNorm == 'golden' ||
      titleNorm.contains('imitadora') ||
      idStr.contains('imitadora')) {
    return const [
      Color(0xFFFFF8E1), // Blanc doré
      Color(0xFFFFD54F), // Doré scintillant
      Color(0xFFFFC107), // Doré
      Color(0xFFFFA000), // Or profond
    ];
  }

  // Ice Cube - The Predator / It Was a Good Day (Gris noir à marron blanc à blanc gris à blanc)
  if (a.contains('the_predator') ||
      albumNorm.contains('the predator') ||
      titleNorm.contains('it was a good day') ||
      idStr.contains('it_was_a_good_day')) {
    return const [
      Color(0xFF1C1C1C), // Gris noir
      Color(0xFFA89F91), // Marron blanc (sépia délavé)
      Color(0xFFCFD8DC), // Blanc gris
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Tesher x Jason Derulo - Jalebi Baby (Bleu exubérance à orange)
  if (titleNorm.contains('jalebi baby') ||
      idStr.contains('jalebi_baby') ||
      a.contains('jalebi_baby') ||
      albumNorm.contains('jalebi baby')) {
    return const [
      Color(0xFF00838F), // Bleu exubérance (sarcelle vibrant)
      Color(0xFF00ACC1), // Bleu cyan chaud
      Color(0xFFFF6D00), // Orange
      Color(0xFFFF8F00), // Orange vif
    ];
  }

  // Ninho - Destin / La vie qu'on mène (Blanc à gris à bleu à jaune)
  if (a.contains('destin') ||
      albumNorm == 'destin' ||
      titleNorm.contains('la vie quon mene') ||
      titleNorm.contains("la vie qu'on mene") ||
      idStr.contains('la_vie_qu')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF9E9E9E), // Gris
      Color(0xFF0288D1), // Bleu
      Color(0xFFFFC107), // Jaune
    ];
  }

  // Major Lazer & DJ Snake - Peace Is the Mission / Lean On (Violet foncé à rose)
  if (a.contains('peace_is_the_mission') ||
      albumNorm.contains('peace is the mission') ||
      titleNorm.contains('lean on') ||
      idStr.contains('lean_on')) {
    return const [
      Color(0xFF311B92), // Violet foncé
      Color(0xFF6A1B9A), // Violet moyen
      Color(0xFFD81B60), // Rose framboise
      Color(0xFFE91E63), // Rose
    ];
  }

  // DJ Snake - Encore / Let Me Love You (Vert à jaune sable à bleu clair clair)
  if (a.contains('encore') ||
      albumNorm == 'encore' ||
      titleNorm.contains('let me love you') ||
      idStr.contains('let_me_love_you')) {
    return const [
      Color(0xFF1B5E20), // Vert
      Color(0xFF2E7D32), // Vert moyen
      Color(0xFFD7B168), // Jaune sable
      Color(0xFFE1F5FE), // Bleu clair clair
    ];
  }

  // MGMT - Little Dark Age (Noir clair grisâtre à jaune)
  if (a.contains('little_dark_age') ||
      albumNorm.contains('little dark age') ||
      titleNorm.contains('little dark age') ||
      idStr.contains('little_dark_age')) {
    return const [
      Color(0xFF2B2B2B), // Noir clair grisâtre
      Color(0xFF424242), // Gris anthracite
      Color(0xFFFFD600), // Jaune
      Color(0xFFFFEA00), // Jaune vif
    ];
  }

  // Odetari & Cade Clair - XIII SORROWS / LOOK DON'T TOUCH (Noir à blanc à rose à violet)
  if (a.contains('xiii_sorrows') ||
      albumNorm.contains('xiii sorrows') ||
      titleNorm.contains('look dont touch') ||
      titleNorm.contains("look don't touch") ||
      idStr.contains('look_don')) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFEC407A), // Rose
      Color(0xFF8E24AA), // Violet
    ];
  }

  // Juice WRLD - Goodbye & Good Riddance / Lucid Dreams (Noir à rouge à bleu dominant à jaune)
  if (a.contains('goodbye_and_good_riddance') ||
      a.contains('goodbye') ||
      albumNorm.contains('goodbye') ||
      titleNorm.contains('lucid dreams') ||
      idStr.contains('lucid_dreams')) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFFE53935), // Rouge (prend moins de place)
      Color(0xFF0288D1), // Bleu profond
      Color(0xFF03A9F4), // Bleu vif (prend plus de place)
      Color(0xFF4FC3F7), // Bleu ciel
      Color(0xFFFFEA00), // Jaune
    ];
  }

  // Giga Papaskiri - Lucie from Paris (Noir à gris à blanc)
  if (titleNorm.contains('lucie from paris') ||
      idStr.contains('lucie_from_paris') ||
      a.contains('lucie_from_paris') ||
      albumNorm.contains('lucie from paris')) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFF757575), // Gris
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Moha La Squale - Bendero / Luna (Vert foncé à vert à bleu à jaune sable)
  if (a.contains('bendero') ||
      albumNorm == 'bendero' ||
      titleNorm == 'luna' ||
      idStr.endsWith('/luna.flac') ||
      idStr == 'luna') {
    return const [
      Color(0xFF1B5E20), // Vert foncé
      Color(0xFF388E3C), // Vert
      Color(0xFF0288D1), // Bleu
      Color(0xFFE0BB76), // Jaune sable
    ];
  }

  // Maître Gims - Ma beauté / Mon coeur avait raison (Bleu grisé à jaune très clair)
  if (a.contains('ma_beaute') ||
      albumNorm.contains('ma beaute') ||
      titleNorm.contains('ma beaute') ||
      idStr.contains('ma_beaute')) {
    return const [
      Color(0xFF607D8B), // Bleu grisé
      Color(0xFF90A4AE), // Bleu gris clair
      Color(0xFFFFFDE7), // Jaune très clair
    ];
  }

  // DJ Snake - Carte Blanche / Magenta Riddim (Bleu ciel à gris à blanc)
  if (a.contains('carte_blanche') ||
      albumNorm.contains('carte blanche') ||
      titleNorm.contains('magenta riddim') ||
      idStr.contains('magenta_riddim')) {
    return const [
      Color(0xFF03A9F4), // Bleu ciel
      Color(0xFFB0BEC5), // Gris
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // 6ix9ine - DUMMY BOY / MALA (Noir à blanc à rouge à rose à violet à bleu à jaune à vert - 8 couleurs)
  if (a.contains('dummy_boy') ||
      albumNorm.contains('dummy boy') ||
      titleNorm.contains('mala') ||
      idStr.contains('mala')) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFE53935), // Rouge
      Color(0xFFEC407A), // Rose
      Color(0xFF8E24AA), // Violet
      Color(0xFF1E88E5), // Bleu
      Color(0xFFFFEA00), // Jaune
      Color(0xFF43A047), // Vert
    ];
  }

  // RK - 15 / Malya (Gris à jaune à orange feu)
  if (a.contains('15') ||
      albumNorm == '15' ||
      titleNorm.contains('malya') ||
      idStr.contains('malya')) {
    return const [
      Color(0xFF424242), // Gris
      Color(0xFFFFD600), // Jaune
      Color(0xFFFF5722), // Orange feu
    ];
  }

  // MHD - MHD / Maman j'ai mal (Rouge à jaune à vert à bleu à blanc à rouge)
  if (a.contains('mhd') ||
      albumNorm == 'mhd' ||
      titleNorm.contains('maman jai mal') ||
      titleNorm.contains("maman j'ai mal") ||
      idStr.contains('maman_j_ai_mal')) {
    return const [
      Color(0xFFE53935), // Rouge
      Color(0xFFFFEA00), // Jaune
      Color(0xFF2E7D32), // Vert
      Color(0xFF1976D2), // Bleu
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFD32F2F), // Rouge
    ];
  }

  // Soolking - Vintage / Meleğim (Orangé à bleu foncé à violet)
  if (a.contains('vintage') ||
      albumNorm == 'vintage' ||
      titleNorm.contains('melegim') ||
      idStr.contains('melegim')) {
    return const [
      Color(0xFFFF7043), // Orangé
      Color(0xFF0D1B3E), // Bleu foncé
      Color(0xFF7B1FA2), // Violet
    ];
  }

  // Lorde - Melodrama / Melodrama (Violet à très peu de orangé à gris bleu à blanc gris)
  if (a.contains('melodrama') ||
      albumNorm.contains('melodrama') ||
      titleNorm.contains('melodrama') ||
      idStr.contains('melodrama')) {
    return const [
      Color(0xFF5E35B1), // Violet
      Color(0xFFFFAB91), // Très peu d'orangé
      Color(0xFF7986CB), // Gris bleu
      Color(0xFFE8EAF6), // Blanc gris
    ];
  }

  // Hamza - H-24 / Mi Amor (Bleu cyan avec plusieurs teintes)
  if (a.contains('h_24') ||
      a.contains('h-24') ||
      albumNorm.contains('h-24') ||
      albumNorm.contains('h 24') ||
      titleNorm.contains('mi amor') ||
      idStr.contains('mi_amor')) {
    return const [
      Color(0xFF00363A), // Bleu cyan très foncé
      Color(0xFF006064), // Bleu cyan profond
      Color(0xFF00838F), // Bleu cyan moyen
      Color(0xFF00ACC1), // Bleu cyan éclatant
      Color(0xFF4DD0E1), // Bleu cyan clair
      Color(0xFFE0F7FA), // Bleu cyan très clair
    ];
  }

  // J Balvin & Willy William - Vibras / Mi Gente (Vert à jaune à orangé à violet clair à violet foncé)
  if (a.contains('vibras') ||
      albumNorm.contains('vibras') ||
      titleNorm.contains('mi gente') ||
      idStr.contains('mi_gente')) {
    return const [
      Color(0xFF2E7D32), // Vert
      Color(0xFFFFEA00), // Jaune
      Color(0xFFFF5722), // Orangé
      Color(0xFFAB47BC), // Violet clair
      Color(0xFF4A148C), // Violet foncé
    ];
  }

  // C418 - Minecraft - Volume Alpha / Mice on Venus (Marron foncé à marron clair à vert clair à vert foncé)
  if (a.contains('minecraft_volume_alpha') ||
      albumNorm.contains('minecraft') ||
      titleNorm.contains('mice on venus') ||
      idStr.contains('mice_on_venus')) {
    return const [
      Color(0xFF3E2723), // Marron foncé
      Color(0xFF8D6E63), // Marron clair
      Color(0xFF7CB342), // Vert clair
      Color(0xFF1B5E20), // Vert foncé
    ];
  }

  // vs self - Everything Seems Better Now / Mourn (Blanc à jaune marron à 10% de bleu à 10% de rouge)
  if (a.contains('everything_seems_better_now') ||
      albumNorm.contains('everything seems better now') ||
      titleNorm.contains('mourn') ||
      idStr.contains('mourn')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFC7B198), // Jaune marron (sépia sable)
      Color(0xFFA8947C), // Jaune marron soutenu
      Color(0xFF455A64), // Bleu (10%)
      Color(0xFFA94442), // Rouge (10%)
    ];
  }

  // Travis Scott - UTOPIA / MY EYES (Marron à noir)
  if (a.contains('utopia') ||
      albumNorm.contains('utopia') ||
      titleNorm.contains('my eyes') ||
      idStr.contains('my_eyes')) {
    return const [
      Color(0xFF5D4037), // Marron
      Color(0xFF2E1C14), // Marron très foncé
      Color(0xFF111111), // Noir
    ];
  }

  // Franglish & Tory Lanez - My Salsa (Jaune à orange à marron à bleu)
  if (titleNorm.contains('my salsa') ||
      idStr.contains('my_salsa') ||
      a.contains('my_salsa')) {
    return const [
      Color(0xFFFFEA00), // Jaune
      Color(0xFFFF6D00), // Orange
      Color(0xFF5D4037), // Marron
      Color(0xFF03A9F4), // Bleu
    ];
  }

  // Sufjan Stevens - Mystery of Love (Jaune à bleu légèrement foncé)
  if (titleNorm.contains('mystery of love') ||
      idStr.contains('mystery_of_love') ||
      a.contains('mystery_of_love') ||
      albumNorm.contains('mystery of love') ||
      albumNorm.contains('call me by your name')) {
    return const [
      Color(0xFFFFEA00), // Jaune vif
      Color(0xFFFFD54F), // Jaune ambré
      Color(0xFF1976D2), // Bleu
      Color(0xFF0D47A1), // Bleu légèrement foncé
    ];
  }

  // Sean Paul & Dua Lipa - Mad Love: The Prequel / No Lie (Rose néon à bleu néon)
  if (a.contains('mad_love') ||
      albumNorm.contains('mad love') ||
      titleNorm.contains('no lie') ||
      idStr.contains('no_lie')) {
    return const [
      Color(0xFFFF1493), // Rose néon vif
      Color(0xFFFF4081), // Rose néon
      Color(0xFF80D8FF), // Bleu néon clair
      Color(0xFF00E5FF), // Bleu néon
    ];
  }

  // Lacrim - VENI VIDI VICI / No lo sé (Rouge orangé vif à rouge éclatant à rouge carmin profond)
  if (a.contains('veni_vidi_vici') ||
      albumNorm.contains('veni vidi vici') ||
      titleNorm.contains('no lo se') ||
      idStr.contains('no_lo_se')) {
    return const [
      Color(0xFFFF3D00), // Rouge orangé vif (ex-orange jauné rendu rougeoyant)
      Color(0xFFE53935), // Rouge éclatant (ex-orange rendu rouge)
      Color(0xFFB71C1C), // Rouge carmin profond (ex-rouge orangé rendu rouge sombre)
    ];
  }

  // The Marías - Submarine / No One Noticed (Bleu foncé à bleu violet très clair à blanc grisâtre)
  if (a.contains('submarine') ||
      albumNorm.contains('submarine') ||
      titleNorm.contains('no one noticed') ||
      idStr.contains('no_one_noticed')) {
    return const [
      Color(0xFF0D1B3E), // Bleu foncé
      Color(0xFF9FA8DA), // Bleu violet très clair
      Color(0xFFECEFF1), // Blanc grisâtre
    ];
  }

  // TLC - FanMail / No Scrubs (Gris verdâtre à gris légèrement blanc)
  if (a.contains('fanmail') ||
      albumNorm.contains('fanmail') ||
      titleNorm.contains('no scrubs') ||
      idStr.contains('no_scrubs')) {
    return const [
      Color(0xFF4A5D4E), // Gris verdâtre foncé
      Color(0xFF6B7F6F), // Gris verdâtre
      Color(0xFFCFD8DC), // Gris légèrement blanc
    ];
  }

  // PLK - 2069' / Nouvelles (Rouge orangé à orange à beige à blanc à noir)
  if (a.contains('2069') ||
      albumNorm.contains('2069') ||
      titleNorm.contains('nouvelles') ||
      idStr.contains('nouvelles')) {
    return const [
      Color(0xFFE64A19), // Rouge orangé
      Color(0xFFFF9800), // Orange
      Color(0xFFD2B48C), // Beige
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF111111), // Noir
    ];
  }

  // Lil Peep - LIVE FOREVER / nuts (Gris à orange à blanc orangé)
  if (a.contains('live_forever') ||
      albumNorm.contains('live forever') ||
      titleNorm.contains('nuts') ||
      idStr.contains('nuts')) {
    return const [
      Color(0xFF5D534E), // Gris
      Color(0xFFFF7043), // Orange
      Color(0xFFFFF3E0), // Blanc orangé
    ];
  }

  // Drake - Views / One Dance (Rouge à gris à blanc)
  if (a.contains('views') ||
      albumNorm == 'views' ||
      titleNorm.contains('one dance') ||
      idStr.contains('one_dance')) {
    return const [
      Color(0xFFD32F2F), // Rouge
      Color(0xFF607D8B), // Gris
      Color(0xFFECEFF1), // Blanc
    ];
  }

  // Mauvais Djo - L'undertaker Part.1 / Pilé (Bleu à jaune à marron bois)
  if (a.contains('undertaker') ||
      albumNorm.contains('undertaker') ||
      titleNorm.contains('pile') ||
      idStr.contains('pile')) {
    return const [
      Color(0xFF1565C0), // Bleu
      Color(0xFFFFEA00), // Jaune
      Color(0xFF8D5B3A), // Marron bois
    ];
  }

  // Pour deux âmes solitaires (Part.1) (Jaune blanc à jaune verdâtre à vert)
  if ((titleNorm.contains('ames solitaires') || idStr.contains('ames_solitaires')) &&
      (idStr.contains('part.1') || idStr.contains('part_1') || titleNorm.contains('part.1') || titleNorm.contains('part 1'))) {
    return const [
      Color(0xFFFFF9C4), // Jaune blanc
      Color(0xFFDCE775), // Jaune verdâtre
      Color(0xFF43A047), // Vert
    ];
  }

  // Pour deux âmes solitaires (Part.2) (Blanc à gris à gris foncé)
  if ((titleNorm.contains('ames solitaires') || idStr.contains('ames_solitaires')) &&
      (idStr.contains('part.2') || idStr.contains('part_2') || titleNorm.contains('part.2') || titleNorm.contains('part 2'))) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF9E9E9E), // Gris
      Color(0xFF37474F), // Gris foncé
    ];
  }

  // Niro - Les autres / Printemps blanc (Rouge à gris foncé à blanc)
  if (a.contains('les_autres') ||
      albumNorm.contains('les autres') ||
      titleNorm.contains('printemps blanc') ||
      idStr.contains('printemps_blanc')) {
    return const [
      Color(0xFFD32F2F), // Rouge
      Color(0xFF263238), // Gris foncé
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Major Lazer & J Balvin - Music Is the Weapon / Que calor (Bleu clair à vert jaunâtre à orange dominant à jaune blanchâtre)
  if (a.contains('music_is_the_weapon') ||
      albumNorm.contains('music is the weapon') ||
      titleNorm.contains('que calor') ||
      idStr.contains('que_calor')) {
    return const [
      Color(0xFF4FC3F7), // Bleu clair
      Color(0xFFC0CA33), // Vert jaunâtre
      Color(0xFFFF6D00), // Orange (dominant 1)
      Color(0xFFFF5722), // Orange (dominant 2)
      Color(0xFFFFF9C4), // Jaune blanchâtre
    ];
  }

  // Dadju - Gentleman 2.0 / Reine (Rouge à blanc à gris foncé à noir)
  if (a.contains('gentleman') ||
      albumNorm.contains('gentleman') ||
      titleNorm.contains('reine') ||
      idStr.contains('reine')) {
    return const [
      Color(0xFFE53935), // Rouge
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF37474F), // Gris foncé
      Color(0xFF111111), // Noir
    ];
  }

  // Niska - Commando / Réseaux (Jaune marron à vert à bleu grisâtre)
  if (a.contains('commando') ||
      albumNorm.contains('commando') ||
      titleNorm.contains('reseaux') ||
      idStr.contains('reseaux')) {
    return const [
      Color(0xFFC59B27), // Jaune marron
      Color(0xFF558B2F), // Vert
      Color(0xFF546E7A), // Bleu grisâtre
    ];
  }

  // Clean Bandit - What Is Love? / Rockabye (Blanc nuage à gris à bleu ciel à bleu foncé)
  if (titleNorm.contains('rockabye') ||
      idStr.contains('rockabye') ||
      a.contains('what_is_love') ||
      albumNorm.contains('what is love')) {
    return const [
      Color(0xFFFFFFFF), // Blanc nuage
      Color(0xFF90A4AE), // Gris
      Color(0xFF03A9F4), // Bleu ciel
      Color(0xFF0D47A1), // Bleu foncé
    ];
  }

  // Bilal Hassani - Euphories / Roi (Rose pastel à 70% et bleu clair pastel à 30%)
  if (titleNorm == 'roi' ||
      titleNorm.startsWith('roi ') ||
      idStr == 'roi' ||
      a.contains('euphories') ||
      albumNorm.contains('euphories')) {
    return const [
      Color(0xFFF48FB1), // Rose pastel
      Color(0xFFF06292), // Rose pastel moyen
      Color(0xFFEC407A), // Rose pastel profond
      Color(0xFF80D8FF), // Bleu clair pastel (30%)
    ];
  }

  // The Weeknd & Anitta - Hurry Up Tomorrow / São Paulo (Blanc à marron jaunâtre à noir)
  if (titleNorm.contains('sao paulo') ||
      idStr.contains('sao_paulo') ||
      a.contains('hurry_up_tomorrow') ||
      albumNorm.contains('hurry up tomorrow')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFB08958), // Marron jaunâtre
      Color(0xFF111111), // Noir
    ];
  }

  // Maître Gims - Mon coeur avait raison / Sapés comme jamais (Bleu foncé grisâtre à marron clair à noir)
  if (titleNorm.contains('sapes comme jamais') ||
      idStr.contains('sapes_comme_jamais') ||
      a.contains('sapes_comme_jamais')) {
    return const [
      Color(0xFF2E3A46), // Bleu foncé grisâtre
      Color(0xFF8D6E63), // Marron clair
      Color(0xFF111111), // Noir
    ];
  }

  // David Guetta - 7 / Say My Name (Vert à bleu foncé à marron orangé à blanc)
  if (titleNorm.contains('say my name') ||
      idStr.contains('say_my_name') ||
      a == '7' ||
      albumNorm == '7') {
    return const [
      Color(0xFF2E7D32), // Vert
      Color(0xFF0D47A1), // Bleu foncé
      Color(0xFFD84315), // Marron orangé
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Chimbala x Omega - Se Me Nota (Agarrame) (Blanc à jaune à orange à orange foncé)
  if (titleNorm.contains('se me nota') ||
      idStr.contains('se_me_nota') ||
      a.contains('se_me_nota') ||
      albumNorm.contains('se me nota')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFFFEA00), // Jaune
      Color(0xFFFF9800), // Orange
      Color(0xFFE65100), // Orange foncé
    ];
  }

  // Tyler, The Creator - Flower Boy / See You Again (Vert à jaune à jaune orangé à orange profond)
  if (titleNorm.contains('see you again') ||
      idStr.contains('see_you_again') ||
      a.contains('flower_boy') ||
      albumNorm.contains('flower boy')) {
    return const [
      Color(0xFF2E7D32), // Vert
      Color(0xFFFFEB3B), // Jaune
      Color(0xFFFFB300), // Jaune orangé
      Color(0xFFE64A19), // Orange profond
    ];
  }

  // Travis Scott - ASTROWORLD / SICKO MODE (Bleu à jaune doré à orange doré à rouge 10%)
  if (titleNorm.contains('sicko mode') ||
      idStr.contains('sicko_mode') ||
      a.contains('astroworld') ||
      albumNorm.contains('astroworld')) {
    return const [
      Color(0xFF0288D1), // Bleu
      Color(0xFFFFD54F), // Jaune doré
      Color(0xFFFF9800), // Orange doré
      Color(0xFFFF6D00), // Orange doré profond
      Color(0xFFE53935), // Rouge (10%)
    ];
  }

  // The Neighbourhood - The Neighbourhood / Softcore (Blanc à noir)
  if (titleNorm.contains('softcore') ||
      idStr.contains('softcore') ||
      a == 'the_neighbourhood' ||
      albumNorm == 'the neighbourhood') {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF757575), // Gris intermédiaire
      Color(0xFF111111), // Noir
    ];
  }

  // ThxSoMch - SPIT IN MY FACE! (Beige foncé à marron clair à noir clair)
  if (titleNorm.contains('spit in my face') ||
      idStr.contains('spit_in_my_face') ||
      a.contains('spit_in_my_face') ||
      albumNorm.contains('spit in my face')) {
    return const [
      Color(0xFFBCAAA4), // Beige foncé
      Color(0xFF8D6E63), // Marron clair
      Color(0xFF2C2C2C), // Noir clair
    ];
  }

  // twenty one pilots - Blurryface / Stressed Out (Blanc à gris à rouge à noir)
  if (titleNorm.contains('stressed out') ||
      idStr.contains('stressed_out') ||
      a.contains('blurryface') ||
      albumNorm.contains('blurryface')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF757575), // Gris
      Color(0xFFE53935), // Rouge
      Color(0xFF111111), // Noir
    ];
  }

  // Post Malone & Swae Lee - Sunflower (Rouge à blanc à noir)
  if (titleNorm.contains('sunflower') || idStr.contains('sunflower')) {
    return const [
      Color(0xFFE53935), // Rouge
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF111111), // Noir
    ];
  }

  // Kendrick Lamar - good kid, m.A.A.d city / Swimming Pools (Blanc à vert grisâtre à marron à bleu ciel)
  if (titleNorm.contains('swimming pools') ||
      idStr.contains('swimming_pools') ||
      a.contains('good_kid') ||
      albumNorm.contains('good kid')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF78909C), // Vert grisâtre
      Color(0xFF4E342E), // Marron
      Color(0xFF03A9F4), // Bleu ciel
    ];
  }

  // Luidji - Tristesse Business : Saison 1 / Système (Bleu foncé à bleu turquoise à jaune légèrement orangé)
  if (titleNorm.contains('systeme') ||
      idStr.contains('systeme') ||
      a.contains('tristesse_business') ||
      albumNorm.contains('tristesse business')) {
    return const [
      Color(0xFF0D47A1), // Bleu foncé
      Color(0xFF00E5FF), // Bleu turquoise
      Color(0xFFFFB74D), // Jaune légèrement orangé
    ];
  }

  // Glass Animals - How to Be a Human Being / Take a Slice (Vert à bleu à jaune à orange)
  if (titleNorm.contains('take a slice') ||
      idStr.contains('take_a_slice') ||
      a.contains('how_to_be_a_human_being') ||
      albumNorm.contains('how to be a human being')) {
    return const [
      Color(0xFF43A047), // Vert
      Color(0xFF0288D1), // Bleu
      Color(0xFFFFEB3B), // Jaune
      Color(0xFFFF6D00), // Orange
    ];
  }

  // Koba LaD - Ténébreux / Ténébreux #1 (Rouge à gris foncé à noir clair)
  if (titleNorm.contains('tenebreux') ||
      idStr.contains('tenebreux') ||
      a.contains('tenebreux') ||
      albumNorm.contains('tenebreux')) {
    return const [
      Color(0xFFD32F2F), // Rouge
      Color(0xFF37474F), // Gris foncé
      Color(0xFF262626), // Noir clair
    ];
  }

  // Seekae - Test & Recognise (Flume Re-work) (Blanc à noir)
  if ((titleNorm.contains('test') && titleNorm.contains('recognise')) ||
      (idStr.contains('test') && idStr.contains('recognise')) ||
      a.contains('test_and_recognise') ||
      albumNorm.contains('test & recognise')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF757575), // Gris intermédiaire
      Color(0xFF111111), // Noir
    ];
  }

  // The Weeknd - Beauty Behind the Madness / The Hills (Gris à noir)
  if (titleNorm.contains('the hills') ||
      idStr.contains('the_hills') ||
      a.contains('beauty_behind_the_madness') ||
      albumNorm.contains('beauty behind the madness')) {
    return const [
      Color(0xFFB0BEC5), // Gris clair
      Color(0xFF546E7A), // Gris
      Color(0xFF111111), // Noir
    ];
  }

  // Tame Impala - Currents / The Less I Know the Better (Gris à jaune orangé à rose à rouge rosé à violet)
  if (titleNorm.contains('less i know') ||
      idStr.contains('less_i_know') ||
      a.contains('currents') ||
      albumNorm.contains('currents')) {
    return const [
      Color(0xFF9E9E9E), // Gris
      Color(0xFFFFB300), // Jaune orangé
      Color(0xFFEC407A), // Rose
      Color(0xFFE91E63), // Rouge rosé
      Color(0xFF6A1B9A), // Violet
    ];
  }

  // Maître Gims - À contrecoeur (Pilule Violette) / Tout donner (Blanc grisâtre à violet foncé)
  if (titleNorm.contains('tout donner') ||
      idStr.contains('tout_donner') ||
      a.contains('contrecoeur') ||
      albumNorm.contains('contrecoeur')) {
    return const [
      Color(0xFFECEFF1), // Blanc grisâtre
      Color(0xFF512DA8), // Violet moyen
      Color(0xFF240046), // Violet foncé
    ];
  }

  // Burak Yeter - Tuesday (Violet clair à rose violet)
  if (titleNorm.contains('tuesday') ||
      idStr.contains('tuesday') ||
      a.contains('tuesday') ||
      albumNorm.contains('tuesday')) {
    return const [
      Color(0xFFBA68C8), // Violet clair
      Color(0xFFAB47BC), // Violet moyen
      Color(0xFFD81B60), // Rose violet
    ];
  }

  // French Montana - Jungle Rules / Unforgettable (Bleu verdâtre à jaune beige à orange blanc fourrure)
  if (titleNorm.contains('unforgettable') ||
      idStr.contains('unforgettable') ||
      a.contains('jungle_rules') ||
      albumNorm.contains('jungle rules')) {
    return const [
      Color(0xFF4DB6AC), // Bleu verdâtre
      Color(0xFFE0C39E), // Jaune beige
      Color(0xFFE89858), // Orange
      Color(0xFFFFF3E0), // Blanc fourrure
    ];
  }

  // Sexion d'Assaut - L'École des points vitaux / Wati by Night (Blanc à rouge à noir)
  if (titleNorm.contains('wati by night') ||
      idStr.contains('wati_by_night') ||
      a.contains('points_vitaux') ||
      albumNorm.contains('points vitaux')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFD32F2F), // Rouge
      Color(0xFF111111), // Noir
    ];
  }

  // ridgeclub - where am i supposed to go? (Jaune à gris à gris de route à bleu du ciel)
  if (titleNorm.contains('where am i supposed to go') ||
      idStr.contains('where_am_i_supposed_to_go') ||
      a.contains('where_am_i_supposed_to_go') ||
      albumNorm.contains('where am i supposed to go')) {
    return const [
      Color(0xFFFFD54F), // Jaune
      Color(0xFF90A4AE), // Gris
      Color(0xFF455A64), // Gris de route (béton)
      Color(0xFF81D4FA), // Bleu du ciel
    ];
  }

  // Eminem - Curtain Call: The Hits / Without Me (Noir à jaune doré à rouge)
  if (titleNorm.contains('without me') ||
      idStr.contains('without_me') ||
      a.contains('curtain_call') ||
      albumNorm.contains('curtain call')) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFFFFD54F), // Jaune doré
      Color(0xFFD32F2F), // Rouge
    ];
  }

  // Nicky Jam & J Balvin - X (Spanglish Version) (Vert à jaune à rouge orangé)
  if (titleNorm == 'x' ||
      titleNorm.startsWith('x ') ||
      titleNorm.startsWith('x(') ||
      idStr.startsWith('x_') ||
      a == 'x' ||
      albumNorm.startsWith('x ')) {
    return const [
      Color(0xFF43A047), // Vert
      Color(0xFFFFEA00), // Jaune
      Color(0xFFE64A19), // Rouge orangé
    ];
  }

  // Don Miguelo - Y que fue? (Blanc à marron à noir)
  if (titleNorm.contains('y que fue') ||
      idStr.contains('y_que_fue') ||
      a.contains('y_que_fue') ||
      albumNorm.contains('y que fue')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF8D6E63), // Marron
      Color(0xFF111111), // Noir
    ];
  }

  // JAY-Z - The Blueprint 2 / '03 Bonnie & Clyde (Bleu à gris clair à gris foncé à noir clair)
  if ((titleNorm.contains('bonnie') && titleNorm.contains('clyde')) ||
      idStr.contains('bonnie') ||
      a.contains('blueprint_2') ||
      albumNorm.contains('blueprint')) {
    return const [
      Color(0xFF1565C0), // Bleu
      Color(0xFFCFD8DC), // Gris clair
      Color(0xFF455A64), // Gris foncé
      Color(0xFF212121), // Noir clair
    ];
  }

  // The Neighbourhood - I Love You.
  if (a.contains('i_love_you') || albumNorm.contains('i love you') || titleNorm.contains('sweater weather') || idStr.contains('sweater_weather')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF9E9E9E), // Gris
      Color(0xFF000000), // Noir
    ];
  }

  // Tyler, The Creator - IGOR
  if (a.contains('igor') || albumNorm.contains('igor') || titleNorm.contains('gone, gone') || titleNorm.contains('gone gone') || idStr.contains('gone')) {
    return const [
      Color(0xFFFFC0CB), // Rose clair
      Color(0xFFFFC0CB),
      Color(0xFFFFC0CB),
    ];
  }

  // Nirvana - Nevermind
  if (a.contains('nevermind') || albumNorm.contains('nevermind') || titleNorm.contains('smells like teen spirit') || idStr.contains('smells_like_teen_spirit')) {
    return const [
      Color(0xFFFFF59D), // Jaune (peu)
      Color(0xFF00E5FF), // Cyan
      Color(0xFF1976D2), // Bleu
    ];
  }

  // Damso - Bēyāh
  if (a.contains('beyah') || albumNorm.contains('beyah') || a.contains('bēyāh') || idStr.contains('pa_pa_paw') || titleNorm.contains('pa pa paw')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFBDBDBD), // Gris moyen
      Color(0xFF424242), // Gris foncé
    ];
  }

  // PNL - Dans la légende
  if (a.contains('dans_la_legende') ||
      albumNorm.contains('dans la legende') ||
      titleNorm.contains('onizuka') ||
      idStr.contains('onizuka') ||
      titleNorm.contains('luz de luna') ||
      idStr.contains('luz_de_luna') ||
      titleNorm.contains('qlf') ||
      idStr.contains('qlf')) {
    return const [
      Color(0xFFFFEB3B), // Jaune
      Color(0xFFFF9800), // Orange
      Color(0xFF9C27B0), // Violet
    ];
  }

  // PNL - Deux frères
  if (a.contains('deux_freres') || albumNorm.contains('deux freres') || titleNorm.contains('misere') || idStr.contains('misere')) {
    return const [
      Color(0xFF2196F3), // Bleu
      Color(0xFF8E24AA), // Violet (transition)
      Color(0xFFF44336), // Rouge
    ];
  }

  // Dua Lipa - Future Nostalgia
  if (a.contains('future_nostalgia') || albumNorm.contains('future nostalgia')) {
    return const [
      Color(0xFF2196F3), // Bleu
      Color(0xFFE91E63), // Rose
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFFFEB3B), // Jaune
    ];
  }

  // Ninho - M.I.L.S
  if (a.contains('mils') || albumNorm.contains('mils')) {
    return const [
      Color(0xFFFFF8E7), // Blanc légèrement doré (Cosmic Latte)
      Color(0xFFFFF8E7),
      Color(0xFFD4AF37), // Or classique (Metallic Gold)
      Color(0xFFD4AF37),
    ];
  }

  // Kaaris - Or Noir
  if (a.contains('or_noir') || albumNorm.contains('or noir')) {
    return const [
      Color(0xFFFBE18D), // Or clair scintillant (pailleté)
      Color(0xFFFBE18D),
      Color(0xFFC5A059), // Or profond
      Color(0xFFC5A059),
    ];
  }

  // Damso - Batterie Faible
  if (a.contains('batterie_faible') || albumNorm.contains('batterie faible')) {
    return const [
      Color(0xFFFF7597),
      Color(0xFFFF7597),
      Color(0xFFC2185B),
      Color(0xFFC2185B),
    ];
  }

  // Damso - Lithopédion
  if (a.contains('lithopedion') || albumNorm.contains('lithopedion')) {
    return const [
      Color(0xFFB0BEC5),
      Color(0xFFB0BEC5),
      Color(0xFF2C3E50),
      Color(0xFF2C3E50),
    ];
  }

  // Nekfeu - Feu
  if (a == 'feu' || albumNorm == 'feu') {
    return const [
      Color(0xFFFF5722),
      Color(0xFFFF5722),
      Color(0xFFFFD700),
      Color(0xFFFFD700),
    ];
  }

  // Nekfeu - Cyborg
  if (a.contains('cyborg') || albumNorm.contains('cyborg')) {
    return const [
      Color(0xFFE53935),
      Color(0xFFE53935),
      Color(0xFF4A148C),
      Color(0xFF4A148C),
    ];
  }

  // Damso - Ipséité
  if (a.contains('ipseite') || albumNorm.contains('ipseite')) {
    return const [
      Color(0xFFF39C12),
      Color(0xFFF39C12),
      Color(0xFFFFD700),
      Color(0xFFFFD700),
    ];
  }

  // Angèle - Nonante-Cinq
  if (a.contains('nonante') || albumNorm.contains('nonante')) {
    return const [
      Color(0xFF0D47A1), // Bleu foncé
      Color(0xFF0D47A1), // Bleu foncé
      Color(0xFFD32F2F), // Rouge
      Color(0xFFFFC107), // Jaune
    ];
  }

  // Dadju - Poison ou Antidote
  if (a.contains('poison_ou_antidote') || (albumNorm.contains('poison') && albumNorm.contains('antidote'))) {
    return const [
      Color(0xFF1B5E20), // Vert très sombre
      Color(0xFF2E7D32), // Vert
      Color(0xFFFFB300), // Jaune
      Color(0xFFE040FB), // Violet (tirant vers le magenta pour bien se mélanger au jaune)
    ];
  }

  // Dégradé par défaut
  return const [
    Color(0xFF9C27B0),
    Color(0xFF9C27B0),
    Color(0xFF311B92),
    Color(0xFF311B92),
  ];
}

String getSafeFileName(String title) {
  final clean = title.toLowerCase().trim();
  if (clean == 'zoo' || clean == 'chargé' || clean == 'charge') {
    return 'or_noir';
  }
  if (clean == '2069' || clean == "2069'") {
    return "2069'";
  }
  if (clean.contains('minecraft') && clean.contains('volume beta')) {
    return 'minecraft_volume_beta';
  }
  if (clean.contains('minecraft') && clean.contains('volume alpha')) {
    return 'minecraft_volume_alpha';
  }
  if (clean.contains('jok') && clean.contains('travolta')) {
    return 'jok_travolta';
  }
  if (clean == 'charger' || clean.contains('franchement')) {
    return 'franchement';
  }
  if (clean.contains('we love summer') || clean == 'vida') {
    return 'vida';
  }
  if (clean.contains('rockabye')) {
    return 'what_is_love';
  }
  if (clean.contains('rmf') && clean.contains('wiosne')) {
    return 'the_wrong_kind_of_war';
  }
  if (clean.contains('masterpiece') || clean.contains('drop it like') || clean.contains('rhythm & gangsta')) {
    return 'rg_the_masterpiece';
  }
  if (clean.contains('sober') && (clean.contains('2') || clean.contains('pt'))) {
    return 'come_over_when_youre_sober_pt_2';
  }
  if (clean.contains('friday') && (clean.contains('dopamine') || clean.contains('riton') || clean.contains('mufasa'))) {
    return 'friday';
  }
  if (clean == 'thank u, next' || clean == 'thank u next' || clean == '7 rings') {
    return 'thank_u,_next';
  }
  if (clean.contains('goodbye') && clean.contains('riddance')) {
    return 'goodbye_and_good_riddance';
  }
  if (clean.contains('undertaker')) {
    return 'lundertaker_part_1';
  }
  if (clean.contains('gentleman')) {
    return 'gentleman_2_0';
  }
  if (clean.contains('test') && clean.contains('recognise')) {
    return 'test_and_recognise';
  }
  if (clean.startsWith('x') && (clean.contains('spanglish') || clean.contains('single'))) {
    return 'x';
  }
  if (clean.contains('blueprint') || clean.contains('bonnie')) {
    return 'the_blueprint_2';
  }
  if (clean.contains('good kid') && clean.contains('city')) {
    return 'good_kid_maad_city';
  }
  return title
      .replaceAll(RegExp(r'\s*\(.*?\)'), '') // Enlève (The Moonlight Edition), etc.
      .replaceAll('.', '')
      .replaceAll('!', '')
      .replaceAll('?', '')
      .replaceAll(':', '')
      .replaceAll("'", "")
      .replaceAll('’', '')
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('à', 'a')
      .replaceAll('ğ', 'g')
      .replaceAll('Ğ', 'g')
      .replaceAll(RegExp(r'[\u2010-\u2015\u2212]'), '-')
      .replaceAll(RegExp(r'^_+|_+$'), '')
      .replaceAll(RegExp(r'_+'), '_');
}

String _cleanTitle(String title) {
  // Enlève "(feat. Artiste)" ou "[ft. Artiste]"
  String cleaned = title.replaceAll(
    RegExp(r'\s*[(\[]f(?:ea)?t\.?\s+[^)\]]+[)\]]', caseSensitive: false),
    '',
  );
  // Enlève " feat. Artiste" (sans parenthèses) à la fin
  cleaned = cleaned.replaceAll(
    RegExp(r'\s+f(?:ea)?t\.?\s+.*', caseSensitive: false),
    '',
  );
  final trimmed = cleaned.trim();
  if (trimmed.toLowerCase() == 'melegim' || trimmed.toLowerCase() == 'meleğim') {
    return 'Meleğim';
  }
  return trimmed;
}

String getBaseId(String idStr) {
  return idStr
      .split('/')
      .last
      .replaceAll(RegExp(r'\.flac|\.mp3|\.wav', caseSensitive: false), '');
}

String normalizeSongId(String rawId) {
  final base = getBaseId(rawId);
  return '${ApiConfig.baseUrl}/$base.flac';
}

String formatArtist(String? artist) {
  if (artist == null || artist.isEmpty) return 'Inconnu';
  return artist.replaceAll(
    RegExp(r'\s+feat\.?\s+', caseSensitive: false),
    ' & ',
  );
}

List<String> extractArtists(String? rawArtist) {
  if (rawArtist == null || rawArtist.isEmpty) return ['Inconnu'];

  String artist = rawArtist;
  if (artist.toLowerCase().contains('tyler') && artist.toLowerCase().contains('creator')) {
    artist = artist.replaceAll(RegExp(r'tyler[\s,&]+the creator', caseSensitive: false), 'Tyler The Creator');
  }

  // Regex de séparation multi-artistes (duos, featurings, collaborations) :
  // - &
  // - et / ET / Et
  // - x / X / ×
  // - feat. / feat / ft. / ft / featuring
  // - with / avec
  // - virgules, points-virgules, slashs : , ; /
  final separator = RegExp(
    r'\s+&\s+|\s+et\s+|\s+[xX×]\s+|\s+(?:feat\.?|ft\.?|featuring)\s+|\s+(?:with|avec)\s+|[,;/]',
    caseSensitive: false,
  );

  final parts = artist.split(separator);
  final List<String> result = [];

  for (var part in parts) {
    var clean = part
        .replaceAll(RegExp(r'^[\(\[\{"\s]+|[\)\]\}"\s]+$'), '')
        .trim();
    if (clean.isEmpty) continue;

    // Harmonisation de la casse si le nom est entièrement en minuscules (ex: "tesher" -> "Tesher")
    if (clean == clean.toLowerCase()) {
      clean = clean.split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');
    }

    if (!result.any((a) => a.toLowerCase() == clean.toLowerCase())) {
      result.add(clean);
    }
  }

  return result.isNotEmpty ? result : ['Inconnu'];
}

String extractPrimaryArtist(String? rawArtist) {
  final list = extractArtists(rawArtist);
  return list.isNotEmpty ? list.first : 'Inconnu';
}

final RegExp _regexE = RegExp(r'[éèêë]');
final RegExp _regexA = RegExp(r'[àáâãäå]');
final RegExp _regexO = RegExp(r'[òóôõöø]');
final RegExp _regexI = RegExp(r'[ìíîï]');
final RegExp _regexU = RegExp(r'[ùúûü]');
final RegExp _regexN = RegExp(r'ñ');
final RegExp _regexC = RegExp(r'ç');

final Map<String, String> _normalizedCache = {};

String normalizeString(String text) {
  if (_normalizedCache.containsKey(text)) {
    return _normalizedCache[text]!;
  }
  final normalized = text
      .toLowerCase()
      .replaceAll(_regexE, 'e')
      .replaceAll(_regexA, 'a')
      .replaceAll(_regexO, 'o')
      .replaceAll(_regexI, 'i')
      .replaceAll(_regexU, 'u')
      .replaceAll(_regexN, 'n')
      .replaceAll(_regexC, 'c')
      .trim();
  _normalizedCache[text] = normalized;
  return normalized;
}

Future<void> clearTemporaryFiles() async {
  try {
    final cacheDir = await getTemporaryDirectory();
    if (cacheDir.existsSync()) {
      cacheDir.list().listen((file) {
        if (file.path.contains('just_audio_cache') ||
            file.path.contains('ExoPlayer') ||
            file.path.endsWith('.apk')) {
          file.deleteSync(recursive: true);
        }
      });
    }
  } catch (e) {
    debugPrint("Erreur lors du nettoyage du cache système : $e");
  }
}

void showCreatePlaylistDialog(
  BuildContext context,
  List<Color> themeColors, {
  String? songIdToAdd,
}) {
  String playlistName = '';
  final ValueNotifier<String?> selectedImageNotifier = ValueNotifier(null);

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: "Fermer",
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Align(
        alignment: const Alignment(0.0, -0.4),
        child: Material(
          type: MaterialType.transparency,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: FadeTransition(
              opacity: animation,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              colors: themeColors,
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ).createShader(bounds);
                          },
                          child: const Text(
                            "Nouvelle Playlist",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        ValueListenableBuilder<String?>(
                          valueListenable: selectedImageNotifier,
                          builder: (context, imagePath, _) {
                            final hasValidImage =
                                imagePath != null &&
                                imagePath.isNotEmpty &&
                                File(imagePath).existsSync();

                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    final picker = ImagePicker();
                                    final xfile = await picker.pickImage(
                                      source: ImageSource.gallery,
                                    );
                                    if (xfile != null) {
                                      selectedImageNotifier.value = xfile.path;
                                    }
                                  },
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.2,
                                        ),
                                      ),
                                    ),
                                    child: hasValidImage
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            child: Image.file(
                                              File(imagePath),
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : const Icon(
                                            CupertinoIcons.camera_fill,
                                            color: Colors.white54,
                                            size: 32,
                                          ),
                                  ),
                                ),
                                if (hasValidImage)
                                  Positioned(
                                    top: -10,
                                    right: -10,
                                    child: GestureDetector(
                                      onTap: () {
                                        selectedImageNotifier.value = null;
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: themeColors,
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black54,
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          CupertinoIcons.minus,
                                          color: Colors.white,
                                          size: 16,
                                          weight: 800,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 20),
                        ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              colors: themeColors,
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ).createShader(
                              Rect.fromCenter(
                                center: bounds.center,
                                width: 120,
                                height: bounds.height,
                              ),
                            );
                          },
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              textSelectionTheme: TextSelectionThemeData(
                                selectionHandleColor: themeColors[0],
                                selectionColor: themeColors[0].withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            child: TextField(
                              autofocus: true,
                              onChanged: (val) {
                                playlistName = val;
                              },
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              cursorColor: Colors.white,
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                hintText: "Nom de la playlist...",
                                hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  fontSize: 20,
                                ),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                                child: const Text(
                                  "Annuler",
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: themeColors,
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: CupertinoButton(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  onPressed: () {
                                    if (playlistName.trim().isNotEmpty) {
                                      final pName = playlistName.trim();

                                      if (!customPlaylistsNotifier.value
                                          .contains(pName)) {
                                        final currentList = List<String>.from(
                                          customPlaylistsNotifier.value,
                                        );
                                        currentList.add(pName);
                                        customPlaylistsNotifier.value =
                                            currentList;
                                      }

                                      if (songIdToAdd != null) {
                                        final currentContents =
                                            Map<String, Set<String>>.from(
                                              playlistContentsNotifier.value,
                                            );
                                        final currentSet = Set<String>.from(
                                          currentContents[pName] ?? <String>{},
                                        );
                                        currentSet.add(songIdToAdd);
                                        currentContents[pName] = currentSet;
                                        playlistContentsNotifier.value =
                                            currentContents;
                                      }

                                      if (selectedImageNotifier.value != null &&
                                          selectedImageNotifier
                                              .value!
                                              .isNotEmpty) {
                                        final currentImages =
                                            Map<String, String>.from(
                                              playlistImagesNotifier.value,
                                            );
                                        currentImages[pName] =
                                            selectedImageNotifier.value!;
                                        playlistImagesNotifier.value =
                                            currentImages;
                                      }
                                    }
                                    Navigator.pop(context);
                                  },
                                  child: const Text(
                                    "Créer",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  ).then((_) {
    selectedImageNotifier.dispose();
  });
}

// ====================================================
// GESTIONNAIRE DE SYNCHRONISATION CLOUD AUTOMATIQUE
// ====================================================
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
      }

      // Force la sauvegarde locale immédiate pour que le téléphone soit à jour
      final mmkv = MMKV.defaultMMKV();
      mmkv.encodeBool('isCrossfadeEnabled', isCrossfadeEnabledNotifier.value);
      mmkv.encodeInt('crossfadeDuration', crossfadeDurationNotifier.value);
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
}
