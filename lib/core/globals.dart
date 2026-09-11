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
  false,
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
  isLiquidGlassEnabledNotifier.value = mmkv.decodeBool('isLiquidGlassEnabled', defaultValue: true);
  isBatterySaverEnabledNotifier.value = mmkv.decodeBool('isBatterySaverEnabled', defaultValue: false);
  if (isLiquidGlassEnabledNotifier.value && isBatterySaverEnabledNotifier.value) {
    isLiquidGlassEnabledNotifier.value = false;
  }
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
    if (isLiquidGlassEnabledNotifier.value && isBatterySaverEnabledNotifier.value) {
      isBatterySaverEnabledNotifier.value = false;
    }
  });

  isBatterySaverEnabledNotifier.addListener(() {
    mmkv.encodeBool('isBatterySaverEnabled', isBatterySaverEnabledNotifier.value);
    if (isBatterySaverEnabledNotifier.value && isLiquidGlassEnabledNotifier.value) {
      isLiquidGlassEnabledNotifier.value = false;
    }
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
    final String fileName = Uri.decodeComponent(item.artUri?.pathSegments.last ?? '${getSafeFileName(getBaseId(item.id))}.jpg');
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

String normalizeAlbumName(String id, dynamic rawAlbum) {
  var albumName = (rawAlbum ?? 'Inconnu').toString();
  final lowerId = id.toLowerCase();
  final lowerAlbum = albumName.toLowerCase();

  if (lowerId.contains("can't_feel_my_face") || lowerId.contains('cant_feel_my_face')) {
    if (lowerAlbum.contains('now that')) {
      return 'Beauty Behind the Madness';
    }
  } else if (lowerId.contains('despacito')) {
    if (lowerAlbum.contains('summer')) {
      return 'VIDA';
    }
  } else if (lowerId.contains('shy')) {
    if (lowerAlbum.contains('rmf')) {
      return 'The Wrong Kind of War';
    }
  } else if (lowerId.contains('friday')) {
    if (lowerAlbum.contains('now that')) {
      return 'Friday (Dopamine re-edit)';
    }
  } else if (lowerId.contains('gypsy_woman')) {
    if (lowerAlbum.contains('firstclass')) {
      return 'Surprise';
    }
  } else if (lowerId.contains('my_salsa')) {
    if (lowerAlbum.contains('nrj')) {
      return 'Monsieur (Mood Edition)';
    }
  } else if (lowerId.contains('mi_gente')) {
    if (lowerAlbum.contains('now that')) {
      return 'Vibras';
    }
  } else if (lowerId.contains('no_lie')) {
    if (lowerAlbum.contains('now that')) {
      return 'Mad Love The Prequel';
    }
  } else if (lowerId.contains('lucie_from_paris')) {
    if (lowerAlbum.contains('inconnu')) {
      return 'Lucie from Paris';
    }
  } else if (lowerId.contains('lean_on')) {
    if (lowerAlbum.contains('now that')) {
      return 'Peace Is the Mission';
    }
  } else if (lowerId == 'solo' || lowerId == 'rockabye') {
    if (lowerAlbum.contains('now that') || lowerAlbum.contains('summer party')) {
      return 'What Is Love?';
    }
  } else if (lowerId == 'tuesday') {
    if (lowerAlbum.contains('bravo')) {
      return 'Tuesday';
    }
  }
  return albumName;
}

String resolveCoverName({
  required String id,
  required String albumName,
  String? coverName,
}) {
  final cleanId = id.toLowerCase().trim();
  final cleanAlbum = albumName.toLowerCase().trim();

  // 1. Dérogations spécifiques (priorités albums et singles ciblés)
  if (cleanId == 'zoo' || cleanId == 'charge') {
    return 'or_noir';
  }
  if (cleanId == 'pa_pa_paw') {
    return 'beyah';
  }
  if (cleanId == 'nouvelles' || coverName == '2069') {
    return "2069'";
  }
  // Gambi - LA VIE EST BELLE (priorité au JPG d'album spécifique sur le VPS)
  if (cleanId == 'popopop' || cleanId == 'puff_puff_puff' || cleanId == 'he_oh') {
    return 'la_vie_est_belle';
  }
  if (cleanId.contains("can't_feel_my_face") || cleanId.contains('cant_feel_my_face')) {
    return 'beauty_behind_the_madness';
  }
  if (cleanId == 'charger' || cleanAlbum.contains('franchement')) {
    return 'franchement';
  }
  if (cleanId == 'rockabye' || cleanId == 'solo') {
    return 'what_is_love';
  }
  if (cleanId.contains('despacito') || cleanAlbum.contains('we love summer') || cleanAlbum.contains('we_love_summer')) {
    return 'vida';
  }
  if (cleanId.contains('shy') || cleanAlbum.contains('rmf')) {
    return 'the_wrong_kind_of_war';
  }
  if (cleanId.contains('drop_it_like') || cleanId.contains('masterpiece') || cleanAlbum.contains('masterpiece')) {
    return 'rg_the_masterpiece';
  }
  if (cleanId.contains('falling_down') || cleanAlbum.contains('sober')) {
    return 'come_over_when_youre_sober_pt_2';
  }
  if (cleanId.contains('friday')) {
    return 'friday';
  }
  if (cleanId.contains('gypsy_woman') || cleanAlbum.contains('firstclass')) {
    return 'surprise';
  }
  if (cleanId.contains('my_salsa') || cleanAlbum.contains('nrj')) {
    return 'my_salsa';
  }
  if (cleanId.contains('mi_gente')) {
    return 'vibras';
  }
  if (cleanId.contains('no_lie')) {
    return 'mad_love_the_prequel';
  }
  if (cleanId.contains('lucie_from_paris')) {
    return 'lucie_from_paris';
  }
  if (cleanId.contains('lean_on')) {
    return 'peace_is_the_mission';
  }
  if (cleanId.contains('pour_deux_ames_solitaires') && cleanId.contains('1')) {
    return 'pour_deux_ames_solitaires_part_1';
  }
  if (cleanId.contains('pour_deux_ames_solitaires') && cleanId.contains('2')) {
    return 'pour_deux_ames_solitaires_part_2';
  }
  if (cleanId == 'tuesday') {
    return 'tuesday';
  }
  if (cleanId.contains('swimming_pools') || cleanAlbum.contains('maad')) {
    return 'good_kid_maad_city';
  }
  if (cleanId == 'you_know_you_like_it' || cleanId == 'let_me_love_you') {
    return 'encore';
  }
  if (cleanId == 'luz_de_luna') {
    return 'dans_la_legende';
  }
  if (cleanId.contains('smells_like_teen_spirit')) {
    return 'nevermind';
  }
  if (cleanId == 'all_i_need') {
    return 'in_rainbows';
  }

  // 2. Priorité au coverName explicite (si renseigné dans musiques.json)
  if (coverName != null && coverName.trim().isNotEmpty) {
    return coverName.trim();
  }

  // 3. Priorité au JPG d'album spécifique si l'album est valide
  if (albumName.trim().isNotEmpty && cleanAlbum != 'inconnu') {
    return getSafeFileName(albumName);
  }

  // 4. Fallback sur le safe file name de l'id
  return getSafeFileName(id);
}

String buildArtUriString(String imageName) {
  final safeUrlName = imageName.replaceAll('#', '%23');
  return '${ApiConfig.baseUrl}/$safeUrlName.jpg';
}

Uri buildArtUri(String imageName) {
  return Uri.parse(buildArtUriString(imageName));
}

void _parseMusiquesFromJson(List<dynamic> data) {
  globalPlaylist.clear();
  for (var jsonItem in data) {
    final id = jsonItem['id'] as String;
    var albumName = normalizeAlbumName(id, jsonItem['album']);
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

    final safeImageName = resolveCoverName(
      id: id,
      albumName: albumName,
      coverName: jsonItem['coverName'] as String?,
    );

    final mediaItem = MediaItem(
      id: '${ApiConfig.baseUrl}/$id.flac',
      album: albumName,
      title: cleanTitle(rawTitle),
      artist: _extractEnrichedArtist(rawTitle, rawArtist),
      artUri: buildArtUri(safeImageName),
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
        var albumName = normalizeAlbumName(id, jsonItem['album']);
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

        final safeImageName = resolveCoverName(
          id: id,
          albumName: albumName,
          coverName: jsonItem['coverName'] as String?,
        );
        
        entities.add(SongEntity(
          songId: id,
          title: rawTitle,
          artist: _extractEnrichedArtist(rawTitle, rawArtist),
          album: albumName,
          artUri: buildArtUriString(safeImageName),
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
        var album = normalizeAlbumName(entity.songId, entity.album);
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
