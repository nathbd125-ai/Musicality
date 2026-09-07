import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:musicality/core/globals.dart';

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

