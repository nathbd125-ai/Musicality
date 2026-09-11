import 'package:musicality/objectbox.g.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'models/objectbox_entities.dart';
import 'package:mmkv/mmkv.dart';
import 'dart:convert';

class ObjectBoxService {
  late final Store store;
  late final Box<SongEntity> songBox;
  late final Box<PlaylistEntity> playlistBox;
  late final Box<LikedSongEntity> likedSongBox;
  late final Box<PlayCountEntity> playCountBox;
  late final Box<ArtistScoreEntity> artistScoreBox;
  late final Box<SearchHistoryEntity> searchHistoryBox;

  ObjectBoxService._create(this.store) {
    songBox = store.box<SongEntity>();
    playlistBox = store.box<PlaylistEntity>();
    likedSongBox = store.box<LikedSongEntity>();
    playCountBox = store.box<PlayCountEntity>();
    artistScoreBox = store.box<ArtistScoreEntity>();
    searchHistoryBox = store.box<SearchHistoryEntity>();
  }

  static Future<ObjectBoxService> create() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final storeDir = p.join(docsDir.path, "obx-musicality");
    final store = await openStore(directory: storeDir);
    return ObjectBoxService._create(store);
  }

  void migrateFromMMKV(MMKV mmkv) {
    // Migration Liked Songs
    final savedLikesStr = mmkv.decodeString('likedSongs');
    if (savedLikesStr != null && likedSongBox.isEmpty()) {
      final oldLikes = json.decode(savedLikesStr).cast<String>();
      likedSongBox.putMany(oldLikes.map((id) => LikedSongEntity(songId: id)).toList().cast<LikedSongEntity>());
      mmkv.removeValue('likedSongs');
    }

    // Migration Play Counts
    final savedPlayCountsStr = mmkv.decodeString('songPlayCounts');
    if (savedPlayCountsStr != null && playCountBox.isEmpty()) {
      final Map<String, dynamic> decodedCounts = json.decode(savedPlayCountsStr);
      final entities = decodedCounts.entries.map((e) => PlayCountEntity(songId: e.key, count: e.value as int)).toList();
      playCountBox.putMany(entities);
      mmkv.removeValue('songPlayCounts');
    }

    // Migration Artist Scores
    final savedScoresStr = mmkv.decodeString('artistScores');
    if (savedScoresStr != null && artistScoreBox.isEmpty()) {
      final Map<String, dynamic> decodedScores = json.decode(savedScoresStr);
      final entities = decodedScores.entries.map((e) => ArtistScoreEntity(artist: e.key, score: e.value as int)).toList();
      artistScoreBox.putMany(entities);
      mmkv.removeValue('artistScores');
    }

    // Migration Artist Times
    final savedTimesStr = mmkv.decodeString('artistTimes');
    if (savedTimesStr != null) {
      final Map<String, dynamic> decodedTimes = json.decode(savedTimesStr);
      for (var entry in decodedTimes.entries) {
        var entity = artistScoreBox.query(ArtistScoreEntity_.artist.equals(entry.key)).build().findFirst();
        if (entity != null) {
          entity.listeningTimeSeconds = entry.value as int;
          artistScoreBox.put(entity);
        } else {
          artistScoreBox.put(ArtistScoreEntity(artist: entry.key, score: 0, listeningTimeSeconds: entry.value as int));
        }
      }
      mmkv.removeValue('artistTimes');
    }

    // Migration Search History
    final savedSearchHistoryStr = mmkv.decodeString('searchHistory');
    if (savedSearchHistoryStr != null && searchHistoryBox.isEmpty()) {
      final oldHistory = json.decode(savedSearchHistoryStr).cast<String>();
      final entities = oldHistory.map((query) => SearchHistoryEntity(query: query, timestamp: DateTime.now().millisecondsSinceEpoch)).toList().cast<SearchHistoryEntity>();
      searchHistoryBox.putMany(entities);
      mmkv.removeValue('searchHistory');
    }
  }
}

late ObjectBoxService obx;
