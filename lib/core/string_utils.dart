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
