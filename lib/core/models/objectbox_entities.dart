import 'package:objectbox/objectbox.dart';

@Entity()
class SongEntity {
  @Id()
  int id = 0;

  @Unique()
  String songId;

  String title;
  String artist;
  String album;
  String? artUri;
  int durationSeconds;
  bool hasFlac;
  bool hasHiRes;

  SongEntity({
    required this.songId,
    required this.title,
    required this.artist,
    required this.album,
    this.artUri,
    required this.durationSeconds,
    this.hasFlac = true,
    this.hasHiRes = false,
  });
}

@Entity()
class PlaylistEntity {
  @Id()
  int id = 0;

  @Unique()
  String name;

  String? imagePath;

  final songs = ToMany<SongEntity>();

  PlaylistEntity({
    required this.name,
    this.imagePath,
  });
}

@Entity()
class LikedSongEntity {
  @Id()
  int id = 0;

  @Unique()
  String songId;

  LikedSongEntity({required this.songId});
}

@Entity()
class PlayCountEntity {
  @Id()
  int id = 0;

  @Unique()
  String songId;

  int count;

  PlayCountEntity({required this.songId, required this.count});
}

@Entity()
class ArtistScoreEntity {
  @Id()
  int id = 0;

  @Unique()
  String artist;

  int score;
  int listeningTimeSeconds;

  ArtistScoreEntity({
    required this.artist,
    required this.score,
    this.listeningTimeSeconds = 0,
  });
}

@Entity()
class SearchHistoryEntity {
  @Id()
  int id = 0;

  String query;
  int timestamp;

  SearchHistoryEntity({required this.query, required this.timestamp});
}
