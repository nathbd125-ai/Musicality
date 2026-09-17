import 'dart:math';
import 'package:musicality/core/api_config.dart';

final RegExp _parenthesesRegex = RegExp(r'\s*\(.*?\)');
final RegExp _spacesRegex = RegExp(r'\s+');
final RegExp _dashesRegex = RegExp(r'[\u2010-\u2015\u2212]');
final RegExp _trimUnderscoresRegex = RegExp(r'^_+|_+$');
final RegExp _multiUnderscoresRegex = RegExp(r'_+');

final RegExp _featParensRegex = RegExp(r'\s*[(\[]f(?:ea)?t\.?\s+[^)\]]+[)\]]', caseSensitive: false);
final RegExp _featEndRegex = RegExp(r'\s+f(?:ea)?t\.?\s+.*', caseSensitive: false);

final RegExp _baseIdRegex = RegExp(r'\.flac|\.mp3|\.wav', caseSensitive: false);
final RegExp _featAmpRegex = RegExp(r'\s+feat\.?\s+', caseSensitive: false);
final RegExp _tylerRegex = RegExp(r'tyler[\s,&]+the creator', caseSensitive: false);
final RegExp _artistSeparatorRegex = RegExp(
  r'\s+&\s+|\s+et\s+|\s+[xX×]\s+|\s+(?:feat\.?|ft\.?|featuring)\s+|\s+(?:with|avec)\s+|[,;/]',
  caseSensitive: false,
);
final RegExp _trimSurroundingQuotesRegex = RegExp(r'^[\(\[\{"\s]+|[\)\]\}"\s]+$');
final RegExp _extractFeatParensRegex = RegExp(r'\s*[(\[]\s*f(?:ea)?t\.?\s+([^()\]]+)[)\]]', caseSensitive: false);
final RegExp _extractFeatEndRegex = RegExp(r'\s+f(?:ea)?t\.?\s+(.*)', caseSensitive: false);

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
      .replaceAll(_parenthesesRegex, '') // Enlève (The Moonlight Edition), etc.
      .replaceAll('.', '')
      .replaceAll('!', '')
      .replaceAll('?', '')
      .replaceAll(':', '')
      .replaceAll("'", "")
      .replaceAll('’', '')
      .toLowerCase()
      .trim()
      .replaceAll(_spacesRegex, '_')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('à', 'a')
      .replaceAll('ğ', 'g')
      .replaceAll('Ğ', 'g')
      .replaceAll(_dashesRegex, '-')
      .replaceAll(_trimUnderscoresRegex, '')
      .replaceAll(_multiUnderscoresRegex, '_');
}

String cleanTitle(String title) {
  // Enlève "(feat. Artiste)" ou "[ft. Artiste]"
  String cleaned = title.replaceAll(
    _featParensRegex,
    '',
  );
  // Enlève " feat. Artiste" (sans parenthèses) à la fin
  cleaned = cleaned.replaceAll(
    _featEndRegex,
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
      .replaceAll(_baseIdRegex, '');
}

String normalizeSongId(String rawId) {
  final base = getBaseId(rawId);
  return '${ApiConfig.baseUrl}/$base.flac';
}

String formatArtist(String? artist) {
  if (artist == null || artist.isEmpty) return 'Inconnu';
  return artist.replaceAll(
    _featAmpRegex,
    ' & ',
  );
}

List<String> extractArtists(String? rawArtist) {
  if (rawArtist == null || rawArtist.isEmpty) return ['Inconnu'];

  String artist = rawArtist;
  if (artist.toLowerCase().contains('tyler') && artist.toLowerCase().contains('creator')) {
    artist = artist.replaceAll(_tylerRegex, 'Tyler The Creator');
  }

  // Regex de séparation multi-artistes (duos, featurings, collaborations) :
  final parts = artist.split(_artistSeparatorRegex);
  final List<String> result = [];

  for (var part in parts) {
    var clean = part
        .replaceAll(_trimSurroundingQuotesRegex, '')
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

String extractEnrichedArtist(String rawTitle, String rawArtist) {
  final match = _extractFeatParensRegex.firstMatch(rawTitle)
      ?? _extractFeatEndRegex.firstMatch(rawTitle);
  if (match != null) {
    final featArtist = match.group(1)?.trim();
    if (featArtist != null && featArtist.isNotEmpty && !rawArtist.toLowerCase().contains(featArtist.toLowerCase())) {
      return '$rawArtist & $featArtist';
    }
  }
  return rawArtist;
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

/// Calcule la distance d'édition de Levenshtein entre deux chaînes (optimisé 2-lignes O(min(m,n)) mémoire).
int levenshteinDistance(String s1, String s2) {
  if (s1 == s2) return 0;
  if (s1.isEmpty) return s2.length;
  if (s2.isEmpty) return s1.length;

  List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
  List<int> v1 = List<int>.filled(s2.length + 1, 0);

  for (int i = 0; i < s1.length; i++) {
    v1[0] = i + 1;
    for (int j = 0; j < s2.length; j++) {
      final int cost = (s1.codeUnitAt(i) == s2.codeUnitAt(j)) ? 0 : 1;
      v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce(min);
    }
    for (int j = 0; j <= s2.length; j++) {
      v0[j] = v1[j];
    }
  }
  return v1[s2.length];
}

final RegExp _wordSplitRegex = RegExp(r'[\s\-_\.,;:/\(\)\[\]]+');

/// Calcule le score de pertinence d'une recherche avec tolérance aux fautes (Fuzzy Search).
/// Renvoie 0 si aucune correspondance n'est trouvée, ou un score positif (>0) trié par pertinence.
int calculateSearchScore({
  required String title,
  required String? artist,
  required String? album,
  required String query,
}) {
  final cleanQuery = normalizeString(query);
  if (cleanQuery.isEmpty) return 0;

  final normTitle = normalizeString(title);
  final normArtist = normalizeString(artist ?? '');
  final normAlbum = normalizeString(album ?? '');

  // 1. Détection ultra-rapide par correspondance directe (Bonus absolu)
  if (normTitle == cleanQuery) return 300;
  if (normTitle.startsWith(cleanQuery)) return 250;
  if (normArtist == cleanQuery) return 220;
  if (normArtist.startsWith(cleanQuery)) return 200;
  if (normTitle.contains(cleanQuery)) return 180;
  if (normArtist.contains(cleanQuery)) return 150;
  if (normAlbum.contains(cleanQuery)) return 120;

  // 2. Recherche multi-termes et tolérance aux fautes (Fuzzy Search)
  final queryTokens = cleanQuery.split(_wordSplitRegex).where((s) => s.isNotEmpty).toList();
  if (queryTokens.isEmpty) return 0;

  final titleWords = normTitle.split(_wordSplitRegex).where((s) => s.isNotEmpty).toList();
  final artistWords = normArtist.split(_wordSplitRegex).where((s) => s.isNotEmpty).toList();
  final albumWords = normAlbum.split(_wordSplitRegex).where((s) => s.isNotEmpty).toList();

  int totalScore = 0;

  for (final qToken in queryTokens) {
    int bestTokenScore = 0;

    // A. Correspondance dans les mots du titre
    for (final tWord in titleWords) {
      if (tWord == qToken) {
        bestTokenScore = max(bestTokenScore, 90);
      } else if (tWord.startsWith(qToken)) {
        bestTokenScore = max(bestTokenScore, 75);
      } else if (tWord.contains(qToken)) {
        bestTokenScore = max(bestTokenScore, 60);
      } else if (qToken.length >= 4) {
        final dist = levenshteinDistance(tWord, qToken);
        if (dist == 1) {
          bestTokenScore = max(bestTokenScore, 55);
        } else if (dist == 2 && qToken.length >= 7) {
          bestTokenScore = max(bestTokenScore, 40);
        }
      }
    }

    // B. Correspondance dans les mots de l'artiste
    for (final aWord in artistWords) {
      if (aWord == qToken) {
        bestTokenScore = max(bestTokenScore, 80);
      } else if (aWord.startsWith(qToken)) {
        bestTokenScore = max(bestTokenScore, 70);
      } else if (aWord.contains(qToken)) {
        bestTokenScore = max(bestTokenScore, 50);
      } else if (qToken.length >= 4) {
        final dist = levenshteinDistance(aWord, qToken);
        if (dist == 1) {
          bestTokenScore = max(bestTokenScore, 50);
        } else if (dist == 2 && qToken.length >= 7) {
          bestTokenScore = max(bestTokenScore, 35);
        }
      }
    }

    // C. Correspondance dans l'album
    for (final albWord in albumWords) {
      if (albWord == qToken || albWord.startsWith(qToken)) {
        bestTokenScore = max(bestTokenScore, 40);
      }
    }

    // Chaque mot saisi doit correspondre au moins partiellement
    if (bestTokenScore == 0) {
      return 0;
    }
    totalScore += bestTokenScore;
  }

  return totalScore;
}

