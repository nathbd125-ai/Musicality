// ignore_for_file: experimental_member_use, deprecated_member_use, depend_on_referenced_packages, invalid_use_of_experimental_api

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:google_sign_in/google_sign_in.dart';

late AudioHandler _audioHandler;
late String _documentPath;

// --- CONFIGURATION VPS ---
class ApiConfig {
  static const String baseUrl = 'http://164.132.104.67/media/Musicality';
}

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
final ValueNotifier<bool> isDownloadLosslessNotifier = ValueNotifier<bool>(
  true,
);
final ValueNotifier<bool> isCacheEnabledNotifier = ValueNotifier<bool>(false);
final ValueNotifier<int> cacheLimitNotifier = ValueNotifier<int>(100);

// ALGORITHME
final ValueNotifier<Map<String, int>> artistScoresNotifier =
    ValueNotifier<Map<String, int>>({});
final ValueNotifier<Map<String, int>> artistListeningTimeNotifier =
    ValueNotifier<Map<String, int>>({});

// FONCTION DE MISE À JOUR DES SCORES
void updateArtistScore(String artist, int points) {
  if (artist.isEmpty) return;
  final current = Map<String, int>.from(artistScoresNotifier.value);
  for (var a in _extractArtists(artist)) {
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

        int localIndex = _playlist.indexWhere(
          (item) =>
              _normalizeString(item.title) == _normalizeString(title) ||
              _normalizeString(title).contains(_normalizeString(item.title)),
        );

        if (localIndex != -1) {
          final localItem = _playlist[localIndex];
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
  final prefs = await SharedPreferences.getInstance();
  _documentPath = (await getApplicationDocumentsDirectory()).path;

  // Création du dossier cache s'il n'existe pas
  final cacheDir = Directory('$_documentPath/cache');
  if (!cacheDir.existsSync()) {
    cacheDir.createSync();
  }

  // Chargement paramètres Compte
  final savedProfile = prefs.getString('userProfileImage');
  if (savedProfile != null && savedProfile.isNotEmpty) {
    userProfileImageNotifier.value = savedProfile;
  }

  isLosslessNotifier.value = prefs.getBool('isLossless') ?? false;
  isDownloadLosslessNotifier.value =
      prefs.getBool('isDownloadLossless') ?? true;
  isCacheEnabledNotifier.value = prefs.getBool('isCacheEnabled') ?? false;
  cacheLimitNotifier.value = prefs.getInt('cacheLimit') ?? 100;

  isLosslessNotifier.addListener(() {
    prefs.setBool('isLossless', isLosslessNotifier.value);
    if (_audioHandler is MyAudioHandler) {
      (_audioHandler as MyAudioHandler).reloadAudioSourcesForQuality();
    }
  });

  isDownloadLosslessNotifier.addListener(() {
    prefs.setBool('isDownloadLossless', isDownloadLosslessNotifier.value);
  });

  isCacheEnabledNotifier.addListener(() {
    prefs.setBool('isCacheEnabled', isCacheEnabledNotifier.value);
    if (_audioHandler is MyAudioHandler) {
      (_audioHandler as MyAudioHandler).reloadAudioSourcesForQuality();
    }
  });

  cacheLimitNotifier.addListener(() {
    prefs.setInt('cacheLimit', cacheLimitNotifier.value);
  });

  userProfileImageNotifier.addListener(() {
    if (userProfileImageNotifier.value != null) {
      prefs.setString('userProfileImage', userProfileImageNotifier.value!);
    }
  });

  for (var item in _playlist) {
    final coverFile = File(
      '$_documentPath/${_getSafeFileName(item.title)}.jpg',
    );
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

  final savedScoresStr = prefs.getString('artistScores') ?? '{}';
  final Map<String, dynamic> decodedScores = json.decode(savedScoresStr);
  Map<String, int> loadedScores = decodedScores.map(
    (key, value) => MapEntry(key, value as int),
  );

  final savedTimesStr = prefs.getString('artistTimes') ?? '{}';
  final Map<String, dynamic> decodedTimes = json.decode(savedTimesStr);
  artistListeningTimeNotifier.value = decodedTimes.map(
    (key, value) => MapEntry(key, value as int),
  );

  Timer? timesDebounce;
  artistListeningTimeNotifier.addListener(() {
    timesDebounce?.cancel();
    timesDebounce = Timer(const Duration(seconds: 5), () {
      prefs.setString(
        'artistTimes',
        json.encode(artistListeningTimeNotifier.value),
      );
    });
  });

  final savedPlayCountsStr = prefs.getString('songPlayCounts') ?? '{}';
  final Map<String, dynamic> decodedCounts = json.decode(savedPlayCountsStr);
  songPlayCountNotifier.value = decodedCounts.map(
    (key, value) => MapEntry(key, value as int),
  );

  Timer? playCountDebounce;
  songPlayCountNotifier.addListener(() {
    playCountDebounce?.cancel();
    playCountDebounce = Timer(const Duration(seconds: 5), () {
      prefs.setString(
        'songPlayCounts',
        json.encode(songPlayCountNotifier.value),
      );
    });
  });

  final savedLikes = prefs.getStringList('likedSongs') ?? [];

  bool hasMigrated = prefs.getBool('hasMigratedOldLikes') ?? false;
  if (!hasMigrated && savedLikes.isNotEmpty) {
    for (String songId in savedLikes) {
      try {
        final item = _playlist.firstWhere((e) => e.id == songId);
        if (item.artist != null) {
          loadedScores[item.artist!] = (loadedScores[item.artist!] ?? 0) + 10;
        }
      } catch (e) {
        debugPrint("Erreur migration favoris : $e");
      }
    }
    prefs.setBool('hasMigratedOldLikes', true);
  }

  artistScoresNotifier.value = loadedScores;

  Timer? scoresDebounce;
  artistScoresNotifier.addListener(() {
    scoresDebounce?.cancel();
    scoresDebounce = Timer(const Duration(seconds: 5), () {
      prefs.setString('artistScores', json.encode(artistScoresNotifier.value));
    });
  });

  likedSongsNotifier.value = savedLikes.toSet();
  likedSongsNotifier.addListener(() {
    prefs.setStringList('likedSongs', likedSongsNotifier.value.toList());
  });

  final savedSearchHistory = prefs.getStringList('searchHistory') ?? [];
  searchHistoryNotifier.value = savedSearchHistory;
  searchHistoryNotifier.addListener(() {
    prefs.setStringList('searchHistory', searchHistoryNotifier.value);
  });

  final savedPlaylists = prefs.getStringList('customPlaylists') ?? [];
  Map<String, Set<String>> initialContents = {};
  Map<String, String> initialImages = {};
  List<String> validPlaylists = [];

  for (String pName in savedPlaylists) {
    final content = prefs.getStringList('playlist_content_$pName') ?? [];
    if (content.isNotEmpty) {
      initialContents[pName] = content.toSet();
      validPlaylists.add(pName);

      final img = prefs.getString('playlist_image_$pName');
      if (img != null && img.isNotEmpty) {
        initialImages[pName] = img;
      }
    } else {
      prefs.remove('playlist_content_$pName');
      prefs.remove('playlist_image_$pName');
    }
  }

  customPlaylistsNotifier.value = validPlaylists;
  prefs.setStringList('customPlaylists', validPlaylists);

  customPlaylistsNotifier.addListener(() {
    prefs.setStringList('customPlaylists', customPlaylistsNotifier.value);
  });

  playlistContentsNotifier.value = initialContents;
  playlistContentsNotifier.addListener(() {
    final contents = playlistContentsNotifier.value;
    for (String pName in customPlaylistsNotifier.value) {
      prefs.setStringList(
        'playlist_content_$pName',
        (contents[pName] ?? {}).toList(),
      );
    }
  });

  playlistImagesNotifier.value = initialImages;
  playlistImagesNotifier.addListener(() {
    final images = playlistImagesNotifier.value;
    for (String pName in customPlaylistsNotifier.value) {
      if (images.containsKey(pName)) {
        prefs.setString('playlist_image_$pName', images[pName]!);
      } else {
        prefs.remove('playlist_image_$pName');
      }
    }
  });
}

Widget getLocalOrNetworkImage(MediaItem item, {double? width, double? height}) {
  final coverFile = File('$_documentPath/${_getSafeFileName(item.title)}.jpg');
  if (coverFile.existsSync()) {
    return Image.file(
      coverFile,
      width: width,
      height: height,
      cacheWidth: 300,
      fit: BoxFit.cover,
    );
  } else {
    return Image.network(
      item.artUri.toString(),
      width: width,
      height: height,
      cacheWidth: 300,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          Container(color: Colors.black26, width: width, height: height),
    );
  }
}

class LyricLine {
  final Duration time;
  final String text;
  LyricLine({required this.time, required this.text});
}

List<MediaItem> _playlist = [];

Future<void> fetchMusiques() async {
  try {
    final response = await http
        .get(Uri.parse('${ApiConfig.baseUrl}/musiques.json'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      _playlist.clear();
      for (var jsonItem in data) {
        final id = jsonItem['id'] as String;
        final albumName = jsonItem['album'] ?? 'Inconnu';
        _playlist.add(
          MediaItem(
            id: '${ApiConfig.baseUrl}/$id.flac',
            album: albumName,
            title: _cleanTitle(jsonItem['title'] ?? id),
            artist: jsonItem['artist'] ?? 'Inconnu',
            artUri: Uri.parse(
              '${ApiConfig.baseUrl}/${_getSafeFileName(albumName)}.jpg',
            ),
            duration: Duration(seconds: jsonItem['durationSeconds'] ?? 0),
            extras: {'hasFlac': jsonItem['hasFlac'] ?? true},
          ),
        );
      }
      debugPrint('Musiques chargées avec succès : ${_playlist.length}');
    } else {
      debugPrint(
        'Erreur réseau lors du chargement des musiques : ${response.statusCode}',
      );
    }
  } catch (e) {
    debugPrint('Erreur lors de la récupération des musiques : $e');
  }
}

List<Color> _getAlbumGradientColors(String album) {
  final a = _getSafeFileName(album);
  if (a.contains('mils')) {
    return const [
      Color(0xFFFFF8E7), // Blanc légèrement doré (Cosmic Latte)
      Color(0xFFFFF8E7),
      Color(0xFFD4AF37), // Or classique (Metallic Gold)
      Color(0xFFD4AF37),
    ];
  } else if (a == 'batterie_faible') {
    return const [
      Color(0xFFFF7597),
      Color(0xFFFF7597),
      Color(0xFFC2185B),
      Color(0xFFC2185B),
    ];
  } else if (a == 'lithopedion') {
    return const [
      Color(0xFFB0BEC5),
      Color(0xFFB0BEC5),
      Color(0xFF2C3E50),
      Color(0xFF2C3E50),
    ];
  } else if (a == 'feu') {
    return const [
      Color(0xFFFF5722),
      Color(0xFFFF5722),
      Color(0xFFFFD700),
      Color(0xFFFFD700),
    ];
  } else if (a == 'cyborg') {
    return const [
      Color(0xFFE53935),
      Color(0xFFE53935),
      Color(0xFF4A148C),
      Color(0xFF4A148C),
    ];
  } else if (a == 'ipseite') {
    return const [
      Color(0xFFF39C12),
      Color(0xFFF39C12),
      Color(0xFFFFD700),
      Color(0xFFFFD700),
    ];
  } else if (a == 'nonante-cinq') {
    // Bleu très dominant, transition vers rouge (crée un beau violet) puis jaune
    // On évite le passage Bleu -> Jaune qui crée une couleur "boue/vert" dégueu
    return const [
      Color(0xFF0D47A1), // Bleu foncé
      Color(0xFF0D47A1), // Bleu foncé
      Color(0xFFD32F2F), // Rouge
      Color(0xFFFFC107), // Jaune
    ];
  } else if (a == 'poison_ou_antidote') {
    // Bon gros vert dominant, puis jaune et violet très légers
    return const [
      Color(0xFF1B5E20), // Vert très sombre
      Color(0xFF2E7D32), // Vert
      Color(0xFFFFB300), // Jaune
      Color(0xFFE040FB), // Violet (tirant vers le magenta pour bien se mélanger au jaune)
    ];
  } else {
    return const [
      Color(0xFF9C27B0),
      Color(0xFF9C27B0),
      Color(0xFF311B92),
      Color(0xFF311B92),
    ];
  }
}

String _getSafeFileName(String title) {
  return title
      .toLowerCase()
      .replaceAll(' ', '_')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('à', 'a')
      .replaceAll('.', '')
      .replaceAll(RegExp(r'[\u2010-\u2015\u2212]'), '-');
}

String _cleanTitle(String title) {
  // Enlève "(feat. Artiste)" ou "[ft. Artiste]"
  String cleaned = title.replaceAll(RegExp(r'\s*[\(\[]f(?:ea)?t\.?\s+[^)\]]+[\)\]]', caseSensitive: false), '');
  // Enlève " feat. Artiste" (sans parenthèses) à la fin
  cleaned = cleaned.replaceAll(RegExp(r'\s+f(?:ea)?t\.?\s+.*', caseSensitive: false), '');
  return cleaned.trim();
}

String _formatArtist(String? artist) {
  if (artist == null || artist.isEmpty) return 'Inconnu';
  return artist.replaceAll(RegExp(r'\s+feat\.?\s+', caseSensitive: false), ' & ');
}

List<String> _extractArtists(String? rawArtist) {
  if (rawArtist == null || rawArtist.isEmpty) return ['Inconnu'];
  // On ne garde que l'artiste principal (le premier)
  final primaryArtist = rawArtist
      .split(RegExp(r'\s+&\s+|\s+feat\.?\s+|,', caseSensitive: false))
      .first
      .trim();
  return [primaryArtist.isNotEmpty ? primaryArtist : 'Inconnu'];
}

final RegExp _regexE = RegExp(r'[éèêë]');
final RegExp _regexA = RegExp(r'[àáâãäå]');
final RegExp _regexO = RegExp(r'[òóôõöø]');
final RegExp _regexI = RegExp(r'[ìíîï]');
final RegExp _regexU = RegExp(r'[ùúûü]');
final RegExp _regexN = RegExp(r'ñ');
final RegExp _regexC = RegExp(r'ç');

final Map<String, String> _normalizedCache = {};

String _normalizeString(String text) {
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
            file.path.contains('ExoPlayer')) {
          file.deleteSync(recursive: true);
        }
      });
    }
  } catch (e) {
    debugPrint("Erreur lors du nettoyage du cache système : $e");
  }
}

class _HorizontalClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, -100, size.width, size.height + 200);
  }

  @override
  bool shouldReclip(CustomClipper<Rect> oldClipper) => false;
}

class MarqueeWidget extends StatefulWidget {
  final Widget child;
  final String resetKey;

  const MarqueeWidget({super.key, required this.child, required this.resetKey});

  @override
  State<MarqueeWidget> createState() => _MarqueeWidgetState();
}

class _MarqueeWidgetState extends State<MarqueeWidget> {
  late ScrollController _scrollController;
  bool _isScrolling = false;
  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndScroll());
  }

  @override
  void didUpdateWidget(MarqueeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) {
      _isScrolling = false;
      _needsScroll = false;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndScroll());
    }
  }

  void _checkAndScroll() async {
    final currentKey = widget.resetKey;
    if (!mounted || !_scrollController.hasClients) return;
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted || !_scrollController.hasClients || widget.resetKey != currentKey) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll > 10) {
      setState(() {
        _needsScroll = true;
      });
      _startScrolling();
    } else {
      setState(() {
        _needsScroll = false;
      });
    }
  }

  void _startScrolling() async {
    final currentKey = widget.resetKey;
    if (_isScrolling) return;
    _isScrolling = true;

    while (_isScrolling && mounted && widget.resetKey == currentKey) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || !_scrollController.hasClients || widget.resetKey != currentKey || !_isScrolling) break;

      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll <= 0) break;

      await _scrollController.animateTo(
        maxScroll,
        duration: Duration(milliseconds: (maxScroll * 30).toInt()),
        curve: Curves.linear,
      );

      if (!mounted || widget.resetKey != currentKey || !_isScrolling) break;
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted || !_scrollController.hasClients || widget.resetKey != currentKey || !_isScrolling) break;

      await _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _isScrolling = false;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = ClipRect(
      clipper: _HorizontalClipper(),
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        clipBehavior: Clip.none,
        child: widget.child,
      ),
    );

    if (!_needsScroll) {
      return child;
    }

    return AnimatedBuilder(
      animation: _scrollController,
      builder: (context, childWidget) {
        double offset = _scrollController.hasClients
            ? _scrollController.offset
            : 0.0;
        double leftFadeIntensity = (offset / 15.0).clamp(0.0, 1.0);
        double leftStop = 0.05 * leftFadeIntensity;

        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0.0, leftStop, 0.95, 1.0],
            ).createShader(bounds);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3.0),
            child: childWidget,
          ),
        );
      },
      child: child,
    );
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
        'isDownloadLossless': isDownloadLosslessNotifier.value,
        'isCacheEnabled': isCacheEnabledNotifier.value,
        'cacheLimit': cacheLimitNotifier.value,
      },
      'lastSync': FieldValue.serverTimestamp(),
    };
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set(data);
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('pendingCloudSync', false);
    debugPrint("☁️ Sauvegarde auto réussie");
  } catch (e) {
    debugPrint("❌ Erreur de sauvegarde auto : $e");
  }
}

void triggerAutoSync() {
  if (FirebaseAuth.instance.currentUser == null) return;

  SharedPreferences.getInstance().then((prefs) {
    prefs.setBool('pendingCloudSync', true);
  });

  _autoSyncTimer?.cancel();
  _autoSyncTimer = Timer(const Duration(seconds: 5), () {
    performCloudBackup();
  });
}

Future<void> performCloudRestore() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final hasPendingSync = prefs.getBool('pendingCloudSync') ?? false;

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
        ).toSet();
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
        artistScoresNotifier.value = Map<String, int>.from(
          data['artistScores'],
        );
      }
      if (data['artistListeningTime'] != null) {
        artistListeningTimeNotifier.value = Map<String, int>.from(
          data['artistListeningTime'],
        );
      }
      if (data['songPlayCount'] != null) {
        songPlayCountNotifier.value = Map<String, int>.from(
          data['songPlayCount'],
        );
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
          restoredContents[key] = List<String>.from(value).toSet();
        });
        playlistContentsNotifier.value = restoredContents;
      }

      if (data['settings'] != null) {
        final settings = data['settings'];
        isLosslessNotifier.value = settings['isLossless'] ?? false;
        isDownloadLosslessNotifier.value =
            settings['isDownloadLossless'] ?? true;
        isCacheEnabledNotifier.value = settings['isCacheEnabled'] ?? false;
        cacheLimitNotifier.value = settings['cacheLimit'] ?? 100;
      }

      // Force la sauvegarde locale immédiate pour que le téléphone soit à jour
      final prefs = await SharedPreferences.getInstance();
      prefs.setStringList('likedSongs', likedSongsNotifier.value.toList());
      prefs.setStringList('customPlaylists', customPlaylistsNotifier.value);
      prefs.setStringList('searchHistory', searchHistoryNotifier.value);
      prefs.setString('artistScores', json.encode(artistScoresNotifier.value));
      prefs.setString(
        'artistTimes',
        json.encode(artistListeningTimeNotifier.value),
      );
      prefs.setString(
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
  isDownloadLosslessNotifier.addListener(triggerAutoSync);
  isCacheEnabledNotifier.addListener(triggerAutoSync);
  cacheLimitNotifier.addListener(triggerAutoSync);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await fetchMusiques();

  // INITIALISATION DE FIREBASE
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await initPersistence();
  await clearTemporaryFiles();

  // --- NOUVEAUTÉ : ON LANCE LA SYNCHRONISATION AUTOMATIQUE ---
  initAutoSyncListeners();
  await performCloudRestore(); // Télécharge les données si on est déjà connecté
  // -----------------------------------------------------------

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  // ignore: unused_local_variable
  _audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.musicality.channel.audio',
      androidNotificationChannelName: 'Musicality Playback',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'drawable/ic_notification',
    ),
  );
  runApp(const MusicalityApp());
}

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();
  final ConcatenatingAudioSource _playlistSource = ConcatenatingAudioSource(
    children: [],
  );

  bool _isSourceLoaded = false;
  bool _isPreparing = false;

  Timer? _listeningTimer;
  int _currentSongListeningSeconds = 0;
  bool _hasScoredCurrentSong = false;
  String? _lastSongId;

  MyAudioHandler() {
    _initPlayer();
    mediaItem.add(null);

    mediaItem.listen((item) {
      if (item != null && item.id != _lastSongId) {
        _lastSongId = item.id;
        _currentSongListeningSeconds = 0;
        _hasScoredCurrentSong = false;
      }
    });

    _listeningTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final playing = playbackState.value.playing;
      final currentItem = mediaItem.value;

      if (playing && currentItem != null) {
        _currentSongListeningSeconds++;

        final artist = currentItem.artist ?? 'Inconnu';

        final currentTimes = Map<String, int>.from(
          artistListeningTimeNotifier.value,
        );
        for (var a in _extractArtists(artist)) {
          currentTimes[a] = (currentTimes[a] ?? 0) + 1;
        }
        artistListeningTimeNotifier.value = currentTimes;

        final durationSecs = currentItem.duration?.inSeconds ?? 0;
        if (durationSecs > 0 && !_hasScoredCurrentSong) {
          if (_currentSongListeningSeconds >= (durationSecs * 0.90)) {
            _hasScoredCurrentSong = true;
            updateArtistScore(artist, 1);

            final currentPlayCounts = Map<String, int>.from(
              songPlayCountNotifier.value,
            );
            currentPlayCounts[currentItem.id] =
                (currentPlayCounts[currentItem.id] ?? 0) + 1;
            songPlayCountNotifier.value = currentPlayCounts;
          }
        }
      }
    });
  }

  Future<void> _manageCacheSize() async {
    if (!isCacheEnabledNotifier.value) return;
    final cacheDir = Directory('$_documentPath/cache');
    if (!cacheDir.existsSync()) return;

    int limitBytes = cacheLimitNotifier.value * 1024 * 1024;
    List<File> cachedFiles = cacheDir.listSync().whereType<File>().toList();

    if (cachedFiles.isEmpty) return;

    cachedFiles.sort(
      (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
    );
    int totalSize = cachedFiles.fold(
      0,
      (total, file) => total + file.lengthSync(),
    );

    final currentMediaItem = mediaItem.value;
    String currentSafeName = currentMediaItem != null
        ? currentMediaItem.id.split('/').last.replaceAll('.flac', '')
        : "";

    while (totalSize > limitBytes && cachedFiles.isNotEmpty) {
      File oldest = cachedFiles.first;
      if (oldest.path.contains(currentSafeName)) {
        cachedFiles.removeAt(0);
        if (cachedFiles.isNotEmpty) {
          oldest = cachedFiles.first;
        } else {
          break;
        }
      }
      try {
        totalSize -= oldest.lengthSync();
        oldest.deleteSync();
      } catch (e) {
        debugPrint("Erreur lors de la suppression du cache : $e");
      }
      if (cachedFiles.isNotEmpty) cachedFiles.removeAt(0);
    }
  }

  void _updatePlaylist(MediaItem newItem) {
    final idx = _playlist.indexWhere((e) => e.id == newItem.id);
    if (idx != -1) _playlist[idx] = newItem;
  }

  AudioSource _createSource(MediaItem item) {
    String safeName = item.id.split('/').last.replaceAll('.flac', '');
    File manualFlac = File('$_documentPath/$safeName.flac');
    File manualMp3 = File('$_documentPath/$safeName.mp3');

    File cacheFlac = File('$_documentPath/cache/$safeName.flac');
    File cacheMp3 = File('$_documentPath/cache/$safeName.mp3');

    bool wantFlac = isLosslessNotifier.value;
    bool hasFlac = item.extras?['hasFlac'] as bool? ?? true;
    if (wantFlac && !hasFlac) wantFlac = false;

    bool isFlac = false;
    String fileOrUrl = "";
    File? targetCacheFile;

    if (manualFlac.existsSync()) {
      isFlac = true;
      fileOrUrl = manualFlac.path;
    } else if (manualMp3.existsSync()) {
      isFlac = false;
      fileOrUrl = manualMp3.path;
    } else {
      if (wantFlac) {
        if (cacheMp3.existsSync()) {
          try {
            cacheMp3.deleteSync();
          } catch (e) {
            debugPrint("Erreur de suppression MP3 en cache : $e");
          }
        }
        isFlac = true;
        targetCacheFile = cacheFlac;
      } else {
        if (cacheFlac.existsSync()) {
          isFlac = true;
          targetCacheFile = cacheFlac;
        } else {
          isFlac = false;
          targetCacheFile = cacheMp3;
        }
      }
      fileOrUrl = isFlac ? item.id : item.id.replaceAll('.flac', '.mp3');
    }

    final newItem = item.copyWith(extras: {'isFlac': isFlac, 'hasFlac': hasFlac});
    _updatePlaylist(newItem);

    if (fileOrUrl.startsWith('/')) {
      return AudioSource.file(fileOrUrl, tag: newItem);
    } else {
      if (isCacheEnabledNotifier.value || targetCacheFile!.existsSync()) {
        _manageCacheSize();
        return LockCachingAudioSource(
          Uri.parse(fileOrUrl),
          cacheFile: targetCacheFile,
          tag: newItem,
        );
      } else {
        return AudioSource.uri(Uri.parse(fileOrUrl), tag: newItem);
      }
    }
  }

  Future<void> _replaceSourceSafe(int index, AudioSource newSource) async {
    final cIndex = _player.currentIndex;
    if (cIndex == index) return;
    try {
      await _playlistSource.removeAt(index);
      await _playlistSource.insert(index, newSource);
    } catch (e) {
      debugPrint("Erreur lors du remplacement de la source: $e");
    }
  }

  Future<void> playFromList(List<MediaItem> newQueue, int startIndex) async {
    _isPreparing = true;

    final List<AudioSource> newSources = [];
    for (var item in newQueue) {
      newSources.add(_createSource(item));
    }

    await _playlistSource.clear();
    await _playlistSource.addAll(newSources);
    queue.add(newQueue);

    if (startIndex >= 0 && startIndex < newQueue.length) {
      mediaItem.add(newQueue[startIndex]);
      await _player.seek(Duration.zero, index: startIndex);
      _player.play();
    }

    _isPreparing = false;
    _isSourceLoaded = true;
  }

  Future<void> reloadAudioSourcesForQuality() async {
    if (!_isSourceLoaded) return;
    final cIndex = _player.currentIndex;
    if (cIndex == null) return;

    List<MediaItem> currentQueue = List.from(queue.value);

    for (int i = 0; i < currentQueue.length; i++) {
      if (i == cIndex) continue;

      final oldItem = currentQueue[i];
      final oldIsFlac = oldItem.extras?['isFlac'] as bool? ?? false;

      final newSource = _createSource(oldItem);
      final masterIdx = _playlist.indexWhere((e) => e.id == oldItem.id);
      final newItem = masterIdx != -1 ? _playlist[masterIdx] : oldItem;

      final newIsFlac = newItem.extras?['isFlac'] as bool? ?? false;

      if (oldIsFlac != newIsFlac) {
        await _replaceSourceSafe(i, newSource);
        currentQueue[i] = newItem;
      }
    }
    queue.add(currentQueue);
  }

  Stream<LoopMode> get loopModeStream => _player.loopModeStream;
  Stream<bool> get shuffleModeEnabledStream => _player.shuffleModeEnabledStream;

  Future<void> toggleLoopMode() async {
    final isLooping = _player.loopMode == LoopMode.one;
    await _player.setLoopMode(isLooping ? LoopMode.all : LoopMode.one);
  }

  Future<void> toggleShuffleMode() async {
    final isShuffle = _player.shuffleModeEnabled;
    if (!isShuffle) {
      await _player.shuffle();
      await _player.setShuffleModeEnabled(true);
    } else {
      await _player.setShuffleModeEnabled(false);
    }
  }

  Future<void> _initPlayer() async {
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;

      AudioServiceRepeatMode systemRepeatMode = AudioServiceRepeatMode.none;
      if (_player.loopMode == LoopMode.one) {
        systemRepeatMode = AudioServiceRepeatMode.one;
      } else if (_player.loopMode == LoopMode.all) {
        systemRepeatMode = AudioServiceRepeatMode.all;
      }

      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.skipToNext,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.setRepeatMode,
            MediaAction.setShuffleMode,
          },
          androidCompactActionIndices: const [0, 1, 2],
          processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState]!,
          playing: playing,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
          queueIndex: event.currentIndex,
          repeatMode: systemRepeatMode,
          shuffleMode: _player.shuffleModeEnabled
              ? AudioServiceShuffleMode.all
              : AudioServiceShuffleMode.none,
        ),
      );
    });

    _player.currentIndexStream.listen((index) {
      if (index != null &&
          index >= 0 &&
          index < queue.value.length &&
          _isSourceLoaded &&
          !_isPreparing) {
        mediaItem.add(queue.value[index]);
      }
    });

    _player.durationStream.listen((duration) {
      if (duration != null && duration != Duration.zero) {
        final index = _player.currentIndex;
        if (index != null && index >= 0 && index < queue.value.length) {
          final currentQueue = List<MediaItem>.from(queue.value);
          final oldItem = currentQueue[index];

          if (oldItem.duration != duration) {
            final newItem = oldItem.copyWith(duration: duration);
            currentQueue[index] = newItem;
            queue.add(currentQueue);

            if (mediaItem.value?.id == newItem.id) {
              mediaItem.add(newItem);
            }

            final globalIndex = _playlist.indexWhere((e) => e.id == newItem.id);
            if (globalIndex != -1) {
              _playlist[globalIndex] = newItem;
            }
          }
        }
      }
    });

    List<AudioSource> initialList = [];
    List<MediaItem> initialQueue = [];

    for (var item in _playlist) {
      final source = _createSource(item);
      initialList.add(source);
      initialQueue.add(source.sequence.first.tag as MediaItem);
    }

    await _playlistSource.addAll(initialList);
    await _player.setAudioSource(_playlistSource);
    await _player.setLoopMode(LoopMode.all);
    queue.add(initialQueue);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        await _player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
        break;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        await _player.setLoopMode(LoopMode.all);
        break;
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode == AudioServiceShuffleMode.all) {
      await _player.shuffle();
      await _player.setShuffleModeEnabled(true);
    } else {
      await _player.setShuffleModeEnabled(false);
    }
  }

  Future<void> updateSourceAt(
    String id,
    AudioSource newSource,
    MediaItem newItem,
  ) async {
    final currentQueue = List<MediaItem>.from(queue.value);
    final index = currentQueue.indexWhere((e) => e.id == id);
    if (index >= 0) {
      currentQueue[index] = newItem;
      queue.add(currentQueue);
      if (_player.currentIndex == index) {
        mediaItem.add(newItem);
      }
      if (_isSourceLoaded) {
        await _replaceSourceSafe(index, newSource);
      }
    }
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> skipToNext() => _player.seekToNext();
  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> stop() async {
    await _player.stop();
    _listeningTimer?.cancel();
    return super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < queue.value.length) {
      _isPreparing = true;
      mediaItem.add(queue.value[index]);

      if (!_isSourceLoaded) {
        _isSourceLoaded = true;
      }

      await _player.seek(Duration.zero, index: index);
      _isPreparing = false;
      _player.play();
    }
  }
}

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
  PositionData(this.position, this.bufferedPosition, this.duration);
}

class SmoothIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;

  const SmoothIcon({
    super.key,
    required this.icon,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 410),
      curve: Curves.fastOutSlowIn,
      tween: Tween<double>(end: size),
      builder: (context, animatedSize, child) {
        return Icon(icon, color: color, size: animatedSize);
      },
    );
  }
}

class HyperOSButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double padding;

  const HyperOSButton({
    super.key,
    required this.child,
    required this.onTap,
    this.padding = 4.0,
  });

  @override
  State<HyperOSButton> createState() => _HyperOSButtonState();
}

class _HyperOSButtonState extends State<HyperOSButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      lowerBound: 0.85,
      upperBound: 1.0,
    )..value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _controller.animateTo(0.85, curve: Curves.easeInOut),
      onTapUp: (_) {
        _controller.animateTo(1.0, curve: Curves.easeInOut);
        widget.onTap();
      },
      onTapCancel: () => _controller.animateTo(1.0, curve: Curves.easeInOut),
      child: Padding(
        padding: EdgeInsets.all(widget.padding),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _controller.value,
              child: widget.child,
            );
          },
        ),
      ),
    );
  }
}

class HyperOSShuffleButton extends StatefulWidget {
  final bool isShuffle;
  final VoidCallback onTap;
  final List<Color> gradientColors;
  final double size;

  const HyperOSShuffleButton({
    super.key,
    required this.isShuffle,
    required this.onTap,
    required this.gradientColors,
    required this.size,
  });

  @override
  State<HyperOSShuffleButton> createState() => _HyperOSShuffleButtonState();
}

class _HyperOSShuffleButtonState extends State<HyperOSShuffleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      lowerBound: 0.85,
      upperBound: 1.0,
    )..value = 1.0;
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 410),
      curve: Curves.fastOutSlowIn,
      tween: Tween<double>(end: widget.size),
      builder: (context, animatedSize, child) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            _scaleController.animateTo(0.85, curve: Curves.easeInOut);
          },
          onTapUp: (_) {
            _scaleController.animateTo(1.0, curve: Curves.easeInOut);
            widget.onTap();
          },
          onTapCancel: () {
            _scaleController.animateTo(1.0, curve: Curves.easeInOut);
          },
          child: AnimatedBuilder(
            animation: _scaleController,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleController.value,
                child: child,
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: widget.isShuffle
                    ? ShaderMask(
                        key: const ValueKey('shuffle_active'),
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) {
                          return LinearGradient(
                            colors: widget.gradientColors,
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ).createShader(bounds);
                        },
                        child: Icon(CupertinoIcons.shuffle, size: animatedSize),
                      )
                    : Icon(
                        key: const ValueKey('shuffle_inactive'),
                        CupertinoIcons.shuffle,
                        color: Colors.white.withValues(alpha: 0.55),
                        size: animatedSize,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class HyperOSRepeatButton extends StatefulWidget {
  final bool isLooping;
  final VoidCallback onTap;
  final List<Color> gradientColors;
  final double size;

  const HyperOSRepeatButton({
    super.key,
    required this.isLooping,
    required this.onTap,
    required this.gradientColors,
    required this.size,
  });

  @override
  State<HyperOSRepeatButton> createState() => _HyperOSRepeatButtonState();
}

class _HyperOSRepeatButtonState extends State<HyperOSRepeatButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      lowerBound: 0.85,
      upperBound: 1.0,
    )..value = 1.0;
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 410),
      curve: Curves.fastOutSlowIn,
      tween: Tween<double>(end: widget.size),
      builder: (context, animatedSize, child) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            _scaleController.animateTo(0.85, curve: Curves.easeInOut);
          },
          onTapUp: (_) {
            _scaleController.animateTo(1.0, curve: Curves.easeInOut);
            widget.onTap();
          },
          onTapCancel: () {
            _scaleController.animateTo(1.0, curve: Curves.easeInOut);
          },
          child: AnimatedBuilder(
            animation: _scaleController,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleController.value,
                child: child,
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: widget.isLooping
                    ? ShaderMask(
                        key: const ValueKey('loop_active'),
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) {
                          return LinearGradient(
                            colors: widget.gradientColors,
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ).createShader(bounds);
                        },
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(CupertinoIcons.repeat, size: animatedSize),
                            Transform.translate(
                              offset: const Offset(0, 0),
                              child: Text(
                                '1',
                                style: TextStyle(
                                  fontSize: animatedSize * 0.25,
                                  fontWeight: FontWeight.w900,
                                  decoration: TextDecoration.none,
                                  color: Colors.white,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Icon(
                        key: const ValueKey('loop_inactive'),
                        CupertinoIcons.repeat,
                        color: Colors.white.withValues(alpha: 0.55),
                        size: animatedSize,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class HyperOSSlider extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Function(Duration) onSeek;
  final List<Color> gradientColors;

  const HyperOSSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.gradientColors,
  });

  @override
  State<HyperOSSlider> createState() => _HyperOSSliderState();
}

class _HyperOSSliderState extends State<HyperOSSlider> {
  double? _dragValue;
  double _baseMsForDrag = 0.0;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) {
      return n.toString().padLeft(2, "0");
    }

    return "${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    final double maxMs = widget.duration.inMilliseconds.toDouble() == 0.0
        ? 1.0
        : widget.duration.inMilliseconds.toDouble();
    final double currentMs = (_dragValue != null)
        ? _dragValue!
        : widget.position.inMilliseconds.toDouble();
    final double pct = (currentMs / maxMs).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox == null) return;
        final width = renderBox.size.width;
        if (width <= 0) return;
        final double tapX = details.localPosition.dx;
        final double newMs = (tapX / width) * maxMs;
        widget.onSeek(Duration(milliseconds: newMs.toInt()));
      },
      onHorizontalDragStart: (details) {
        _baseMsForDrag = widget.position.inMilliseconds.toDouble();
        setState(() {
          _dragValue = _baseMsForDrag;
        });
      },
      onHorizontalDragUpdate: (details) {
        final RenderBox? renderBox =
            context.findRenderObject() as RenderBox?;
        if (renderBox == null) return;

        final width = renderBox.size.width;
        if (width <= 0) return;

        final double deltaX = details.delta.dx;
        final double deltaMs = (deltaX / width) * maxMs;

        setState(() {
          if (_dragValue != null) {
            _dragValue = (_dragValue! + deltaMs).clamp(0.0, maxMs);
          }
        });
      },
      onHorizontalDragEnd: (details) async {
        if (_dragValue != null) {
          widget.onSeek(Duration(milliseconds: _dragValue!.toInt()));
          await Future.delayed(const Duration(milliseconds: 60));
          if (mounted) {
            setState(() {
              _dragValue = null;
            });
          }
        }
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final activeWidth = width * pct;
                return Stack(
                  alignment: Alignment.centerLeft,
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: width,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2C2C2C),
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                      ),
                    ),
                    if (activeWidth > 0)
                      Container(
                        width: activeWidth,
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: widget.gradientColors[0].withValues(
                                alpha: 0.8,
                              ),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: widget.gradientColors[0].withValues(
                                alpha: 0.5,
                              ),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    if (activeWidth > 0)
                      Container(
                        width: activeWidth,
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: LinearGradient(
                            colors: widget.gradientColors,
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    Positioned(
                      left: (activeWidth - 5).clamp(0.0, width - 10),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.8),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(Duration(milliseconds: currentMs.toInt())),
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
              Text(
                _formatDuration(widget.duration),
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RealAlbumBlurredBackground extends StatelessWidget {
  final MediaItem item;
  const RealAlbumBlurredBackground({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 35, sigmaY: 35),
          child: SizedBox.expand(child: getLocalOrNetworkImage(item)),
        ),
        Container(color: Colors.black.withValues(alpha: 0.15)),
      ],
    );
  }
}

class MusicalityLyricsView extends StatefulWidget {
  final List<LyricLine> lyrics;
  final Stream<PositionData> positionStream;

  const MusicalityLyricsView({
    super.key,
    required this.lyrics,
    required this.positionStream,
  });

  @override
  State<MusicalityLyricsView> createState() => _MusicalityLyricsViewState();
}

class _MusicalityLyricsViewState extends State<MusicalityLyricsView> {
  final ScrollController _scrollController = ScrollController();
  int _activeIndex = -1;
  StreamSubscription<PositionData>? _positionSubscription;
  List<GlobalKey> _lyricKeys = [];

  @override
  void initState() {
    super.initState();
    _generateKeys();
    _listenToPosition();
  }

  @override
  void didUpdateWidget(MusicalityLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _activeIndex = -1;
      _generateKeys();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    }
  }

  void _generateKeys() {
    _lyricKeys = List.generate(widget.lyrics.length, (index) => GlobalKey());
  }

  void _listenToPosition() {
    _positionSubscription = widget.positionStream.listen((data) {
      if (!mounted || widget.lyrics.isEmpty) {
        return;
      }

      final position = data.position;
      int newIndex = -1;

      int left = 0;
      int right = widget.lyrics.length - 1;

      while (left <= right) {
        int mid = left + (right - left) ~/ 2;
        if (position >= widget.lyrics[mid].time) {
          newIndex = mid;
          left = mid + 1;
        } else {
          right = mid - 1;
        }
      }

      if (newIndex != _activeIndex && newIndex >= 0) {
        setState(() {
          _activeIndex = newIndex;
        });
        _scrollToActiveIndex();
      }
    });
  }

  void _scrollToActiveIndex() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeIndex < 0 || _activeIndex >= _lyricKeys.length) {
        return;
      }

      final keyContext = _lyricKeys[_activeIndex].currentContext;
      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          alignment: 0.28,
          duration: const Duration(milliseconds: 550),
          curve: Curves.fastOutSlowIn,
        );
      }
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyrics.isEmpty) {
      return const SizedBox();
    }

    final screenHeight = MediaQuery.of(context).size.height;

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0.0, 0.15, 0.85, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(
          top: screenHeight * 0.22,
          bottom: screenHeight * 0.55,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(widget.lyrics.length, (index) {
            final line = widget.lyrics[index];
            final isActive = index == _activeIndex;

            return GestureDetector(
              key: _lyricKeys[index],
              behavior: HitTestBehavior.opaque,
              onTap: () => _audioHandler.seek(line.time),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 16,
                ),
                child: AnimatedScale(
                  scale: isActive ? 1.0 : 0.85,
                  duration: const Duration(milliseconds: 320),
                  alignment: Alignment.centerLeft,
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 320),
                    opacity: isActive ? 1.0 : 0.25,
                    child: Text(
                      line.text,
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        height: 1.35,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class MusicalityApp extends StatelessWidget {
  const MusicalityApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Musicality',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const HomeScreen(),
    );
  }
}

class CustomSearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;
  final String hintText;
  final FocusNode? focusNode;

  const CustomSearchBar({
    super.key,
    required this.onChanged,
    required this.hintText,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 12),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.search, color: Colors.white70, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                focusNode: focusNode,
                textInputAction: TextInputAction.search,
                onChanged: onChanged,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                cursorColor: Colors.white70,
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 16,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddSongsSheet extends StatefulWidget {
  final String playlistName;
  final List<Color> activeThemeColors;

  const AddSongsSheet({
    super.key,
    required this.playlistName,
    required this.activeThemeColors,
  });

  @override
  State<AddSongsSheet> createState() => _AddSongsSheetState();
}

class _AddSongsSheetState extends State<AddSongsSheet> {
  String _searchQuery = '';
  final FocusNode _searchFocusNode = FocusNode();
  final DraggableScrollableController _dragController =
      DraggableScrollableController();
  final ValueNotifier<double> _sheetSize = ValueNotifier(0.85);
  List<MediaItem> _filteredPlaylist = [];

  @override
  void initState() {
    super.initState();
    _updateFilter();
    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus) {
        _dragController.animateTo(
          1.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.fastOutSlowIn,
        );
      }
    });

    _dragController.addListener(() {
      if (_dragController.isAttached) {
        _sheetSize.value = _dragController.size;
      }
    });
  }

  void _updateFilter() {
    _filteredPlaylist = _playlist.where((item) {
      final query = _normalizeString(_searchQuery);
      final titleMatch = _normalizeString(item.title).contains(query);
      final artistMatch = _normalizeString(item.artist ?? '').contains(query);
      return titleMatch || artistMatch;
    }).toList();
    _filteredPlaylist.sort(
      (a, b) => _normalizeString(a.title).compareTo(_normalizeString(b.title)),
    );
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _dragController.dispose();
    _sheetSize.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: DraggableScrollableSheet(
        controller: _dragController,
        initialChildSize: 0.85,
        minChildSize: 0.0,
        maxChildSize: 1.0,
        expand: false,
        snap: true,
        snapSizes: const [0.85, 1.0],
        builder: (context, scrollController) {
          final topPadding = MediaQuery.of(context).padding.top;

          return ValueListenableBuilder<double>(
            valueListenable: _sheetSize,
            builder: (context, size, child) {
              final progress = ((size - 0.90) / 0.10).clamp(0.0, 1.0);
              final radius = 32.0 * (1.0 - progress);
              final borderAlpha = 0.1 * (1.0 - progress);

              return ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(radius),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF121212).withValues(alpha: 0.35),
                        border: borderAlpha > 0
                            ? Border(
                                top: BorderSide(
                                  color: Colors.white.withValues(
                                    alpha: borderAlpha,
                                  ),
                                  width: 1,
                                ),
                              )
                            : null,
                      ),
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: CustomScrollView(
                controller: scrollController,
                physics: const BouncingScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        SizedBox(height: topPadding),
                        ValueListenableBuilder<double>(
                          valueListenable: _sheetSize,
                          builder: (context, size, child) {
                            final opacity = (1.0 - ((size - 0.90) / 0.10))
                                .clamp(0.0, 1.0);
                            return Opacity(opacity: opacity, child: child);
                          },
                          child: Center(
                            child: Container(
                              margin: const EdgeInsets.only(top: 12, bottom: 8),
                              width: 40,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.only(
                            top: 25,
                            left: 16,
                            right: 16,
                            bottom: 10,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Ajouter des titres",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                                child: ShaderMask(
                                  blendMode: BlendMode.srcIn,
                                  shaderCallback: (bounds) {
                                    return LinearGradient(
                                      colors: widget.activeThemeColors,
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ).createShader(
                                      Rect.fromLTWH(
                                        0,
                                        0,
                                        bounds.width,
                                        bounds.height,
                                      ),
                                    );
                                  },
                                  child: const Text(
                                    "Terminé",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        CustomSearchBar(
                          hintText: "Rechercher...",
                          focusNode: _searchFocusNode,
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                              _updateFilter();
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final item = _filteredPlaylist[index];

                      return ValueListenableBuilder<Map<String, Set<String>>>(
                        valueListenable: playlistContentsNotifier,
                        builder: (context, contents, _) {
                          final inPlaylist =
                              (contents[widget.playlistName] ?? <String>{})
                                  .contains(item.id);

                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: getLocalOrNetworkImage(
                                item,
                                width: 45,
                                height: 45,
                              ),
                            ),
                            title: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                AnimatedOpacity(
                                  duration: const Duration(milliseconds: 300),
                                  opacity: inPlaylist ? 0.0 : 1.0,
                                  child: Text(
                                    item.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                AnimatedOpacity(
                                  duration: const Duration(milliseconds: 300),
                                  opacity: inPlaylist ? 1.0 : 0.0,
                                  child: ShaderMask(
                                    blendMode: BlendMode.srcIn,
                                    shaderCallback: (bounds) {
                                      return LinearGradient(
                                        colors: widget.activeThemeColors,
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ).createShader(
                                        Rect.fromLTWH(
                                          0,
                                          0,
                                          bounds.width,
                                          bounds.height,
                                        ),
                                      );
                                    },
                                    child: Text(
                                      item.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 300),
                              style: TextStyle(
                                color: inPlaylist
                                    ? Color.lerp(
                                        const Color(0xFFCCCCCC),
                                        widget.activeThemeColors[0],
                                        0.35,
                                      )
                                    : Colors.white54,
                                fontSize: 14,
                              ),
                              child: Text(_formatArtist(item.artist)),
                            ),
                            trailing: IconButton(
                              icon: TweenAnimationBuilder<double>(
                                tween: Tween<double>(
                                  begin: 0.0,
                                  end: inPlaylist ? 1.0 : 0.0,
                                ),
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                                builder: (context, value, child) {
                                  return Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Opacity(
                                        opacity: 1.0 - value,
                                        child: Transform.rotate(
                                          angle: value * -0.5,
                                          child: const Icon(
                                            CupertinoIcons.add_circled,
                                            color: Colors.white54,
                                            size: 28,
                                          ),
                                        ),
                                      ),
                                      Opacity(
                                        opacity: value,
                                        child: Transform.scale(
                                          scale: 0.5 + (0.5 * value),
                                          child: ShaderMask(
                                            blendMode: BlendMode.srcIn,
                                            shaderCallback: (bounds) {
                                              return LinearGradient(
                                                colors:
                                                    widget.activeThemeColors,
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ).createShader(
                                                Rect.fromLTWH(
                                                  0,
                                                  0,
                                                  bounds.width,
                                                  bounds.height,
                                                ),
                                              );
                                            },
                                            child: const Icon(
                                              CupertinoIcons
                                                  .checkmark_circle_fill,
                                              color: Colors.white,
                                              size: 28,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              onPressed: () {
                                final currentContents =
                                    Map<String, Set<String>>.from(
                                      playlistContentsNotifier.value,
                                    );
                                final currentSet = Set<String>.from(
                                  currentContents[widget.playlistName] ??
                                      <String>{},
                                );

                                if (inPlaylist) {
                                  currentSet.remove(item.id);
                                } else {
                                  currentSet.add(item.id);
                                }

                                currentContents[widget.playlistName] =
                                    currentSet;
                                playlistContentsNotifier.value =
                                    currentContents;
                              },
                            ),
                          );
                        },
                      );
                    }, childCount: _filteredPlaylist.length),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class ExplorerSheet extends StatefulWidget {
  final String title;
  final List<Color> themeColors;
  final Widget content;

  const ExplorerSheet({
    super.key,
    required this.title,
    required this.themeColors,
    required this.content,
  });

  @override
  State<ExplorerSheet> createState() => _ExplorerSheetState();
}

class _ExplorerSheetState extends State<ExplorerSheet> {
  final DraggableScrollableController _dragController =
      DraggableScrollableController();
  final ValueNotifier<double> _sheetSize = ValueNotifier(0.85);
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _dragController.addListener(() {
      if (_dragController.isAttached) {
        _sheetSize.value = _dragController.size;
      }
    });
  }

  @override
  void dispose() {
    _dragController.dispose();
    _sheetSize.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _dragController,
      initialChildSize: 0.85,
      minChildSize: 0.0,
      maxChildSize: 1.0,
      expand: false,
      snap: true,
      snapSizes: const [0.85, 1.0],
      builder: (context, scrollController) {
        final topPadding = MediaQuery.of(context).padding.top;
        final headerHeight = 115.0 + topPadding;

        return ValueListenableBuilder<double>(
          valueListenable: _sheetSize,
          builder: (context, size, child) {
            final progress = ((size - 0.90) / 0.10).clamp(0.0, 1.0);
            final radius = 32.0 * (1.0 - progress);
            final borderAlpha = 0.1 * (1.0 - progress);

            return ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF121212).withValues(alpha: 0.35),
                      border: borderAlpha > 0
                          ? Border(
                              top: BorderSide(
                                color: Colors.white.withValues(
                                  alpha: borderAlpha,
                                ),
                                width: 1,
                              ),
                            )
                          : null,
                    ),
                    child: child,
                  ),
                ),
              ),
            );
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification notification) {
              if (notification.metrics.axis == Axis.vertical) {
                _scrollOffset.value = notification.metrics.pixels;
              }
              return false;
            },
            child: Stack(
              children: [
                ListView(
                  controller: scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(
                    top: headerHeight,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 100,
                  ),
                  children: [widget.content],
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: headerHeight,
                  child: IgnorePointer(
                    child: Stack(
                      children: [
                        ValueListenableBuilder<double>(
                          valueListenable: _scrollOffset,
                          builder: (context, offset, child) {
                            final opacity = (offset / 25.0).clamp(0.0, 1.0);
                            return Opacity(opacity: opacity, child: child);
                          },
                          child: ClipRect(
                            child: ShaderMask(
                              shaderCallback: (bounds) {
                                return const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black,
                                    Colors.black,
                                    Colors.transparent,
                                  ],
                                  stops: [0.0, 0.70, 1.0],
                                ).createShader(
                                  Rect.fromLTWH(
                                    0,
                                    0,
                                    bounds.width,
                                    bounds.height,
                                  ),
                                );
                              },
                              blendMode: BlendMode.dstIn,
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 35,
                                  sigmaY: 35,
                                ),
                                child: Container(
                                  height: headerHeight,
                                  color: Colors.black.withValues(alpha: 0.98),
                                ),
                              ),
                            ),
                          ),
                        ),
                        RepaintBoundary(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: topPadding),
                              ValueListenableBuilder<double>(
                                valueListenable: _sheetSize,
                                builder: (context, size, child) {
                                  final opacity = (1.0 - ((size - 0.90) / 0.10))
                                      .clamp(0.0, 1.0);
                                  return Opacity(
                                    opacity: opacity,
                                    child: child,
                                  );
                                },
                                child: Center(
                                  child: Container(
                                    margin: const EdgeInsets.only(
                                      top: 12,
                                      bottom: 8,
                                    ),
                                    width: 40,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.3,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 15,
                                  left: 20,
                                  right: 20,
                                ),
                                child: ShaderMask(
                                  blendMode: BlendMode.srcIn,
                                  shaderCallback: (bounds) =>
                                      LinearGradient(
                                        colors: widget.themeColors,
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ).createShader(
                                        Rect.fromLTWH(
                                          0,
                                          0,
                                          bounds.width,
                                          bounds.height,
                                        ),
                                      ),
                                  child: Text(
                                    widget.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SongOptionsOverlay extends StatefulWidget {
  final MediaItem item;
  final List<Color> activeThemeColors;
  final String heroTag;

  const SongOptionsOverlay({
    super.key,
    required this.item,
    required this.activeThemeColors,
    required this.heroTag,
  });

  @override
  State<SongOptionsOverlay> createState() => _SongOptionsOverlayState();
}

class _SongOptionsOverlayState extends State<SongOptionsOverlay> {
  bool _showCreatePlaylist = false;
  String _newPlaylistName = '';
  String? _newPlaylistImage;
  final FocusNode _playlistFocusNode = FocusNode();

  @override
  void dispose() {
    _playlistFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                if (_showCreatePlaylist) {
                  _playlistFocusNode.unfocus();
                  setState(() {
                    _showCreatePlaylist = false;
                  });
                } else {
                  Navigator.pop(context);
                }
              },
              child: Container(color: Colors.transparent),
            ),
          ),

          IgnorePointer(
            ignoring: _showCreatePlaylist,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _showCreatePlaylist ? 0.0 : 1.0,
              child: _buildOptions(),
            ),
          ),

          IgnorePointer(
            ignoring: !_showCreatePlaylist,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _showCreatePlaylist ? 1.0 : 0.0,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 300),
                scale: _showCreatePlaylist ? 1.0 : 0.9,
                curve: Curves.easeOutCubic,
                child: _buildCreatePlaylist(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptions() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            height: 220,
            child: Hero(
              tag: widget.heroTag,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: widget.activeThemeColors[0].withValues(alpha: 0.4),
                      blurRadius: 50,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: getLocalOrNetworkImage(widget.item),
                ),
              ),
            ),
          ),

          AnimatedBuilder(
            animation: ModalRoute.of(context)!.animation!,
            builder: (context, child) {
              final animation = ModalRoute.of(context)!.animation!;
              return Opacity(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0.0, 1.0, curve: Curves.easeOut),
                  reverseCurve: const Interval(0.5, 1.0, curve: Curves.easeIn),
                ).value,
                child: child,
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 24),
                Text(
                  widget.item.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatArtist(widget.item.artist),
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.7),
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 40),

                const Text(
                  "AJOUTER À UNE PLAYLIST",
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 12),

                ValueListenableBuilder<List<String>>(
                  valueListenable: customPlaylistsNotifier,
                  builder: (context, playlists, child) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (playlists.isNotEmpty)
                          Container(
                            width: MediaQuery.of(context).size.width * 0.75,
                            constraints: const BoxConstraints(maxHeight: 250),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Material(
                              type: MaterialType.transparency,
                              child: ListView.builder(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: playlists.length,
                                itemBuilder: (context, index) {
                                  final pName = playlists[index];
                                  return ValueListenableBuilder<
                                    Map<String, Set<String>>
                                  >(
                                    valueListenable: playlistContentsNotifier,
                                    builder: (context, contents, _) {
                                      final inPlaylist =
                                          (contents[pName] ?? <String>{})
                                              .contains(widget.item.id);
                                      return ListTile(
                                        leading: const Icon(
                                          CupertinoIcons.music_albums_fill,
                                          color: Colors.white70,
                                        ),
                                        title: AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          layoutBuilder:
                                              (currentChild, previousChildren) {
                                                return Stack(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  children: [
                                                    ...previousChildren,
                                                    currentChild ??
                                                        const SizedBox.shrink(),
                                                  ],
                                                );
                                              },
                                          child: inPlaylist
                                              ? ShaderMask(
                                                  key: const ValueKey('in'),
                                                  blendMode: BlendMode.srcIn,
                                                  shaderCallback: (bounds) {
                                                    return LinearGradient(
                                                      colors: widget
                                                          .activeThemeColors,
                                                      begin:
                                                          Alignment.centerLeft,
                                                      end:
                                                          Alignment.centerRight,
                                                    ).createShader(
                                                      Rect.fromLTWH(
                                                        0,
                                                        0,
                                                        bounds.width,
                                                        bounds.height,
                                                      ),
                                                    );
                                                  },
                                                  child: Text(
                                                    pName,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                )
                                              : Text(
                                                  pName,
                                                  key: const ValueKey('out'),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                        ),
                                        trailing: inPlaylist
                                            ? ShaderMask(
                                                blendMode: BlendMode.srcIn,
                                                shaderCallback: (bounds) {
                                                  return LinearGradient(
                                                    colors: widget
                                                        .activeThemeColors,
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ).createShader(
                                                    Rect.fromLTWH(
                                                      0,
                                                      0,
                                                      bounds.width,
                                                      bounds.height,
                                                    ),
                                                  );
                                                },
                                                child: const Icon(
                                                  CupertinoIcons.checkmark_alt,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : null,
                                        onTap: () {
                                          final currentContents =
                                              Map<String, Set<String>>.from(
                                                playlistContentsNotifier.value,
                                              );
                                          final currentSet = Set<String>.from(
                                            currentContents[pName] ??
                                                <String>{},
                                          );

                                          if (currentSet.contains(
                                            widget.item.id,
                                          )) {
                                            currentSet.remove(widget.item.id);
                                          } else {
                                            currentSet.add(widget.item.id);
                                          }

                                          currentContents[pName] = currentSet;
                                          playlistContentsNotifier.value =
                                              currentContents;
                                          Navigator.pop(context);
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),

                        const SizedBox(height: 16),

                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            setState(() {
                              _showCreatePlaylist = true;
                            });
                            _playlistFocusNode.requestFocus();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(CupertinoIcons.add, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  "Nouvelle playlist",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatePlaylist() {
    final hasValidImage =
        _newPlaylistImage != null &&
        _newPlaylistImage!.isNotEmpty &&
        File(_newPlaylistImage!).existsSync();

    return Align(
      alignment: const Alignment(0.0, -0.4),
      child: Material(
        type: MaterialType.transparency,
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
                        colors: widget.activeThemeColors,
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ).createShader(
                        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                      );
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

                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final picker = ImagePicker();
                          final xfile = await picker.pickImage(
                            source: ImageSource.gallery,
                          );
                          if (xfile != null) {
                            setState(() {
                              _newPlaylistImage = xfile.path;
                            });
                          }
                        },
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: hasValidImage
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.file(
                                    File(_newPlaylistImage!),
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
                              setState(() {
                                _newPlaylistImage = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: widget.activeThemeColors,
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
                  ),

                  const SizedBox(height: 20),
                  ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) {
                      return LinearGradient(
                        colors: widget.activeThemeColors,
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
                          selectionHandleColor: widget.activeThemeColors[0],
                          selectionColor: widget.activeThemeColors[0]
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: TextField(
                        focusNode: _playlistFocusNode,
                        onChanged: (val) {
                          _newPlaylistName = val;
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
                            _playlistFocusNode.unfocus();
                            setState(() {
                              _showCreatePlaylist = false;
                            });
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
                              colors: widget.activeThemeColors,
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            onPressed: () {
                              _playlistFocusNode.unfocus();

                              if (_newPlaylistName.trim().isNotEmpty) {
                                final pName = _newPlaylistName.trim();

                                if (!customPlaylistsNotifier.value.contains(
                                  pName,
                                )) {
                                  final currentList = List<String>.from(
                                    customPlaylistsNotifier.value,
                                  );
                                  currentList.add(pName);
                                  customPlaylistsNotifier.value = currentList;
                                }

                                final currentContents =
                                    Map<String, Set<String>>.from(
                                      playlistContentsNotifier.value,
                                    );
                                final currentSet = Set<String>.from(
                                  currentContents[pName] ?? <String>{},
                                );
                                currentSet.add(widget.item.id);
                                currentContents[pName] = currentSet;
                                playlistContentsNotifier.value =
                                    currentContents;

                                if (_newPlaylistImage != null &&
                                    _newPlaylistImage!.isNotEmpty) {
                                  final currentImages =
                                      Map<String, String>.from(
                                        playlistImagesNotifier.value,
                                      );
                                  currentImages[pName] = _newPlaylistImage!;
                                  playlistImagesNotifier.value = currentImages;
                                }
                              }

                              setState(() {
                                _showCreatePlaylist = false;
                              });
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
    );
  }
}

// ----------------------------------------------------
// MENU COMPTE (ACCOUNT PAGE) - TRANSFORMÉ EN STATEFUL
// ----------------------------------------------------
class AccountPageView extends StatefulWidget {
  final List<Color> dynamicGradientColors;

  const AccountPageView({super.key, required this.dynamicGradientColors});

  @override
  State<AccountPageView> createState() => _AccountPageViewState();
}

class _AccountPageViewState extends State<AccountPageView> {
  int _cacheSizeBytes = 0;

  @override
  void initState() {
    super.initState();
    _calculateCacheSize();
  }

  void _calculateCacheSize() {
    final cacheDir = Directory('$_documentPath/cache');
    int totalSize = 0;
    if (cacheDir.existsSync()) {
      for (var file in cacheDir.listSync().whereType<File>()) {
        totalSize += file.lengthSync();
      }
    }
    if (mounted) {
      setState(() {
        _cacheSizeBytes = totalSize;
      });
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: isError
            ? const Color(0xFFFF5252)
            : const Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _showAuthDialog(bool isLogin) async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Fermer",
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: const Alignment(0.0, -0.4),
          child: Material(
            type: MaterialType.transparency,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isLogin ? "Connexion" : "Créer un compte",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: emailController,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: "Email",
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        style: const TextStyle(color: Colors.white),
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: "Mot de passe",
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text(
                                "Annuler",
                                style: TextStyle(color: Colors.white54),
                              ),
                            ),
                          ),
                          Expanded(
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              color: widget.dynamicGradientColors[0],
                              onPressed: () async {
                                final email = emailController.text.trim();
                                final password = passwordController.text.trim();
                                if (email.isEmpty || password.isEmpty) return;

                                try {
                                  if (isLogin) {
                                    await FirebaseAuth.instance
                                        .signInWithEmailAndPassword(
                                          email: email,
                                          password: password,
                                        );
                                    await performCloudRestore();
                                    if (!mounted) return;
                                    _showSnackBar(
                                      "Connexion et restauration réussies !",
                                    );
                                  } else {
                                    await FirebaseAuth.instance
                                        .createUserWithEmailAndPassword(
                                          email: email,
                                          password: password,
                                        );
                                    performCloudBackup();
                                    if (!mounted) return;
                                    _showSnackBar("Compte créé avec succès !");
                                  }
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                } on FirebaseAuthException catch (e) {
                                  if (!mounted) return;
                                  _showSnackBar(
                                    e.message ?? "Erreur d'authentification",
                                    isError: true,
                                  );
                                }
                              },
                              child: Text(
                                isLogin ? "Se connecter" : "S'inscrire",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // --- LE BOUTON GOOGLE PARFAIT ET DÉFINITIF ---
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton(
                          color: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          onPressed: () async {
                            try {
                              final googleSignIn = GoogleSignIn.instance;
                              await googleSignIn.initialize(
                                serverClientId:
                                    '154016653293-0f6vgsqeacs4kneqr0bsfplropbb2gvs.apps.googleusercontent.com',
                              );

                              final googleAccount = await googleSignIn
                                  .authenticate();
                              final authClient = googleAccount.authentication;

                              final credential = GoogleAuthProvider.credential(
                                idToken: authClient.idToken,
                              );

                              await FirebaseAuth.instance.signInWithCredential(
                                credential,
                              );
                              await performCloudRestore();

                              if (!mounted) return;
                              _showSnackBar("Connexion Google réussie !");

                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            } catch (e) {
                              if (!mounted) return;

                              // Si l'utilisateur annule, on ignore silencieusement
                              if (e is GoogleSignInException &&
                                  e.code ==
                                      GoogleSignInExceptionCode.canceled) {
                                return;
                              }

                              _showSnackBar(
                                "Erreur Google : $e",
                                isError: true,
                              );
                            }
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Le VRAI logo officiel de Google (géométrie et couleurs parfaites)
                              Image.network(
                                'https://yt3.googleusercontent.com/bAseQlKvNmjdLQrvYWm_q3QDp8C8YKyYI-nYJewgOkPi0JU1_3X9oFgjrEdzkOlXzLGFxFbnsw=s900-c-k-c0x00ffffff-no-rj',
                                height: 28,
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                "Continuer avec Google",
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 20),
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) {
                  return LinearGradient(
                    colors: widget.dynamicGradientColors,
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ).createShader(bounds);
                },
                child: const Text(
                  "Mon Compte",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),

          // --- AVATAR DYNAMIQUE EN TEMPS RÉEL ---
          StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, authSnapshot) {
              final user = authSnapshot.data;

              return ValueListenableBuilder<String?>(
                valueListenable: userProfileImageNotifier,
                builder: (context, imagePath, child) {
                  // 1. On récupère les infos
                  final hasGoogleImage = user != null && user.photoURL != null;
                  final hasLocalImage =
                      imagePath != null &&
                      imagePath.isNotEmpty &&
                      File(imagePath).existsSync();

                  // 2. Priorité: Locale > Google > Défaut
                  Widget avatarWidget;
                  if (hasLocalImage) {
                    avatarWidget = Image.file(
                      File(imagePath),
                      fit: BoxFit.cover,
                    );
                  } else if (hasGoogleImage) {
                    avatarWidget = Image.network(
                      user.photoURL!,
                      fit: BoxFit.cover,
                    );
                  } else {
                    avatarWidget = const Icon(
                      CupertinoIcons.person_fill,
                      color: Colors.white54,
                      size: 60,
                    );
                  }

                  return GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final xfile = await picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      if (xfile != null) {
                        userProfileImageNotifier.value = xfile.path;
                      }
                    },
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.1),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: widget.dynamicGradientColors[0]
                                    .withValues(alpha: 0.3),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: ClipOval(child: avatarWidget),
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: widget.dynamicGradientColors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Icon(
                            CupertinoIcons.camera_fill,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),

          const SizedBox(height: 16),

          // --- SECTION FIREBASE : AUTHENTIFICATION ---
          StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              final user = snapshot.data;
              final isLoggedIn = user != null;

              return Column(
                children: [
                  Text(
                    isLoggedIn
                        ? (user.email ?? "Utilisateur Connecté")
                        : "Utilisateur Local",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      isLoggedIn
                          ? "Synchronisation Cloud Activée"
                          : "Données stockées uniquement sur cet appareil",
                      textAlign:
                          TextAlign.center, // ALIGNEMENT PARFAITEMENT CENTRÉ
                      style: TextStyle(
                        color: isLoggedIn
                            ? widget.dynamicGradientColors[0]
                            : Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: isLoggedIn
                          ? CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 24,
                              ),
                              color: Colors.white.withValues(alpha: 0.1),
                              onPressed: () => FirebaseAuth.instance.signOut(),
                              child: const Text(
                                "Se déconnecter",
                                style: TextStyle(
                                  color: Color(0xFFFF5252),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: CupertinoButton(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    color: Colors.white.withValues(alpha: 0.1),
                                    onPressed: () => _showAuthDialog(false),
                                    child: const Text(
                                      "Créer un compte",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: CupertinoButton(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    color: widget.dynamicGradientColors[0],
                                    onPressed: () => _showAuthDialog(true),
                                    child: const Text(
                                      "Connexion",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 30),

          // --- LE RESTE DES PARAMÈTRES (INTACT) ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: const Text(
                "Paramètres",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          Container(
            margin: const EdgeInsets.only(left: 16, right: 16, top: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              CupertinoIcons.waveform,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  "Qualité sonore",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "La qualité s'appliquera au changement de musique.",
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ValueListenableBuilder<bool>(
                        valueListenable: isLosslessNotifier,
                        builder: (context, isLossless, _) {
                          return Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                            ),
                            child: CupertinoSlidingSegmentedControl<bool>(
                              backgroundColor: Colors.transparent,
                              thumbColor: Colors.white.withValues(alpha: 0.2),
                              groupValue: isLossless,
                              onValueChanged: (bool? value) {
                                if (value != null) {
                                  isLosslessNotifier.value = value;
                                }
                              },
                              children: {
                                false: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    "Normale (MP3)",
                                    style: TextStyle(
                                      color: !isLossless
                                          ? Colors.white
                                          : Colors.white54,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                true: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    "Lossless (FLAC)",
                                    style: TextStyle(
                                      color: isLossless
                                          ? Colors.white
                                          : Colors.white54,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              },
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 30),

                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              CupertinoIcons.cloud_download,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  "Préférence de téléchargement",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "Format utilisé lors de l'enregistrement hors-ligne.",
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ValueListenableBuilder<bool>(
                        valueListenable: isDownloadLosslessNotifier,
                        builder: (context, isDownloadLossless, _) {
                          return Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                            ),
                            child: CupertinoSlidingSegmentedControl<bool>(
                              backgroundColor: Colors.transparent,
                              thumbColor: Colors.white.withValues(alpha: 0.2),
                              groupValue: isDownloadLossless,
                              onValueChanged: (bool? value) {
                                if (value != null) {
                                  isDownloadLosslessNotifier.value = value;
                                }
                              },
                              children: {
                                false: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    "MP3",
                                    style: TextStyle(
                                      color: !isDownloadLossless
                                          ? Colors.white
                                          : Colors.white54,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                true: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    "Lossless (FLAC)",
                                    style: TextStyle(
                                      color: isDownloadLossless
                                          ? Colors.white
                                          : Colors.white54,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              },
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 30),

                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              CupertinoIcons.archivebox,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  "Mise en cache",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "Conserver temporairement les musiques lues.",
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: isCacheEnabledNotifier,
                            builder: (context, isCacheEnabled, _) {
                              return CupertinoSwitch(
                                value: isCacheEnabled,
                                activeTrackColor:
                                    widget.dynamicGradientColors[0],
                                onChanged: (val) {
                                  isCacheEnabledNotifier.value = val;
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: isCacheEnabledNotifier,
                        builder: (context, isCacheEnabled, _) {
                          if (!isCacheEnabled) return const SizedBox();
                          return Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: Column(
                              children: [
                                ValueListenableBuilder<int>(
                                  valueListenable: cacheLimitNotifier,
                                  builder: (context, cacheLimit, _) {
                                    return Container(
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.4,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.05,
                                          ),
                                        ),
                                      ),
                                      child:
                                          CupertinoSlidingSegmentedControl<int>(
                                            backgroundColor: Colors.transparent,
                                            thumbColor: Colors.white.withValues(
                                              alpha: 0.2,
                                            ),
                                            groupValue: cacheLimit,
                                            onValueChanged: (int? value) {
                                              if (value != null) {
                                                cacheLimitNotifier.value =
                                                    value;
                                              }
                                            },
                                            children: {
                                              50: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 12,
                                                    ),
                                                child: Text(
                                                  "50 Mo",
                                                  style: TextStyle(
                                                    color: cacheLimit == 50
                                                        ? Colors.white
                                                        : Colors.white54,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              100: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 12,
                                                    ),
                                                child: Text(
                                                  "100 Mo",
                                                  style: TextStyle(
                                                    color: cacheLimit == 100
                                                        ? Colors.white
                                                        : Colors.white54,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              500: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 12,
                                                    ),
                                                child: Text(
                                                  "500 Mo",
                                                  style: TextStyle(
                                                    color: cacheLimit == 500
                                                        ? Colors.white
                                                        : Colors.white54,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              1024: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 12,
                                                    ),
                                                child: Text(
                                                  "1 Go",
                                                  style: TextStyle(
                                                    color: cacheLimit == 1024
                                                        ? Colors.white
                                                        : Colors.white54,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            },
                                          ),
                                    );
                                  },
                                ),
                                if (_cacheSizeBytes > 0) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.05,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                      ),
                                    ),
                                    child: CupertinoButton(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      onPressed: () {
                                        final cacheDir = Directory(
                                          '$_documentPath/cache',
                                        );
                                        if (cacheDir.existsSync()) {
                                          final files = cacheDir
                                              .listSync()
                                              .whereType<File>();
                                          for (var file in files) {
                                            try {
                                              file.deleteSync();
                                            } catch (e) {
                                              debugPrint(
                                                "Erreur suppression fichier cache : $e",
                                              );
                                            }
                                          }
                                          _calculateCacheSize();
                                        }
                                      },
                                      child: Text(
                                        "Vider le cache (${(_cacheSizeBytes / (1024 * 1024)).toStringAsFixed(1)} Mo)",
                                        style: const TextStyle(
                                          color: Color(0xFFFF5252),
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 220),
        ],
      ),
    );
  }
}

// ----------------------------------------------------
// HOMESCREEN & NAVIGATION
// ----------------------------------------------------

class SongTile extends StatelessWidget {
  final MediaItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final List<Color> activeThemeColors;
  final String heroTag;
  final VoidCallback? onRemoveFromHistory;
  final bool showPlayCount;

  const SongTile({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.activeThemeColors,
    required this.heroTag,
    this.onRemoveFromHistory,
    this.showPlayCount = false,
  });

  void _showSongOptions(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (context, animation, secondaryAnimation) {
          return SongOptionsOverlay(
            item: item,
            activeThemeColors: activeThemeColors,
            heroTag: heroTag,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return Stack(
            children: [
              FadeTransition(
                opacity: animation,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(color: Colors.black.withValues(alpha: 0.6)),
                ),
              ),
              child,
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trackColors = _getAlbumGradientColors(item.album ?? '');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          horizontalTitleGap: 8,
          minLeadingWidth: 45,
          contentPadding: const EdgeInsets.only(left: 12, right: 0),
          leading: SizedBox(
            width: 45,
            height: 45,
            child: Hero(
              tag: heroTag,
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: activeThemeColors[0].withValues(alpha: 0.0),
                        blurRadius: 0,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: getLocalOrNetworkImage(item),
                  ),
                ),
              ),
            ),
          ),
          title: isSelected
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) {
                          return LinearGradient(
                            colors: [trackColors[0], trackColors[1]],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ).createShader(
                            Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                          );
                        },
                        child: MarqueeWidget(
                          resetKey: 'sel_${item.id}',
                          child: Text(
                            item.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : MarqueeWidget(
                  resetKey: 'unsel_${item.id}',
                  child: Text(
                    item.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
          subtitle: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _formatArtist(item.artist),
                  style: TextStyle(
                    color: isSelected
                        ? Color.lerp(
                            const Color(0xFFCCCCCC),
                            trackColors[0],
                            0.35,
                          )
                        : const Color(0xFF9E9E9E),
                    fontSize: 14,
                    height: 1.0,
                    fontWeight: isSelected
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showPlayCount)
                ValueListenableBuilder<Map<String, int>>(
                  valueListenable: songPlayCountNotifier,
                  builder: (context, playCounts, child) {
                    final count = playCounts[item.id] ?? 0;
                    final textStr = "$count écoute${count > 1 ? 's' : ''}";

                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: isSelected
                          ? ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (bounds) {
                                return LinearGradient(
                                  colors: activeThemeColors,
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ).createShader(
                                  Rect.fromLTWH(
                                    0,
                                    0,
                                    bounds.width,
                                    bounds.height,
                                  ),
                                );
                              },
                              child: Text(
                                textStr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : Text(
                              textStr,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    );
                  },
                )
              else
                ValueListenableBuilder<Set<String>>(
                  valueListenable: likedSongsNotifier,
                  builder: (context, likedSongs, child) {
                    final isLiked = likedSongs.contains(item.id);
                    return GestureDetector(
                      onTap: () {
                        final currentLikes = Set<String>.from(
                          likedSongsNotifier.value,
                        );
                        if (isLiked) {
                          currentLikes.remove(item.id);
                          updateArtistScore(item.artist ?? '', -10);
                        } else {
                          currentLikes.add(item.id);
                          updateArtistScore(item.artist ?? '', 10);
                        }
                        likedSongsNotifier.value = currentLikes;
                      },
                      child: Container(
                        color: Colors.transparent,
                        padding: const EdgeInsets.only(
                          left: 4.0,
                          right: 4.0,
                          top: 12.0,
                          bottom: 12.0,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: isLiked
                              ? ShaderMask(
                                  key: const ValueKey('liked'),
                                  blendMode: BlendMode.srcIn,
                                  shaderCallback: (bounds) {
                                    return LinearGradient(
                                      colors: activeThemeColors,
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ).createShader(
                                      Rect.fromLTWH(
                                        0,
                                        0,
                                        bounds.width,
                                        bounds.height,
                                      ),
                                    );
                                  },
                                  child: const Icon(
                                    CupertinoIcons.heart_fill,
                                    size: 24,
                                  ),
                                )
                              : const Icon(
                                  CupertinoIcons.heart,
                                  key: ValueKey('unliked'),
                                  color: Colors.white54,
                                  size: 24,
                                ),
                        ),
                      ),
                    );
                  },
                ),
              if (onRemoveFromHistory != null)
                GestureDetector(
                  onTap: onRemoveFromHistory,
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.only(
                      left: 4.0,
                      right: 8.0,
                      top: 12.0,
                      bottom: 12.0,
                    ),
                    child: ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (bounds) {
                        return LinearGradient(
                          colors: activeThemeColors,
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ).createShader(
                          Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                        );
                      },
                      child: const Icon(
                        CupertinoIcons.clear,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          onTap: onTap,
          onLongPress: () {
            _showSongOptions(context);
          },
        ),
      ),
    );
  }
}

class SearchPageView extends StatefulWidget {
  final MediaItem? currentItem;
  final List<Color> dynamicGradientColors;

  const SearchPageView({
    super.key,
    required this.currentItem,
    required this.dynamicGradientColors,
  });

  @override
  State<SearchPageView> createState() => _SearchPageViewState();
}

class _SearchPageViewState extends State<SearchPageView> {
  String _searchQuery = '';
  late ScrollController _scrollController;
  bool _isScrolled = false;
  List<MediaItem> _filteredPlaylist = [];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(() {
      if (_scrollController.offset > 5 && !_isScrolled) {
        setState(() {
          _isScrolled = true;
        });
      } else if (_scrollController.offset <= 5 && _isScrolled) {
        setState(() {
          _isScrolled = false;
        });
      }
    });
  }

  void _updateFilter() {
    if (_searchQuery.trim().isEmpty) {
      _filteredPlaylist = [];
    } else {
      _filteredPlaylist = _playlist.where((item) {
        final query = _normalizeString(_searchQuery);
        final titleMatch = _normalizeString(item.title).contains(query);
        final artistMatch = _normalizeString(item.artist ?? '').contains(query);
        return titleMatch || artistMatch;
      }).toList();
      _filteredPlaylist.sort(
        (a, b) =>
            _normalizeString(a.title).compareTo(_normalizeString(b.title)),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _searchQuery.trim().isNotEmpty;

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: CustomSearchBar(
            hintText: "Rechercher un artiste, un titre...",
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
                _updateFilter();
              });
            },
          ),
        ),

        Expanded(
          child: ValueListenableBuilder<List<String>>(
            valueListenable: searchHistoryNotifier,
            builder: (context, historyIds, child) {
              List<MediaItem> displayedList = [];

              if (isSearching) {
                displayedList = _filteredPlaylist;
              } else {
                for (String id in historyIds) {
                  try {
                    displayedList.add(
                      _playlist.firstWhere((item) => item.id == id),
                    );
                  } catch (e) {
                    debugPrint("Item non trouvé dans l'historique : $e");
                  }
                }
              }

              if (displayedList.isEmpty) {
                return Container(
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 100),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSearching
                            ? CupertinoIcons.search
                            : CupertinoIcons.clock,
                        color: Colors.white.withValues(alpha: 0.2),
                        size: 60,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isSearching
                            ? "Aucun résultat pour cette recherche"
                            : "Historique de recherche vide",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return TweenAnimationBuilder<Color?>(
                duration: const Duration(milliseconds: 250),
                tween: ColorTween(
                  begin: Colors.white,
                  end: _isScrolled
                      ? Colors.white.withValues(alpha: 0.0)
                      : Colors.white,
                ),
                builder: (context, topColor, child) {
                  return RepaintBoundary(
                    child: ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            topColor ?? Colors.black,
                            Colors.black,
                            Colors.black,
                          ],
                          stops: const [0.0, 0.05, 1.0],
                        ).createShader(
                          Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                        );
                      },
                      blendMode: BlendMode.dstIn,
                      child: child,
                    ),
                  );
                },
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: displayedList.length,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 180.0,
                  ),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemBuilder: (context, index) {
                    final item = displayedList[index];
                    final isSelected = widget.currentItem?.id == item.id;

                    return SongTile(
                      item: item,
                      isSelected: isSelected,
                      activeThemeColors: widget.dynamicGradientColors,
                      heroTag: 'search_${index}_${item.id}',
                      onRemoveFromHistory: !isSearching
                          ? () {
                              final currentHistory = List<String>.from(
                                searchHistoryNotifier.value,
                              );
                              currentHistory.remove(item.id);
                              searchHistoryNotifier.value = currentHistory;
                            }
                          : null,
                      onTap: () {
                        FocusScope.of(context).unfocus();

                        final currentHistory = List<String>.from(
                          searchHistoryNotifier.value,
                        );
                        currentHistory.remove(item.id);
                        currentHistory.insert(0, item.id);
                        if (currentHistory.length > 50) {
                          currentHistory.removeLast();
                        }
                        searchHistoryNotifier.value = currentHistory;

                        (_audioHandler as MyAudioHandler).playFromList(
                          displayedList,
                          index,
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class ArtistPageView extends StatefulWidget {
  final List<Color> dynamicThemeColors;
  final MediaItem? currentItem;

  const ArtistPageView({
    super.key,
    required this.dynamicThemeColors,
    required this.currentItem,
  });

  @override
  State<ArtistPageView> createState() => ArtistPageViewState();
}

class ArtistPageViewState extends State<ArtistPageView> {
  String _searchQuery = '';
  final FocusNode _searchFocusNode = FocusNode();

  bool get isSearching => _searchQuery.trim().isNotEmpty;

  void clearSearch() {
    _searchFocusNode.unfocus();
    setState(() {
      _searchQuery = '';
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _launchYouTube(String title, String artist) async {
    final query = Uri.encodeComponent("$title $artist audio");
    final url = Uri.parse(
      'https://www.youtube.com/results?search_query=$query',
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("Impossible d'ouvrir YouTube");
    }
  }

  void _showExplorerSheet(BuildContext context, String title, Widget content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ExplorerSheet(
          title: title,
          themeColors: widget.dynamicThemeColors,
          content: content,
        );
      },
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onExplore,
  }) {
    return Container(
      height: 140,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onExplore,
            highlightColor: Colors.white.withValues(alpha: 0.05),
            splashColor: Colors.white.withValues(alpha: 0.1),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 20, right: 20, top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, color: Colors.white70, size: 28),
                          const SizedBox(width: 12),
                          ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (bounds) =>
                                LinearGradient(
                                  colors: widget.dynamicThemeColors,
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ).createShader(
                                  Rect.fromLTWH(
                                    0,
                                    0,
                                    bounds.width,
                                    bounds.height,
                                  ),
                                ),
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(right: 95.0),
                        child: Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      "Explorer",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFavorisContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<Map<String, int>>(
          valueListenable: artistListeningTimeNotifier,
          builder: (context, times, child) {
            if (times.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  "Aucun temps d'écoute pour le moment. Écoutez vos morceaux !",
                  style: TextStyle(color: Colors.white54),
                ),
              );
            }
            var sortedArtists = times.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));

            return SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: sortedArtists.length,
                itemBuilder: (context, index) {
                  final artistName = sortedArtists[index].key;
                  final timeSecs = sortedArtists[index].value;

                  return Container(
                    width: 130,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: index == 0
                                ? const Color(0xFFFFD700).withValues(alpha: 0.2)
                                : Colors.white10,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            "${index + 1}",
                            style: TextStyle(
                              color: index == 0
                                  ? const Color(0xFFFFD700)
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Text(
                            artistName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                          ),
                        ),
                        Text(
                          formatArtistTime(timeSecs),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
        const Padding(
          padding: EdgeInsets.only(left: 20, top: 24, bottom: 8),
          child: Text(
            "Titres les plus appréciés",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ValueListenableBuilder<Set<String>>(
          valueListenable: likedSongsNotifier,
          builder: (context, likedSongs, child) {
            final likedItems = _playlist
                .where((i) => likedSongs.contains(i.id))
                .toList();
            if (likedItems.isEmpty) return const SizedBox();

            return Column(
              children: likedItems.asMap().entries.map((entry) {
                int idx = entry.key;
                MediaItem item = entry.value;
                return SongTile(
                  item: item,
                  isSelected: widget.currentItem?.id == item.id,
                  activeThemeColors: widget.dynamicThemeColors,
                  heroTag: 'fav_exp_${item.id}',
                  showPlayCount: true,
                  onTap: () {
                    (_audioHandler as MyAudioHandler).playFromList(
                      likedItems,
                      idx,
                    );
                  },
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRecommendationList(String targetArtist, bool isDiscover) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fetchArtistRecommendations(targetArtist, isDiscover: isDiscover),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }
        final recs = snapshot.data ?? [];
        if (recs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Text(
                "Aucune recommandation trouvée.",
                style: TextStyle(color: Colors.white54),
              ),
            ),
          );
        }

        return Column(
          children: recs.map((reco) {
            final bool isLocal = reco['isLocal'] as bool;
            final String title = reco['title'] as String;
            final String artist = reco['artist'] as String;
            final String artUri = reco['artUri'] as String;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child:
                        isLocal &&
                            File(
                              '$_documentPath/${_getSafeFileName(title)}.jpg',
                            ).existsSync()
                        ? Image.file(
                            File(
                              '$_documentPath/${_getSafeFileName(title)}.jpg',
                            ),
                            width: 55,
                            height: 55,
                            fit: BoxFit.cover,
                          )
                        : Image.network(
                            artUri,
                            width: 55,
                            height: 55,
                            cacheWidth: 200,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  color: Colors.grey,
                                  width: 55,
                                  height: 55,
                                ),
                          ),
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    artist,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),

                  trailing: isLocal
                      ? _buildLocalLikeButton(reco['localId'] as String)
                      : _buildYouTubeButton(),

                  onTap: () {
                    if (isLocal) {
                      (_audioHandler as MyAudioHandler).playFromList(
                        _playlist,
                        reco['localIndex'] as int,
                      );
                      Navigator.pop(context);
                    } else {
                      _launchYouTube(title, artist);
                    }
                  },
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildYouTubeButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFF0000).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF0000).withValues(alpha: 0.5),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.play_arrow_solid,
            color: Color(0xFFFF0000),
            size: 14,
          ),
          SizedBox(width: 4),
          Text(
            "YouTube",
            style: TextStyle(
              color: Color(0xFFFF0000),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalLikeButton(String id) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: likedSongsNotifier,
      builder: (context, likedSongs, child) {
        final isLiked = likedSongs.contains(id);
        return GestureDetector(
          onTap: () {
            final currentLikes = Set<String>.from(likedSongsNotifier.value);
            final item = _playlist.firstWhere((e) => e.id == id);
            if (isLiked) {
              currentLikes.remove(id);
              updateArtistScore(item.artist ?? '', -10);
            } else {
              currentLikes.add(id);
              updateArtistScore(item.artist ?? '', 10);
            }
            likedSongsNotifier.value = currentLikes;
          },
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: isLiked
                  ? ShaderMask(
                      key: const ValueKey('liked'),
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (bounds) =>
                          LinearGradient(
                            colors: widget.dynamicThemeColors,
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ).createShader(
                            Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                          ),
                      child: const Icon(CupertinoIcons.heart_fill, size: 24),
                    )
                  : const Icon(
                      CupertinoIcons.heart,
                      key: ValueKey('unliked'),
                      color: Colors.white54,
                      size: 24,
                    ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<String> matchingArtists = [];

    if (isSearching) {
      final query = _normalizeString(_searchQuery);
      final allArtists = _playlist.expand((e) => _extractArtists(e.artist)).toSet();
      matchingArtists = allArtists
          .where((a) => _normalizeString(a).contains(query))
          .toList();
      matchingArtists.sort((a, b) => a.compareTo(b));
    }

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: CustomSearchBar(
            focusNode: _searchFocusNode,
            hintText: "Rechercher un artiste...",
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),
        Expanded(
          child: isSearching
              ? (matchingArtists.isEmpty
                    ? Container(
                        alignment: Alignment.topCenter,
                        padding: const EdgeInsets.only(top: 100),
                        child: const Text(
                          "Aucun artiste trouvé",
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.only(
                          top: 10,
                          bottom:
                              MediaQuery.of(context).viewInsets.bottom + 220.0,
                        ),
                        itemCount: matchingArtists.length,
                        itemBuilder: (context, index) {
                          final artistName = matchingArtists[index];
                          final sampleItem = _playlist.firstWhere(
                            (e) => _extractArtists(e.artist).contains(artistName),
                            orElse: () => _playlist.first,
                          );

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            leading: ClipOval(
                              child: getLocalOrNetworkImage(
                                sampleItem,
                                width: 55,
                                height: 55,
                              ),
                            ),
                            title: Text(
                              artistName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing: const Icon(
                              CupertinoIcons.chevron_right,
                              color: Colors.white54,
                              size: 20,
                            ),
                            onTap: () {
                              FocusScope.of(context).unfocus();
                              Navigator.of(context).push(
                                PageRouteBuilder(
                                  pageBuilder:
                                      (
                                        context,
                                        animation,
                                        secondaryAnimation,
                                      ) => ArtistProfileScreen(
                                        artistName: artistName,
                                        sampleItem: sampleItem,
                                        themeColors: widget.dynamicThemeColors,
                                        currentItem: widget.currentItem,
                                      ),
                                  transitionsBuilder:
                                      (
                                        context,
                                        animation,
                                        secondaryAnimation,
                                        child,
                                      ) {
                                        return FadeTransition(
                                          opacity: animation,
                                          child: child,
                                        );
                                      },
                                ),
                              );
                            },
                          );
                        },
                      ))
              : ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    top: 10,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 220.0,
                  ),
                  children: [
                    _buildSectionCard(
                      context,
                      title: "Vos favoris",
                      subtitle: "Les artistes que vous écoutez le plus souvent",
                      icon: CupertinoIcons.star_fill,
                      onExplore: () => _showExplorerSheet(
                        context,
                        "Vos favoris",
                        _buildFavorisContent(),
                      ),
                    ),
                    _buildSectionCard(
                      context,
                      title: "Recommandations",
                      subtitle:
                          "Basé sur l'artiste que vous écoutez actuellement",
                      icon: CupertinoIcons.sparkles,
                      onExplore: () {
                        final target = widget.currentItem?.artist ?? "Damso";
                        _showExplorerSheet(
                          context,
                          "Pour vous",
                          _buildRecommendationList(target, false),
                        );
                      },
                    ),
                    _buildSectionCard(
                      context,
                      title: "À découvrir",
                      subtitle: "Tendances et nouveautés selon vos goûts",
                      icon: CupertinoIcons.compass_fill,
                      onExplore: () {
                        final target = widget.currentItem?.artist ?? "Damso";
                        _showExplorerSheet(
                          context,
                          "À découvrir",
                          _buildRecommendationList(target, true),
                        );
                      },
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class ArtistProfileScreen extends StatefulWidget {
  final String artistName;
  final MediaItem sampleItem;
  final List<Color> themeColors;
  final MediaItem? currentItem;

  const ArtistProfileScreen({
    super.key,
    required this.artistName,
    required this.sampleItem,
    required this.themeColors,
    required this.currentItem,
  });

  @override
  State<ArtistProfileScreen> createState() => _ArtistProfileScreenState();
}

class _ArtistProfileScreenState extends State<ArtistProfileScreen> {
  late ScrollController _scrollController;
  double _overlayOpacity = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted) return;

    final topPadding = MediaQuery.of(context).padding.top;
    final baseCollapseOffset = 320.0 - (topPadding + kToolbarHeight);
    final safeTriggerOffset = baseCollapseOffset + 30.0;

    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;

    double newOpacity = ((offset - safeTriggerOffset) / 20.0).clamp(0.0, 1.0);

    if ((newOpacity - _overlayOpacity).abs() > 0.01) {
      setState(() {
        _overlayOpacity = newOpacity;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final artistSongs = _playlist
        .where((e) => _extractArtists(e.artist).contains(widget.artistName))
        .toList();

    final Map<String, List<MediaItem>> albums = {};
    for (var song in artistSongs) {
      final albumName = song.album ?? 'Singles';
      albums.putIfAbsent(albumName, () => []).add(song);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 320,
                pinned: true,
                stretch: true,
                backgroundColor: Colors.black,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: IconButton(
                  icon: const Icon(CupertinoIcons.back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  titlePadding: const EdgeInsets.only(left: 56, bottom: 12),
                  title: Text(
                    widget.artistName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: getLocalOrNetworkImage(widget.sampleItem),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.6),
                                Colors.black,
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 150),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final albumName = albums.keys.elementAt(index);
                    final songsInAlbum = albums[albumName]!;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 20,
                            top: 24,
                            bottom: 8,
                          ),
                          child: ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (bounds) =>
                                LinearGradient(
                                  colors: widget.themeColors,
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ).createShader(
                                  Rect.fromLTWH(
                                    0,
                                    0,
                                    bounds.width,
                                    bounds.height,
                                  ),
                                ),
                            child: Text(
                              albumName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        ...songsInAlbum.asMap().entries.map((entry) {
                          int idx = entry.key;
                          MediaItem song = entry.value;
                          return SongTile(
                            item: song,
                            isSelected: widget.currentItem?.id == song.id,
                            activeThemeColors: widget.themeColors,
                            heroTag: 'artist_${widget.artistName}_${song.id}',
                            onTap: () {
                              (_audioHandler as MyAudioHandler).playFromList(
                                songsInAlbum,
                                idx,
                              );
                            },
                          );
                        }),
                      ],
                    );
                  }, childCount: albums.keys.length),
                ),
              ),
            ],
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + kToolbarHeight - 1,
            left: 0,
            right: 0,
            height: 40,
            child: IgnorePointer(
              child: Opacity(
                opacity: _overlayOpacity,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black,
                        Colors.black.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AllMusicsView extends StatefulWidget {
  final MediaItem? currentItem;
  final List<Color> dynamicGradientColors;

  const AllMusicsView({
    super.key,
    required this.currentItem,
    required this.dynamicGradientColors,
  });

  @override
  State<AllMusicsView> createState() => _AllMusicsViewState();
}

class _AllMusicsViewState extends State<AllMusicsView> {
  String _searchQuery = '';
  late ScrollController _scrollController;
  bool _isScrolled = false;
  List<MediaItem> _filteredPlaylist = [];

  @override
  void initState() {
    super.initState();
    _updateFilter();
    _scrollController = ScrollController();
    _scrollController.addListener(() {
      if (_scrollController.offset > 5 && !_isScrolled) {
        setState(() {
          _isScrolled = true;
        });
      } else if (_scrollController.offset <= 5 && _isScrolled) {
        setState(() {
          _isScrolled = false;
        });
      }
    });
  }

  void _updateFilter() {
    _filteredPlaylist = _playlist.where((item) {
      final query = _normalizeString(_searchQuery);
      final titleMatch = _normalizeString(item.title).contains(query);
      final artistMatch = _normalizeString(item.artist ?? '').contains(query);
      return titleMatch || artistMatch;
    }).toList();
    _filteredPlaylist.sort(
      (a, b) => _normalizeString(a.title).compareTo(_normalizeString(b.title)),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: CustomSearchBar(
            hintText: "Filtrer vos musiques...",
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
                _updateFilter();
              });
            },
          ),
        ),

        Expanded(
          child: _filteredPlaylist.isEmpty
              ? Container(
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 100),
                  child: const Text(
                    "Aucun résultat pour cette recherche",
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                )
              : TweenAnimationBuilder<Color?>(
                  duration: const Duration(milliseconds: 250),
                  tween: ColorTween(
                    begin: Colors.white,
                    end: _isScrolled
                        ? Colors.white.withValues(alpha: 0.0)
                        : Colors.white,
                  ),
                  builder: (context, topColor, child) {
                    return RepaintBoundary(
                      child: ShaderMask(
                        shaderCallback: (Rect bounds) {
                          return LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              topColor ?? Colors.black,
                              Colors.black,
                              Colors.black,
                            ],
                            stops: const [0.0, 0.05, 1.0],
                          ).createShader(
                            Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                          );
                        },
                        blendMode: BlendMode.dstIn,
                        child: child,
                      ),
                    );
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _filteredPlaylist.length,
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom + 180.0,
                    ),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemBuilder: (context, index) {
                      final item = _filteredPlaylist[index];
                      final isSelected = widget.currentItem?.id == item.id;

                      return SongTile(
                        item: item,
                        isSelected: isSelected,
                        activeThemeColors: widget.dynamicGradientColors,
                        heroTag: 'allmusic_${index}_${item.id}',
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          (_audioHandler as MyAudioHandler).playFromList(
                            _filteredPlaylist,
                            index,
                          );
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class LibraryPageView extends StatefulWidget {
  final MediaItem? currentItem;
  final List<Color> dynamicGradientColors;

  const LibraryPageView({
    super.key,
    required this.currentItem,
    required this.dynamicGradientColors,
  });

  @override
  State<LibraryPageView> createState() => LibraryPageViewState();
}

class LibraryPageViewState extends State<LibraryPageView> {
  String _searchQuery = '';
  late final PageController _pageController;
  late ScrollController _scrollController;
  bool _isScrolled = false;

  String _activePlaylistName = 'LIKES';

  bool get isOnMainPage => _pageController.hasClients
      ? (_pageController.page?.round() ?? 0) == 0
      : true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _scrollController = ScrollController();

    _scrollController.addListener(() {
      if (_scrollController.offset > 5 && !_isScrolled) {
        setState(() {
          _isScrolled = true;
        });
      } else if (_scrollController.offset <= 5 && _isScrolled) {
        setState(() {
          _isScrolled = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _openPlaylist(String name) {
    FocusScope.of(context).unfocus();
    setState(() {
      _activePlaylistName = name;
    });
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 400),
      curve: Curves.fastOutSlowIn,
    );
  }

  void goBack() {
    FocusScope.of(context).unfocus();
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.fastOutSlowIn,
    );
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          _searchQuery = '';
          _isScrolled = false;
        });
      }
    });
  }

  void _showAddSongsSheet(
    BuildContext context,
    String playlistName,
    List<Color> themeColors,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AddSongsSheet(
          playlistName: playlistName,
          activeThemeColors: themeColors,
        );
      },
    );
  }

  void _showEditPlaylistDialog(
    BuildContext context,
    String oldName,
    List<Color> themeColors,
  ) {
    final TextEditingController renameController = TextEditingController(
      text: oldName,
    );
    final ValueNotifier<String?> selectedImageNotifier = ValueNotifier(
      playlistImagesNotifier.value[oldName],
    );

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
                              ).createShader(
                                Rect.fromLTWH(
                                  0,
                                  0,
                                  bounds.width,
                                  bounds.height,
                                ),
                              );
                            },
                            child: const Text(
                              "Modifier la Playlist",
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
                                        selectedImageNotifier.value =
                                            xfile.path;
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
                                              borderRadius:
                                                  BorderRadius.circular(16),
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

                          Theme(
                            data: Theme.of(context).copyWith(
                              textSelectionTheme: TextSelectionThemeData(
                                selectionHandleColor: themeColors[0],
                                selectionColor: themeColors[0].withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            child: TextField(
                              controller: renameController,
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
                          const SizedBox(height: 30),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                    ),
                                  ),
                                  child: CupertinoButton(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    onPressed: () {
                                      final currentContents =
                                          Map<String, Set<String>>.from(
                                            playlistContentsNotifier.value,
                                          );
                                      final currentImages =
                                          Map<String, String>.from(
                                            playlistImagesNotifier.value,
                                          );
                                      final currentList = List<String>.from(
                                        customPlaylistsNotifier.value,
                                      );

                                      currentContents.remove(oldName);
                                      currentList.remove(oldName);
                                      currentImages.remove(oldName);

                                      SharedPreferences.getInstance().then((
                                        prefs,
                                      ) {
                                        prefs.remove(
                                          'playlist_content_$oldName',
                                        );
                                        prefs.remove('playlist_image_$oldName');
                                      });

                                      playlistContentsNotifier.value =
                                          currentContents;
                                      customPlaylistsNotifier.value =
                                          currentList;
                                      playlistImagesNotifier.value =
                                          currentImages;

                                      Navigator.pop(context);
                                    },
                                    child: const Text(
                                      "Supprimer",
                                      style: TextStyle(
                                        color: Color(0xFFFF5252),
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
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
                                      final newName = renameController.text
                                          .trim();
                                      final newImage =
                                          selectedImageNotifier.value ?? '';

                                      if (newName.isNotEmpty) {
                                        final currentContents =
                                            Map<String, Set<String>>.from(
                                              playlistContentsNotifier.value,
                                            );
                                        final currentImages =
                                            Map<String, String>.from(
                                              playlistImagesNotifier.value,
                                            );
                                        final currentList = List<String>.from(
                                          customPlaylistsNotifier.value,
                                        );

                                        if (newName != oldName) {
                                          final playlistSongs =
                                              currentContents[oldName] ??
                                              <String>{};
                                          currentContents.remove(oldName);
                                          currentContents[newName] =
                                              playlistSongs;

                                          final index = currentList.indexOf(
                                            oldName,
                                          );
                                          if (index != -1) {
                                            currentList[index] = newName;
                                          } else {
                                            currentList.add(newName);
                                          }

                                          if (currentImages.containsKey(
                                            oldName,
                                          )) {
                                            final img = currentImages[oldName];
                                            currentImages.remove(oldName);
                                            if (img != null) {
                                              currentImages[newName] = img;
                                            }
                                          }

                                          SharedPreferences.getInstance().then((
                                            prefs,
                                          ) {
                                            prefs.remove(
                                              'playlist_content_$oldName',
                                            );
                                            prefs.remove(
                                              'playlist_image_$oldName',
                                            );
                                          });
                                        }

                                        if (newImage.isNotEmpty) {
                                          currentImages[newName] = newImage;
                                        } else {
                                          currentImages.remove(newName);
                                        }

                                        playlistContentsNotifier.value =
                                            currentContents;
                                        customPlaylistsNotifier.value =
                                            currentList;
                                        playlistImagesNotifier.value =
                                            currentImages;
                                      }
                                      Navigator.pop(context);
                                    },
                                    child: const Text(
                                      "Valider",
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
      renameController.dispose();
      selectedImageNotifier.dispose();
    });
  }

  Widget _buildCustomPlaylistTile(String title) {
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: playlistImagesNotifier,
      builder: (context, images, child) {
        return ValueListenableBuilder<Map<String, Set<String>>>(
          valueListenable: playlistContentsNotifier,
          builder: (context, contents, child) {
            final count = contents[title]?.length ?? 0;
            final customImgPath = images[title];

            Widget leadingIcon;
            if (customImgPath != null &&
                customImgPath.isNotEmpty &&
                File(customImgPath).existsSync()) {
              leadingIcon = ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(customImgPath),
                  width: 45,
                  height: 45,
                  fit: BoxFit.cover,
                ),
              );
            } else {
              leadingIcon = Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    colors: widget.dynamicGradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  CupertinoIcons.music_albums_fill,
                  color: Colors.white,
                  size: 24,
                ),
              );
            }

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  leading: leadingIcon,
                  title: MarqueeWidget(
                    resetKey: 'title_$title',
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  subtitle: Text(
                    "$count titre${count > 1 ? 's' : ''}",
                    style: const TextStyle(color: Colors.white70),
                  ),
                  trailing: const Icon(
                    CupertinoIcons.chevron_right,
                    color: Colors.white54,
                    size: 20,
                  ),
                  onTap: () {
                    _openPlaylist(title);
                  },
                  onLongPress: () {
                    _showEditPlaylistDialog(
                      context,
                      title,
                      widget.dynamicGradientColors,
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHub() {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: likedSongsNotifier,
      builder: (context, likedSongs, child) {
        return ValueListenableBuilder<List<String>>(
          valueListenable: customPlaylistsNotifier,
          builder: (context, customPlaylists, child) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 20,
                      right: 16,
                      top: 20,
                      bottom: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Bibliothèque",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            CupertinoIcons.add,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: () {
                            showCreatePlaylistDialog(
                              context,
                              widget.dynamicGradientColors,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                if (likedSongs.isNotEmpty || customPlaylists.isNotEmpty)
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          if (likedSongs.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _openPlaylist('LIKES');
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    width: 0.5,
                                  ),
                                ),
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: ListTile(
                                    leading: Container(
                                      width: 45,
                                      height: 45,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        gradient: LinearGradient(
                                          colors: widget.dynamicGradientColors,
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.heart_fill,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                    title: const Text(
                                      "Titres likés",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    subtitle: Text(
                                      "${likedSongs.length} titre${likedSongs.length > 1 ? 's' : ''}",
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    trailing: const Icon(
                                      CupertinoIcons.chevron_right,
                                      color: Colors.white54,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          ...customPlaylists.reversed.map(
                            (name) => _buildCustomPlaylistTile(name),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Container(
                      alignment: Alignment.topCenter,
                      padding: const EdgeInsets.only(top: 100),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.heart,
                            color: Colors.white.withValues(alpha: 0.2),
                            size: 60,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "Votre bibliothèque est vide",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "Les titres que vous aimez apparaîtront ici",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  top: 10,
                  left: 4,
                  bottom: 4,
                  right: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              CupertinoIcons.back,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: goBack,
                          ),
                          Expanded(
                            child: MarqueeWidget(
                              resetKey: 'header_$_activePlaylistName',
                              child: Text(
                                _activePlaylistName == 'LIKES'
                                    ? "Titres likés"
                                    : _activePlaylistName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_activePlaylistName != 'LIKES')
                      IconButton(
                        icon: const Icon(
                          CupertinoIcons.add,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () {
                          _showAddSongsSheet(
                            context,
                            _activePlaylistName,
                            widget.dynamicGradientColors,
                          );
                        },
                      ),
                  ],
                ),
              ),
              CustomSearchBar(
                hintText: _activePlaylistName == 'LIKES'
                    ? "Rechercher dans vos coups de cœur..."
                    : "Rechercher dans cette playlist...",
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ],
          ),
        ),

        Expanded(
          child: TweenAnimationBuilder<Color?>(
            duration: const Duration(milliseconds: 250),
            tween: ColorTween(
              begin: Colors.white,
              end: _isScrolled
                  ? Colors.white.withValues(alpha: 0.0)
                  : Colors.white,
            ),
            builder: (context, topColor, child) {
              return ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      topColor ?? Colors.black,
                      Colors.black,
                      Colors.black,
                    ],
                    stops: const [0.0, 0.05, 1.0],
                  ).createShader(
                    Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                  );
                },
                blendMode: BlendMode.dstIn,
                child: child,
              );
            },
            child: ValueListenableBuilder<Set<String>>(
              valueListenable: likedSongsNotifier,
              builder: (context, likedSongs, _) {
                return ValueListenableBuilder<Map<String, Set<String>>>(
                  valueListenable: playlistContentsNotifier,
                  builder: (context, playlistContents, _) {
                    final isLikes = _activePlaylistName == 'LIKES';
                    final currentSet = isLikes
                        ? likedSongs
                        : (playlistContents[_activePlaylistName] ?? <String>{});

                    if (isLikes &&
                        currentSet.isEmpty &&
                        _pageController.hasClients &&
                        (_pageController.page?.round() ?? 0) == 1) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) goBack();
                      });
                    }

                    final filteredPlaylist = _playlist.where((item) {
                      if (!currentSet.contains(item.id)) return false;
                      final query = _normalizeString(_searchQuery);
                      final titleMatch = _normalizeString(
                        item.title,
                      ).contains(query);
                      final artistMatch = _normalizeString(
                        item.artist ?? '',
                      ).contains(query);
                      return titleMatch || artistMatch;
                    }).toList();

                    filteredPlaylist.sort(
                      (a, b) => _normalizeString(
                        a.title,
                      ).compareTo(_normalizeString(b.title)),
                    );

                    String emptyText = _searchQuery.isEmpty
                        ? (isLikes ? "Votre bibliothèque est vide" : "")
                        : "Aucun résultat pour cette recherche";

                    if (filteredPlaylist.isEmpty) {
                      if (emptyText.isEmpty) return const SizedBox();
                      return Container(
                        alignment: Alignment.topCenter,
                        padding: const EdgeInsets.only(top: 100),
                        child: Text(
                          emptyText,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      itemCount: filteredPlaylist.length,
                      padding: EdgeInsets.only(
                        bottom:
                            MediaQuery.of(context).viewInsets.bottom + 180.0,
                      ),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemBuilder: (context, index) {
                        final item = filteredPlaylist[index];
                        final isSelected = widget.currentItem?.id == item.id;

                        return SongTile(
                          item: item,
                          isSelected: isSelected,
                          activeThemeColors: widget.dynamicGradientColors,
                          heroTag:
                              'lib_${_activePlaylistName}_${index}_${item.id}',
                          onTap: () {
                            FocusScope.of(context).unfocus();
                            (_audioHandler as MyAudioHandler).playFromList(
                              filteredPlaylist,
                              index,
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      children: [_buildHub(), _buildList()],
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _isPlayerExpanded = false;
  final Set<String> _downloadedSongs = {};
  final Set<String> _downloadingSongs = {};
  late final Stream<PositionData> _positionDataStream;

  late final PageController _mainPageController;
  final GlobalKey<LibraryPageViewState> _libraryKey =
      GlobalKey<LibraryPageViewState>();
  final GlobalKey<ArtistPageViewState> _artistKey =
      GlobalKey<ArtistPageViewState>();

  List<LyricLine> _currentLyrics = [];
  bool _isLoadingLyrics = false;
  String? _lastSongId;

  List<Color> _dynamicGradientColors = [
    const Color(0xFF9C27B0),
    const Color(0xFF9C27B0),
    const Color(0xFF311B92),
    const Color(0xFF311B92),
  ];

  @override
  void initState() {
    super.initState();
    _mainPageController = PageController(initialPage: _currentIndex);
    _scanLocalFiles();

    _positionDataStream =
        Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
          Stream.periodic(
            const Duration(milliseconds: 16),
          ).map((_) => _audioHandler.playbackState.value.position),
          _audioHandler.playbackState.map((state) => state.bufferedPosition),
          _audioHandler.mediaItem.map((item) => item?.duration),
          (position, bufferedPosition, duration) => PositionData(
            position,
            bufferedPosition,
            duration ?? Duration.zero,
          ),
        ).asBroadcastStream();

    _audioHandler.mediaItem.listen((item) {
      if (item != null && item.id != _lastSongId) {
        _lastSongId = item.id;
        _fetchLyrics(item);
        if (mounted) {
          setState(() {
            _dynamicGradientColors = _getAlbumGradientColors(item.album ?? '');
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _mainPageController.dispose();
    super.dispose();
  }

  Future<void> _fetchLyrics(MediaItem item) async {
    final songId = item.id;
    final fileName = '${item.id.split('/').last.replaceAll('.flac', '')}.lrc';

    if (_lyricsCache.containsKey(songId)) {
      setState(() {
        _currentLyrics = _lyricsCache[songId]!;
        _isLoadingLyrics = false;
      });
      return;
    }
    setState(() {
      _isLoadingLyrics = true;
      _currentLyrics = [];
    });

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final localFile = File('${docDir.path}/$fileName');
      String lrcContent = "";

      if (localFile.existsSync()) {
        try {
          lrcContent = await localFile.readAsString();
        } catch (e) {
          debugPrint("Erreur de suppression du fichier corrompu : $e");
          localFile.deleteSync();
        }
      }
      if (lrcContent.contains('<!DOCTYPE')) {
        lrcContent = "";
        if (localFile.existsSync()) {
          localFile.deleteSync();
        }
      }
      if (lrcContent.isEmpty) {
        final url = Uri.parse('${ApiConfig.baseUrl}/$fileName');
        final response = await http
            .get(url)
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          try {
            lrcContent = utf8.decode(response.bodyBytes);
          } catch (_) {
            lrcContent = latin1
                .decode(response.bodyBytes)
                .replaceAll('\u009C', 'œ')
                .replaceAll('\u008C', 'Œ')
                .replaceAll('\u0092', '’');
          }
          await localFile.writeAsString(lrcContent);
        }
      }
      if (!mounted || _lastSongId != songId) return;
      if (lrcContent.isNotEmpty) {
        _parseLRC(lrcContent, songId);
        return;
      }
    } catch (e) {
      debugPrint("Erreur de récupération des paroles: $e");
    }

    if (mounted && _lastSongId == songId) {
      setState(() {
        _currentLyrics = [
          LyricLine(
            time: Duration.zero,
            text: "Paroles indisponibles pour ce titre",
          ),
        ];
        _isLoadingLyrics = false;
      });
    }
  }

  final Map<String, List<LyricLine>> _lyricsCache = {};

  void _parseLRC(String lrcContent, String songId) {
    if (!mounted || _lastSongId != songId) return;
    final List<LyricLine> parsedLines = [];
    final RegExp regExp = RegExp(r'\[(\d+):(\d+)\.(\d+)\](.*)');
    for (var line in lrcContent.split('\n')) {
      final match = regExp.firstMatch(line);
      if (match != null) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final mil = match.group(3)!;
        final text = match.group(4)!.trim();
        int ms = int.parse(mil);
        if (mil.length == 2) ms *= 10;
        final duration = Duration(minutes: min, seconds: sec, milliseconds: ms);
        if (text.isNotEmpty) {
          parsedLines.add(LyricLine(time: duration, text: text));
        }
      }
    }
    parsedLines.sort((a, b) => a.time.compareTo(b.time));
    if (mounted && _lastSongId == songId) {
      _lyricsCache[songId] = parsedLines;
      setState(() {
        _currentLyrics = parsedLines;
        _isLoadingLyrics = false;
      });
    }
  }

  Future<void> _scanLocalFiles() async {
    final docDir = await getApplicationDocumentsDirectory();
    final Set<String> localIds = {};
    for (var item in _playlist) {
      final flacFile = File(
        '${docDir.path}/${item.id.split('/').last.replaceAll('.flac', '')}.flac',
      );
      final mp3File = File(
        '${docDir.path}/${item.id.split('/').last.replaceAll('.flac', '')}.mp3',
      );
      if (flacFile.existsSync() || mp3File.existsSync()) {
        localIds.add(item.id);
      }
    }
    setState(() {
      _downloadedSongs.addAll(localIds);
    });
  }

  Future<void> _toggleDownload(MediaItem item) async {
    final docDir = await getApplicationDocumentsDirectory();
    final safeName = item.id.split('/').last.replaceAll('.flac', '');

    final localFlac = File('${docDir.path}/$safeName.flac');
    final localMp3 = File('${docDir.path}/$safeName.mp3');

    final cacheFlac = File('${docDir.path}/cache/$safeName.flac');
    final cacheMp3 = File('${docDir.path}/cache/$safeName.mp3');

    if (_downloadedSongs.contains(item.id)) {
      if (localFlac.existsSync()) localFlac.deleteSync();
      if (localMp3.existsSync()) localMp3.deleteSync();

      setState(() {
        _downloadedSongs.remove(item.id);
      });

      bool isStreamFlac = isLosslessNotifier.value;
      bool hasFlac = item.extras?['hasFlac'] as bool? ?? true;
      if (isStreamFlac && !hasFlac) isStreamFlac = false;
      
      String streamUrl = isStreamFlac
          ? item.id
          : item.id.replaceAll('.flac', '.mp3');
      final newItem = item.copyWith(extras: {'isFlac': isStreamFlac, 'hasFlac': hasFlac});

      final source =
          isCacheEnabledNotifier.value ||
              (isStreamFlac ? cacheFlac.existsSync() : cacheMp3.existsSync())
          ? LockCachingAudioSource(
              Uri.parse(streamUrl),
              cacheFile: isStreamFlac ? cacheFlac : cacheMp3,
              tag: newItem,
            )
          : AudioSource.uri(Uri.parse(streamUrl), tag: newItem);

      _notifyAudioHandler(item, source, newItem);
    } else {
      if (_downloadingSongs.contains(item.id)) return;
      setState(() {
        _downloadingSongs.add(item.id);
      });

      try {
        bool downloadFlac = isDownloadLosslessNotifier.value;
        bool hasFlac = item.extras?['hasFlac'] as bool? ?? true;
        if (downloadFlac && !hasFlac) downloadFlac = false;
        
        String downloadUrl = downloadFlac
            ? item.id
            : item.id.replaceAll('.flac', '.mp3');
        File fileToSave = downloadFlac ? localFlac : localMp3;

        if (cacheFlac.existsSync()) {
          try {
            cacheFlac.deleteSync();
          } catch (e) {
            debugPrint("Erreur cacheFlac : $e");
          }
        }
        if (cacheMp3.existsSync()) {
          try {
            cacheMp3.deleteSync();
          } catch (e) {
            debugPrint("Erreur cacheMp3 : $e");
          }
        }

        if (downloadFlac && localMp3.existsSync()) localMp3.deleteSync();
        if (!downloadFlac && localFlac.existsSync()) localFlac.deleteSync();

        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(downloadUrl));
        final response = await request.close();
        await response.pipe(fileToSave.openWrite());

        setState(() {
          _downloadingSongs.remove(item.id);
          _downloadedSongs.add(item.id);
        });

        final newItem = item.copyWith(extras: {'isFlac': downloadFlac, 'hasFlac': hasFlac});
        _notifyAudioHandler(
          item,
          AudioSource.file(fileToSave.path, tag: newItem),
          newItem,
        );
      } catch (e) {
        debugPrint("Erreur téléchargement: $e");
        setState(() {
          _downloadingSongs.remove(item.id);
        });
      }
    }
  }

  void _notifyAudioHandler(
    MediaItem item,
    AudioSource source,
    MediaItem newItem,
  ) {
    if (_audioHandler is MyAudioHandler) {
      (_audioHandler as MyAudioHandler).updateSourceAt(
        item.id,
        source,
        newItem,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).viewPadding.top;
    final double bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final double extraBottom = bottomPadding > 35 ? bottomPadding : 0;
    final double screenHeight = MediaQuery.of(context).size.height;

    final double navBarHeight = 66.0 + bottomPadding;

    const Duration transitionDuration = Duration(milliseconds: 410);
    const Curve transitionCurve = Curves.fastOutSlowIn;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        if (_isPlayerExpanded) {
          setState(() {
            _isPlayerExpanded = false;
          });
          return;
        }

        if (_currentIndex == 1) {
          final artistState = _artistKey.currentState;
          if (artistState != null && artistState.isSearching) {
            artistState.clearSearch();
            return;
          }
        }

        if (_currentIndex == 3) {
          final libState = _libraryKey.currentState;
          if (libState != null && !libState.isOnMainPage) {
            libState.goBack();
            return;
          }
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.black,
        body: StreamBuilder<MediaItem?>(
          stream: _audioHandler.mediaItem,
          builder: (context, mainSnapshot) {
            final currentItem = mainSnapshot.data;
            final hasMusic = currentItem != null;

            final safeItem = currentItem ?? _playlist.first;

            return TweenAnimationBuilder<Color?>(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              tween: ColorTween(end: _dynamicGradientColors[0]),
              builder: (context, color1, _) {
                return TweenAnimationBuilder<Color?>(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  tween: ColorTween(end: _dynamicGradientColors[1]),
                  builder: (context, color2, _) {
                    return TweenAnimationBuilder<Color?>(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      tween: ColorTween(end: _dynamicGradientColors[2]),
                      builder: (context, color3, _) {
                        return TweenAnimationBuilder<Color?>(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                          tween: ColorTween(end: _dynamicGradientColors[3]),
                          builder: (context, color4, _) {
                            final List<Color> smoothThemeColors = [
                              color1 ?? _dynamicGradientColors[0],
                              color2 ?? _dynamicGradientColors[1],
                              color3 ?? _dynamicGradientColors[2],
                              color4 ?? _dynamicGradientColors[3],
                            ];

                            return Stack(
                              children: [
                                Positioned.fill(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 600),
                                    child: hasMusic
                                        ? RealAlbumBlurredBackground(
                                            key: ValueKey<String>(safeItem.id),
                                            item: safeItem,
                                          )
                                        : Container(color: Colors.black),
                                  ),
                                ),

                                AnimatedOpacity(
                                  opacity: _isPlayerExpanded ? 0.0 : 1.0,
                                  duration: const Duration(milliseconds: 300),
                                  child: IgnorePointer(
                                    ignoring: _isPlayerExpanded,
                                    child: Scaffold(
                                      backgroundColor: Colors.transparent,
                                      extendBody: true,
                                      resizeToAvoidBottomInset: false,
                                      body: PageView(
                                        controller: _mainPageController,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        children: [
                                          SearchPageView(
                                            currentItem: currentItem,
                                            dynamicGradientColors:
                                                smoothThemeColors,
                                          ),
                                          ArtistPageView(
                                            key: _artistKey,
                                            dynamicThemeColors:
                                                smoothThemeColors,
                                            currentItem: currentItem,
                                          ),
                                          AllMusicsView(
                                            currentItem: currentItem,
                                            dynamicGradientColors:
                                                smoothThemeColors,
                                          ),
                                          LibraryPageView(
                                            key: _libraryKey,
                                            currentItem: currentItem,
                                            dynamicGradientColors:
                                                smoothThemeColors,
                                          ),
                                          AccountPageView(
                                            dynamicGradientColors:
                                                smoothThemeColors,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                StreamBuilder<PlaybackState>(
                                  stream: _audioHandler.playbackState,
                                  builder: (context, playSnapshot) {
                                    final playbackState = playSnapshot.data;
                                    final playing =
                                        playbackState?.playing ?? false;

                                    final isDownloaded = _downloadedSongs
                                        .contains(safeItem.id);
                                    final isDownloading = _downloadingSongs
                                        .contains(safeItem.id);

                                    return AnimatedPositioned(
                                      duration: transitionDuration,
                                      curve: transitionCurve,
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      height: _isPlayerExpanded
                                          ? screenHeight
                                          : (hasMusic
                                                ? 115 + navBarHeight
                                                : navBarHeight),
                                      child: Material(
                                        type: MaterialType.transparency,
                                        child: GestureDetector(
                                          onTap: () {
                                            if (hasMusic &&
                                                !_isPlayerExpanded) {
                                              FocusScope.of(context).unfocus();
                                              setState(() {
                                                _isPlayerExpanded = true;
                                              });
                                            }
                                          },
                                          onVerticalDragEnd: (details) {
                                            if (_isPlayerExpanded &&
                                                details.primaryVelocity !=
                                                    null &&
                                                details.primaryVelocity! >
                                                    300) {
                                              setState(() {
                                                _isPlayerExpanded = false;
                                              });
                                            }
                                          },
                                          child: AnimatedContainer(
                                            duration: transitionDuration,
                                            curve: transitionCurve,
                                            clipBehavior: Clip.antiAlias,
                                            decoration: BoxDecoration(
                                              color: _isPlayerExpanded
                                                  ? Colors.black.withValues(
                                                      alpha: 0.1,
                                                    )
                                                  : Colors.black.withValues(
                                                      alpha: 0.55,
                                                    ),
                                              borderRadius: _isPlayerExpanded
                                                  ? BorderRadius.zero
                                                  : const BorderRadius.only(
                                                      topLeft: Radius.circular(
                                                        24,
                                                      ),
                                                      topRight: Radius.circular(
                                                        24,
                                                      ),
                                                    ),
                                              border: _isPlayerExpanded
                                                  ? null
                                                  : const Border(
                                                      top: BorderSide(
                                                        color: Colors.white12,
                                                        width: 0.5,
                                                      ),
                                                    ),
                                            ),
                                            child: BackdropFilter(
                                              filter: ImageFilter.blur(
                                                sigmaX: 30.0,
                                                sigmaY: 30.0,
                                              ),
                                              child: Stack(
                                                clipBehavior: Clip.none,
                                                children: [
                                                  if (hasMusic)
                                                    AnimatedPositioned(
                                                      duration:
                                                          transitionDuration,
                                                      curve: transitionCurve,
                                                      top: 0,
                                                      left: 0,
                                                      right: 0,
                                                      bottom: _isPlayerExpanded
                                                          ? 0
                                                          : navBarHeight,
                                                      child: Stack(
                                                        clipBehavior: Clip.none,
                                                        children: [
                                                          AnimatedPositioned(
                                                            duration:
                                                                transitionDuration,
                                                            curve:
                                                                transitionCurve,
                                                            top:
                                                                _isPlayerExpanded
                                                                ? topPadding +
                                                                      10
                                                                : -60,
                                                            left: 20,
                                                            right: 20,
                                                            child: AnimatedOpacity(
                                                              duration:
                                                                  const Duration(
                                                                    milliseconds:
                                                                        200,
                                                                  ),
                                                              opacity:
                                                                  _isPlayerExpanded
                                                                  ? 1.0
                                                                  : 0.0,
                                                              child: Row(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .spaceBetween,
                                                                children: [
                                                                  IconButton(
                                                                    icon: const Icon(
                                                                      Icons
                                                                          .keyboard_arrow_down,
                                                                      color: Colors
                                                                          .white,
                                                                      size: 30,
                                                                    ),
                                                                    onPressed: () {
                                                                      FocusScope.of(
                                                                        context,
                                                                      ).unfocus();
                                                                      setState(() {
                                                                        _isPlayerExpanded =
                                                                            false;
                                                                      });
                                                                    },
                                                                  ),
                                                                  IconButton(
                                                                    icon: Icon(
                                                                      isDownloading
                                                                          ? Icons.downloading
                                                                          : (isDownloaded
                                                                                ? Icons.cloud_done
                                                                                : Icons.cloud_download),
                                                                      size: 26,
                                                                    ),
                                                                    color:
                                                                        isDownloaded
                                                                        ? Colors
                                                                              .white
                                                                        : Colors
                                                                              .white70,
                                                                    onPressed: () {
                                                                      _toggleDownload(
                                                                        safeItem,
                                                                      );
                                                                    },
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),

                                                          AnimatedPositioned(
                                                            duration:
                                                                transitionDuration,
                                                            curve:
                                                                transitionCurve,
                                                            top:
                                                                _isPlayerExpanded
                                                                ? topPadding +
                                                                      65
                                                                : 12,
                                                            left: 20,
                                                            width:
                                                                _isPlayerExpanded
                                                                ? 60
                                                                : 54,
                                                            height:
                                                                _isPlayerExpanded
                                                                ? 60
                                                                : 54,
                                                            child: AnimatedContainer(
                                                              duration:
                                                                  transitionDuration,
                                                              curve:
                                                                  transitionCurve,
                                                              clipBehavior: Clip
                                                                  .antiAlias,
                                                              decoration: BoxDecoration(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      _isPlayerExpanded
                                                                          ? 12.0
                                                                          : 8.0,
                                                                    ),
                                                              ),
                                                              child: Image.network(
                                                                safeItem.artUri
                                                                    .toString(),
                                                                cacheWidth: 500,
                                                                fit: BoxFit
                                                                    .cover,
                                                              ),
                                                            ),
                                                          ),

                                                          AnimatedPositioned(
                                                            duration:
                                                                transitionDuration,
                                                            curve:
                                                                transitionCurve,
                                                            top:
                                                                _isPlayerExpanded
                                                                ? topPadding +
                                                                      68
                                                                : 11,
                                                            left:
                                                                _isPlayerExpanded
                                                                ? 95
                                                                : 88,
                                                            right:
                                                                _isPlayerExpanded
                                                                ? 20
                                                                : 12, // Aligné avec le bord droit du bouton Répéter
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                MarqueeWidget(
                                                                  resetKey: 'title_${safeItem.id}',
                                                                  child: Row(
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .center,
                                                                    children: [
                                                                      // 1. LE TITRE DE LA MUSIQUE (De retour avec son magnifique gradient !)
                                                                      ShaderMask(
                                                                        blendMode:
                                                                            BlendMode.srcIn,
                                                                        shaderCallback:
                                                                            (
                                                                              bounds,
                                                                            ) {
                                                                              return LinearGradient(
                                                                                colors: [
                                                                                  smoothThemeColors[0],
                                                                                  smoothThemeColors[1],
                                                                                ],
                                                                                begin: Alignment.centerLeft,
                                                                                end: Alignment.centerRight,
                                                                              ).createShader(
                                                                                Rect.fromLTWH(
                                                                                  0,
                                                                                  0,
                                                                                  bounds.width,
                                                                                  bounds.height,
                                                                                ),
                                                                              ); // Le Rect.fromLTWH évite le bug d'affichage lors du scroll !
                                                                            },
                                                                        child: AnimatedDefaultTextStyle(
                                                                          duration:
                                                                              transitionDuration,
                                                                          curve:
                                                                              transitionCurve,
                                                                          style: TextStyle(
                                                                            fontWeight:
                                                                                FontWeight.bold,
                                                                            fontSize:
                                                                                _isPlayerExpanded
                                                                                ? 20
                                                                                : 16,
                                                                            color:
                                                                                Colors.white,
                                                                          ),
                                                                          child: Text(
                                                                            safeItem.title,
                                                                          ),
                                                                        ),
                                                                      ),

                                                                      // 2. LE BADGE LOSSLESS ALIGNÉ AVEC LE TITRE
                                                                      if (safeItem
                                                                              .extras?['isFlac'] ==
                                                                          true) ...[
                                                                        const SizedBox(
                                                                          width:
                                                                              6,
                                                                        ),
                                                                        Transform.translate(
                                                                          offset: const Offset(
                                                                            0,
                                                                            1.5,
                                                                          ),
                                                                          child: ShaderMask(
                                                                            blendMode:
                                                                                BlendMode.srcIn,
                                                                            shaderCallback:
                                                                                (
                                                                                  bounds,
                                                                                ) {
                                                                                  return LinearGradient(
                                                                                    colors: smoothThemeColors,
                                                                                    begin: Alignment.centerLeft,
                                                                                    end: Alignment.centerRight,
                                                                                  ).createShader(
                                                                                    bounds,
                                                                                  );
                                                                                },
                                                                            child: AnimatedDefaultTextStyle(
                                                                              duration: transitionDuration,
                                                                              curve: transitionCurve,
                                                                              style: TextStyle(
                                                                                fontSize: _isPlayerExpanded
                                                                                    ? 13
                                                                                    : 10,
                                                                                fontWeight: FontWeight.w900,
                                                                                letterSpacing: 0.5,
                                                                                color: Colors.white,
                                                                              ),
                                                                              child: const Text(
                                                                                "• LOSSLESS",
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ],
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                  height: 5,
                                                                ),

                                                                // 3. L'ARTISTE (Padding supplémentaire pour éviter le bouton Précédent)
                                                                AnimatedPadding(
                                                                  duration: transitionDuration,
                                                                  curve: transitionCurve,
                                                                  padding: EdgeInsets.only(
                                                                    right: _isPlayerExpanded ? 0 : 130, // 12 + 130 = 142
                                                                  ),
                                                                  child: MarqueeWidget(
                                                                    resetKey:
                                                                      'artist_${safeItem.id}',
                                                                  child: TweenAnimationBuilder<double>(
                                                                    duration:
                                                                        transitionDuration,
                                                                    curve:
                                                                        transitionCurve,
                                                                    tween: Tween<double>(
                                                                      end:
                                                                          _isPlayerExpanded
                                                                          ? 15.0
                                                                          : 13.0,
                                                                    ),
                                                                    builder:
                                                                        (
                                                                          context,
                                                                          fontSize,
                                                                          child,
                                                                        ) {
                                                                          return Text(
                                                                            _formatArtist(safeItem.artist),
                                                                            style: TextStyle(
                                                                              color: Color.lerp(
                                                                                const Color(
                                                                                  0xFFCCCCCC,
                                                                                ),
                                                                                smoothThemeColors[0],
                                                                                0.35,
                                                                              ),
                                                                              fontSize: fontSize,
                                                                              height: 1.0,
                                                                              fontWeight: FontWeight.w500,
                                                                            ),
                                                                          );
                                                                        },
                                                                  ),
                                                                ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),

                                                          AnimatedPositioned(
                                                            duration:
                                                                transitionDuration,
                                                            curve:
                                                                transitionCurve,
                                                            top:
                                                                _isPlayerExpanded
                                                                ? topPadding +
                                                                      155
                                                                : screenHeight,
                                                            bottom:
                                                                _isPlayerExpanded
                                                                ? 160 + extraBottom
                                                                : 0,
                                                            left: 0,
                                                            right: 0,
                                                            child: AnimatedOpacity(
                                                              duration:
                                                                  const Duration(
                                                                    milliseconds:
                                                                        300,
                                                                  ),
                                                              opacity:
                                                                  _isPlayerExpanded
                                                                  ? 1.0
                                                                  : 0.0,
                                                              child:
                                                                  _isLoadingLyrics
                                                                  ? const Center(
                                                                      child: CircularProgressIndicator(
                                                                        color: Colors
                                                                            .white,
                                                                      ),
                                                                    )
                                                                  : MusicalityLyricsView(
                                                                      lyrics:
                                                                          _currentLyrics,
                                                                      positionStream:
                                                                          _positionDataStream,
                                                                    ),
                                                            ),
                                                          ),

                                                          AnimatedPositioned(
                                                            duration:
                                                                transitionDuration,
                                                            curve:
                                                                transitionCurve,
                                                            left:
                                                                _isPlayerExpanded
                                                                ? 20
                                                                : -50,
                                                            bottom:
                                                                _isPlayerExpanded
                                                                ? 95 + extraBottom
                                                                : 48,
                                                            width:
                                                                _isPlayerExpanded
                                                                ? 40
                                                                : 30,
                                                            height:
                                                                _isPlayerExpanded
                                                                ? 40
                                                                : 30,
                                                            child: AnimatedOpacity(
                                                              duration:
                                                                  const Duration(
                                                                    milliseconds:
                                                                        200,
                                                                  ),
                                                              opacity:
                                                                  _isPlayerExpanded
                                                                  ? 1.0
                                                                  : 0.0,
                                                              child: IgnorePointer(
                                                                ignoring:
                                                                    !_isPlayerExpanded,
                                                                child: StreamBuilder<bool>(
                                                                  stream:
                                                                      (_audioHandler
                                                                              as MyAudioHandler)
                                                                          .shuffleModeEnabledStream,
                                                                  initialData:
                                                                      false,
                                                                  builder:
                                                                      (
                                                                        context,
                                                                        snapshot,
                                                                      ) {
                                                                        final isShuffle =
                                                                            snapshot.data ??
                                                                            false;
                                                                        return HyperOSShuffleButton(
                                                                          isShuffle:
                                                                              isShuffle,
                                                                          onTap: () {
                                                                            (_audioHandler
                                                                                    as MyAudioHandler)
                                                                                .toggleShuffleMode();
                                                                          },
                                                                          gradientColors:
                                                                              smoothThemeColors,
                                                                          size:
                                                                              _isPlayerExpanded
                                                                              ? 30
                                                                              : 20,
                                                                        );
                                                                      },
                                                                ),
                                                              ),
                                                            ),
                                                          ),

                                                          AnimatedPositioned(
                                                            duration:
                                                                transitionDuration,
                                                            curve:
                                                                transitionCurve,
                                                            left: 0,
                                                            right: 0,
                                                            bottom:
                                                                _isPlayerExpanded
                                                                ? 85 + extraBottom
                                                                : 33,
                                                            height: 60,
                                                            child: AnimatedPadding(
                                                              duration:
                                                                  transitionDuration,
                                                              curve:
                                                                  transitionCurve,
                                                              padding:
                                                                  EdgeInsets.only(
                                                                    right:
                                                                        _isPlayerExpanded
                                                                        ? 0
                                                                        : 50,
                                                                  ),
                                                              child: AnimatedAlign(
                                                                duration:
                                                                    transitionDuration,
                                                                curve:
                                                                    transitionCurve,
                                                                alignment:
                                                                    _isPlayerExpanded
                                                                    ? Alignment
                                                                          .center
                                                                    : Alignment
                                                                          .centerRight,
                                                                child: Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    HyperOSButton(
                                                                      onTap: () {
                                                                        _audioHandler
                                                                            .skipToPrevious();
                                                                      },
                                                                      child: SmoothIcon(
                                                                        icon: CupertinoIcons
                                                                            .backward_fill,
                                                                        color: Colors
                                                                            .white,
                                                                        size:
                                                                            _isPlayerExpanded
                                                                            ? 36
                                                                            : 22,
                                                                      ),
                                                                    ),
                                                                    AnimatedContainer(
                                                                      duration:
                                                                          transitionDuration,
                                                                      curve:
                                                                          transitionCurve,
                                                                      width:
                                                                          _isPlayerExpanded
                                                                          ? 35
                                                                          : 6,
                                                                    ),
                                                                    HyperOSButton(
                                                                      onTap: () {
                                                                        if (playing) {
                                                                          _audioHandler
                                                                              .pause();
                                                                        } else {
                                                                          _audioHandler
                                                                              .play();
                                                                        }
                                                                      },
                                                                      child: SmoothIcon(
                                                                        icon:
                                                                            playing
                                                                            ? CupertinoIcons.pause_solid
                                                                            : CupertinoIcons.play_arrow_solid,
                                                                        color: Colors
                                                                            .white,
                                                                        size:
                                                                            _isPlayerExpanded
                                                                            ? 46
                                                                            : 26,
                                                                      ),
                                                                    ),
                                                                    AnimatedContainer(
                                                                      duration:
                                                                          transitionDuration,
                                                                      curve:
                                                                          transitionCurve,
                                                                      width:
                                                                          _isPlayerExpanded
                                                                          ? 35
                                                                          : 6,
                                                                    ),
                                                                    HyperOSButton(
                                                                      onTap: () {
                                                                        _audioHandler
                                                                            .skipToNext();
                                                                      },
                                                                      child: SmoothIcon(
                                                                        icon: CupertinoIcons
                                                                            .forward_fill,
                                                                        color: Colors
                                                                            .white,
                                                                        size:
                                                                            _isPlayerExpanded
                                                                            ? 36
                                                                            : 22,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                          ),

                                                          AnimatedPositioned(
                                                            duration:
                                                                transitionDuration,
                                                            curve:
                                                                transitionCurve,
                                                            right:
                                                                _isPlayerExpanded
                                                                ? 20
                                                                : 12,
                                                            bottom:
                                                                _isPlayerExpanded
                                                                ? 95 + extraBottom
                                                                : 48,
                                                            width:
                                                                _isPlayerExpanded
                                                                ? 40
                                                                : 30,
                                                            height:
                                                                _isPlayerExpanded
                                                                ? 40
                                                                : 30,
                                                            child: StreamBuilder<LoopMode>(
                                                              stream:
                                                                  (_audioHandler
                                                                          as MyAudioHandler)
                                                                      .loopModeStream,
                                                              initialData:
                                                                  LoopMode.all,
                                                              builder: (context, snapshot) {
                                                                final loopMode =
                                                                    snapshot
                                                                        .data ??
                                                                    LoopMode
                                                                        .all;
                                                                final isLooping =
                                                                    loopMode ==
                                                                    LoopMode
                                                                        .one;
                                                                return HyperOSRepeatButton(
                                                                  isLooping:
                                                                      isLooping,
                                                                  onTap: () {
                                                                    (_audioHandler
                                                                            as MyAudioHandler)
                                                                        .toggleLoopMode();
                                                                  },
                                                                  gradientColors:
                                                                      smoothThemeColors,
                                                                  size:
                                                                      _isPlayerExpanded
                                                                      ? 30
                                                                      : 20,
                                                                );
                                                              },
                                                            ),
                                                          ),

                                                          AnimatedPositioned(
                                                            duration:
                                                                transitionDuration,
                                                            curve:
                                                                transitionCurve,
                                                            left: 20,
                                                            right: 20,
                                                            bottom:
                                                                _isPlayerExpanded
                                                                ? 25 + extraBottom
                                                                : 6,
                                                            child: StreamBuilder<PositionData>(
                                                              stream:
                                                                  _positionDataStream,
                                                              initialData:
                                                                  PositionData(
                                                                    Duration
                                                                        .zero,
                                                                    Duration
                                                                        .zero,
                                                                    Duration
                                                                        .zero,
                                                                  ),
                                                              builder:
                                                                  (
                                                                    context,
                                                                    posSnapshot,
                                                                  ) {
                                                                    final position =
                                                                        posSnapshot
                                                                            .data!
                                                                            .position;
                                                                    final duration =
                                                                        posSnapshot
                                                                            .data!
                                                                            .duration;
                                                                    return HyperOSSlider(
                                                                      position:
                                                                          position,
                                                                      duration:
                                                                          duration,
                                                                      onSeek: (target) {
                                                                        _audioHandler.seek(
                                                                          target,
                                                                        );
                                                                      },
                                                                      gradientColors:
                                                                          smoothThemeColors,
                                                                    );
                                                                  },
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),

                                AnimatedPositioned(
                                  duration: transitionDuration,
                                  curve: transitionCurve,
                                  bottom: _isPlayerExpanded ? -navBarHeight : 0,
                                  left: 0,
                                  right: 0,
                                  height: navBarHeight,
                                  child: AnimatedOpacity(
                                    duration: transitionDuration,
                                    opacity: _isPlayerExpanded ? 0.0 : 1.0,
                                    child: Theme(
                                      data: Theme.of(context).copyWith(
                                        splashColor: Colors.transparent,
                                        highlightColor: Colors.transparent,
                                      ),

                                      // --- DÉBUT DE LA NOUVELLE BARRE DE NAVIGATION ---
                                      child: StreamBuilder<User?>(
                                        stream: FirebaseAuth.instance
                                            .authStateChanges(),
                                        builder: (context, authSnapshot) {
                                          final user = authSnapshot.data;

                                          return ValueListenableBuilder<
                                            String?
                                          >(
                                            valueListenable:
                                                userProfileImageNotifier,
                                            builder: (context, localImagePath, _) {
                                              // Logique de l'icône (Locale > Google > Défaut)
                                              final hasLocalImage =
                                                  localImagePath != null &&
                                                  localImagePath.isNotEmpty &&
                                                  File(
                                                    localImagePath,
                                                  ).existsSync();
                                              final hasGoogleImage =
                                                  user != null &&
                                                  user.photoURL != null;

                                              Widget accountIcon;
                                              if (hasLocalImage) {
                                                accountIcon = ClipOval(
                                                  child: Image.file(
                                                    File(localImagePath),
                                                    width: 24,
                                                    height: 24,
                                                    fit: BoxFit.cover,
                                                  ),
                                                );
                                              } else if (hasGoogleImage) {
                                                accountIcon = ClipOval(
                                                  child: Image.network(
                                                    user.photoURL!,
                                                    width: 24,
                                                    height: 24,
                                                    fit: BoxFit.cover,
                                                  ),
                                                );
                                              } else {
                                                accountIcon = const Icon(
                                                  CupertinoIcons
                                                      .person_alt_circle,
                                                );
                                              }

                                              return BottomNavigationBar(
                                                backgroundColor:
                                                    Colors.transparent,
                                                elevation: 0,
                                                selectedItemColor: Colors.white,
                                                unselectedItemColor:
                                                    Colors.white54,
                                                selectedFontSize: 11,
                                                unselectedFontSize: 11,
                                                type: BottomNavigationBarType
                                                    .fixed,
                                                currentIndex: _currentIndex,
                                                onTap: (index) {
                                                  FocusScope.of(
                                                    context,
                                                  ).unfocus();
                                                  setState(() {
                                                    _currentIndex = index;
                                                  });
                                                  _mainPageController
                                                      .animateToPage(
                                                        index,
                                                        duration:
                                                            const Duration(
                                                              milliseconds: 400,
                                                            ),
                                                        curve: Curves
                                                            .fastOutSlowIn,
                                                      );
                                                },
                                                items: [
                                                  const BottomNavigationBarItem(
                                                    icon: Icon(
                                                      CupertinoIcons.search,
                                                    ),
                                                    label: 'Recherche',
                                                  ),
                                                  const BottomNavigationBarItem(
                                                    icon: Icon(
                                                      CupertinoIcons
                                                          .person_2_fill,
                                                    ),
                                                    label: 'Artistes',
                                                  ),
                                                  const BottomNavigationBarItem(
                                                    icon: Icon(
                                                      CupertinoIcons.music_note,
                                                    ),
                                                    label: 'Musiques',
                                                  ),
                                                  const BottomNavigationBarItem(
                                                    icon: Icon(
                                                      CupertinoIcons.heart_fill,
                                                    ),
                                                    label: 'Bibliothèque',
                                                  ),
                                                  // 👇 L'ICÔNE DYNAMIQUE EST ICI 👇
                                                  BottomNavigationBarItem(
                                                    icon: accountIcon,
                                                    label: 'Compte',
                                                  ),
                                                ],
                                              );
                                            },
                                          );
                                        },
                                      ),

                                      // --- FIN DE LA NOUVELLE BARRE DE NAVIGATION ---
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
