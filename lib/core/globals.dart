import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:mmkv/mmkv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:musicality/core/api_config.dart';
import 'package:musicality/core/models/objectbox_entities.dart';
import 'package:musicality/core/objectbox_service.dart';
import 'package:musicality/core/my_audio_handler.dart';
import 'package:musicality/core/string_utils.dart';
import 'package:musicality/core/cloud_sync_service.dart';
import 'package:musicality/objectbox.g.dart';

export 'package:musicality/core/string_utils.dart';
export 'package:musicality/core/cloud_sync_service.dart';
export 'package:musicality/core/recommendation_service.dart';
export 'package:musicality/core/lyrics_service.dart';
export 'package:musicality/core/song_download_service.dart';
export 'package:musicality/core/app_update_service.dart';
export 'package:musicality/ui/widgets/cached_album_art.dart';
export 'package:musicality/ui/theme/album_gradients.dart';
export 'package:musicality/ui/sheets/create_playlist_dialog.dart';
export 'package:musicality/ui/sheets/edit_playlist_dialog.dart';
export 'package:musicality/ui/sheets/auth_dialog.dart';
export 'package:musicality/ui/widgets/account_profile_header.dart';
export 'package:musicality/ui/widgets/audio_quality_settings_card.dart';
export 'package:musicality/ui/widgets/storage_cache_settings_card.dart';
export 'package:musicality/ui/widgets/crossfade_settings_card.dart';
export 'package:musicality/ui/widgets/explorer_section_card.dart';
export 'package:musicality/ui/widgets/explorer_contents.dart';


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
final ValueNotifier<bool> isHapticFeedbackEnabledNotifier = ValueNotifier<bool>(true);

// ALGORITHME
final ValueNotifier<Map<String, int>> artistScoresNotifier =
    ValueNotifier<Map<String, int>>({});
final ValueNotifier<Map<String, int>> artistListeningTimeNotifier =
    ValueNotifier<Map<String, int>>({});

// FONCTION DE MISE À JOUR DES SCORES

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

  isHapticFeedbackEnabledNotifier.value = mmkv.decodeBool('isHapticFeedbackEnabled', defaultValue: true);
  isHapticFeedbackEnabledNotifier.addListener(() {
    mmkv.encodeBool('isHapticFeedbackEnabled', isHapticFeedbackEnabledNotifier.value);
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
      title: cleanTitle(rawTitle),
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
          title: cleanTitle(entity.title),
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
