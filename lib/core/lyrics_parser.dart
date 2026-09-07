import 'package:musicality/core/models.dart';

class LyricsParser {
  static List<LyricLine> parse(String content) {
    if (content.contains('<tt') || content.contains('xmlns:itunes') || content.contains('xmlns="http://www.w3.org/ns/ttml"')) {
      return _parseTtml(content);
    }
    return _parseLrc(content);
  }

  /// Parser officiel pour les fichiers Apple Music TTML (Timed Text Markup Language)
  static List<LyricLine> _parseTtml(String content) {
    final List<LyricLine> lines = [];
    final RegExp pRegExp = RegExp(r'<p\b([^>]*)>(.*?)</p>', dotAll: true);
    final RegExp spanRegExp = RegExp(r'<span\b([^>]*)>(.*?)</span>', dotAll: true);
    final RegExp attrBegin = RegExp(r'begin="([^"]+)"');
    final RegExp attrEnd = RegExp(r'end="([^"]+)"');

    Duration parseTtmlTime(String timeStr) {
      final clean = timeStr.trim();
      if (clean.endsWith('s')) {
        final sec = double.tryParse(clean.replaceAll('s', '')) ?? 0.0;
        return Duration(milliseconds: (sec * 1000).round());
      }
      if (clean.endsWith('ms')) {
        final ms = int.tryParse(clean.replaceAll('ms', '')) ?? 0;
        return Duration(milliseconds: ms);
      }
      final parts = clean.split(':');
      if (parts.length == 3) {
        final hours = int.tryParse(parts[0]) ?? 0;
        final mins = int.tryParse(parts[1]) ?? 0;
        final secs = double.tryParse(parts[2]) ?? 0.0;
        final totalMs = (hours * 3600 + mins * 60 + secs) * 1000;
        return Duration(milliseconds: totalMs.round());
      } else if (parts.length == 2) {
        final mins = int.tryParse(parts[0]) ?? 0;
        final secs = double.tryParse(parts[1]) ?? 0.0;
        final totalMs = (mins * 60 + secs) * 1000;
        return Duration(milliseconds: totalMs.round());
      }
      return Duration.zero;
    }

    final pMatches = pRegExp.allMatches(content);
    for (final pMatch in pMatches) {
      final pAttrs = pMatch.group(1) ?? '';
      final pInner = pMatch.group(2) ?? '';

      final beginMatch = attrBegin.firstMatch(pAttrs);
      if (beginMatch == null) continue;
      final lineTime = parseTtmlTime(beginMatch.group(1)!);

      final endMatch = attrEnd.firstMatch(pAttrs);
      final lineEndTime = endMatch != null ? parseTtmlTime(endMatch.group(1)!) : null;

      final spanMatches = spanRegExp.allMatches(pInner).toList();
      final List<LyricWord> words = [];

      for (final sMatch in spanMatches) {
        final sAttrs = sMatch.group(1) ?? '';
        final sText = sMatch.group(2)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
        if (sText.isEmpty) continue;

        final sBeginMatch = attrBegin.firstMatch(sAttrs);
        final sEndMatch = attrEnd.firstMatch(sAttrs);

        if (sBeginMatch != null && sEndMatch != null) {
          final wStart = parseTtmlTime(sBeginMatch.group(1)!);
          final wEnd = parseTtmlTime(sEndMatch.group(1)!);
          words.add(LyricWord(text: sText, start: wStart, end: wEnd));
        }
      }

      final cleanLineText = _fixAccentSpacing(pInner.replaceAll(RegExp(r'<[^>]+>'), '')).trim();
      if (cleanLineText.isNotEmpty && !_isCreditLine(cleanLineText)) {
        lines.add(LyricLine(
          time: lineTime,
          text: cleanLineText,
          endTime: lineEndTime ?? (words.isNotEmpty ? words.last.end : lineTime + const Duration(seconds: 3)),
          words: words,
        ));
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  /// Détecte et élimine les lignes de crédits parasites (ex: "Written by ...", "by Nathan", "Lyrics by ...", "Romeo Santos - Imitadora", "AFRO TRAP Part.7（La Puissance ）-MHD")
  static bool _isCreditLine(String text, [Duration? lineTime]) {
    final clean = text.trim().toLowerCase();
    if (clean.isEmpty) return true;

    // 1. Détection des expressions de crédits universelles
    final creditPatterns = [
      RegExp(r'\b(?:written|lyrics?|synced?|sync|timing|composed|arranged|produced|recorded|mixed|mastered)\s*(?:by|\?|\:|\-)', caseSensitive: false),
      RegExp(r'\b(?:paroles?|auteur|compositeur|chanteur|musique|arrangements?|mixage|enregistrement|studio)\s*(?:par|\:|\-)', caseSensitive: false),
      RegExp(r'\b(?:letra|compositor|productor)\s*(?:por|\:|\-)', caseSensitive: false),
      RegExp(r'\b(?:source|karaoke|credits?|traduction|translated)\s*(?:\:|\-)', caseSensitive: false),
      RegExp(r'\b(?:qq|wechat|telegram|instagram|twitter|tiktok)\s*(?:\:|\-)', caseSensitive: false),
      RegExp(r'(?:rentanadviser\.com|musixmatch|genius\.com|lrclib|netease|spotify|apple\s*music)', caseSensitive: false),
      // Producteurs / Beatmakers / Tags de prod
      RegExp(r'\b(?:prod|production|producer|beat|beatmaker|instru|instrumental)\s*(?:by|\?|\:|\.|\-)', caseSensitive: false),
      RegExp(r'\b(?:dsk\s+on\s+the\s+beat|dsk)\b', caseSensitive: false),
      // Crédits en chinois fréquents sur NetEase
      RegExp(r'(?:作词|作曲|编曲|制作|录音|混音|吉他|贝斯|鼓|和声|母带|发行|企划|统筹)'),
    ];

    for (final pattern in creditPatterns) {
      if (pattern.hasMatch(clean)) return true;
    }

    // 2. Détecte "by quelqu'un", "par: ...", "sync: ..."
    if (clean.startsWith('by ') || clean.startsWith('by: ') || clean.startsWith('par: ') || clean.startsWith('sync: ')) {
      if (clean.split(RegExp(r'\s+')).length <= 6) {
        return true;
      }
    }

    // 3. Détection des métadonnées et titres / artistes en intro (<= 15 secondes)
    if (lineTime != null && lineTime.inSeconds <= 15) {
      // Préfixes avec deux points (ex: "Auteur : ...", "Artiste : ...", "Titre : ...")
      if (clean.contains(':') || clean.contains('：')) {
        final prefix = clean.split(RegExp(r'[:：]')).first.trim();
        if (prefix.split(RegExp(r'\s+')).length <= 3) {
          return true;
        }
      }

      // Format titre/artiste avec séparateur (ex: "AFRO TRAP Part.7（La Puissance ）-MHD", "MHD - Afro Trap")
      if (RegExp(r'[-–—|~]').hasMatch(clean)) {
        final words = clean.split(RegExp(r'\s+'));
        if (words.length <= 10) {
          return true;
        }
      }

      // En-têtes spécifiques comme "afro trap part. 7" ou "part. 7" sans paroles réelles
      if (clean.contains('afro trap') && clean.split(RegExp(r'\s+')).length <= 8) {
        return true;
      }
    }

    return false;
  }

  
  static String _fixAccentSpacing(String s) {
    const letters = r'[a-zA-ZáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ]';
    // Accents pouvant terminer un mot (ex: carré, aimé, liberté, papá, corazón)
    const wordEndingAccents = r'[éÉèÈáÁóÓ]';
    // Accents strictement internes ne terminant jamais un mot en français/espagnol (ex: français, connaître, tête, fête, bâtard, mañana)
    const internalAccents = r'[çÇñÑêÊëËîÎïÏûÛüÜôÔâÂ]';
    const allAccents = r'[çÇéÉèÈêÊëËîÎïÏùÙûÛüÜñÑíÍúÚáÁóÓâÂôÔ]';
    const initialAccents = r'[éÉèÈêÊëË]';

    String old;
    do {
      old = s;

      // 1. Ponctuation inversée espagnole : supprime l'espace après ¡ ou ¿
      s = s.replaceAllMapped(
        RegExp(r'([¡¿])\s+'),
        (m) => m[1]!,
      );

      // 2. 'l à' ou 'L à' -> 'là' ou 'Là' (avec ou sans balises, avec ou sans mot collé après)
      // Ex: "l à" -> "là", "l <tag>à" -> "l<tag>à", "l <tag>à<tag>que" -> "l<tag>à <tag>que", "làque" -> "là que"
      s = s.replaceAllMapped(
        RegExp(r'(^|[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ])([Ll])(?:\s+(<\d+:\d+(?:\.\d+)?>)?\s*|\s*(<\d+:\d+(?:\.\d+)?>)\s*)([àÀ])(?:\s*(<\d+:\d+(?:\.\d+)?>)?\s*(' + letters + r'+)|(?=[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ]|$))'),
        (m) {
          final prefix = m[1]!;
          final l = m[2]!;
          final tag1 = m[3] ?? m[4] ?? '';
          final a = m[5]!;
          final tag2 = m[6] ?? '';
          final nextWord = m[7];
          if (nextWord != null && nextWord.isNotEmpty) {
            return '$prefix$l$tag1$a $tag2$nextWord';
          }
          return '$prefix$l$tag1$a';
        },
      );

      // 2b. Mots tronqués connus devant 'à' (déjà, voilà, delà, etc.)
      s = s.replaceAllMapped(
        RegExp(r'(^|[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ])(d[eé]j|voil|del|de[cç]|hol|jusqu)(?:\s+(<\d+:\d+(?:\.\d+)?>)?\s*|\s*(<\d+:\d+(?:\.\d+)?>)\s*)([àÀ])(?=[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ]|$)'),
        (m) => '${m[1]}${m[2]}${m[3] ?? m[4] ?? ""}${m[5]}',
      );

      // 2c. 'à' isolé collé au mot suivant avec ou sans balise temporelle (ex: "àla" -> "à la", "à<tag>la" -> "à <tag>la")
      s = s.replaceAllMapped(
        RegExp(r'(^|[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ])([àÀ])\s*(<\d+:\d+(?:\.\d+)?>)?(' + letters + r'+)'),
        (m) => '${m[1]}${m[2]} ${m[3] ?? ""}${m[4]}',
      );

      // 2d. 'là' collé au mot suivant sans espace (ex: "làque" -> "là que", "là<tag>que" -> "là <tag>que")
      s = s.replaceAllMapped(
        RegExp(r'(^|[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ])([Ll]à)\s*(<\d+:\d+(?:\.\d+)?>)?(' + letters + r'+)'),
        (m) => '${m[1]}${m[2]} ${m[3] ?? ""}${m[4]}',
      );

      // 2e. "O ù" -> "Où", "d'o ù" -> "d'où", avec ou sans mot collé après (ex: "O <tag>ù<tag>sont" -> "O<tag>ù <tag>sont", "Oùsont" -> "Où sont")
      s = s.replaceAllMapped(
        RegExp(r'(^|[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ])([Oo])(?:\s+(<\d+:\d+(?:\.\d+)?>)?\s*|\s*(<\d+:\d+(?:\.\d+)?>)\s*)([ùÙ])(?:\s*(<\d+:\d+(?:\.\d+)?>)?\s*(' + letters + r'+)|(?=[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ]|$))'),
        (m) {
          final prefix = m[1]!;
          final o = m[2]!;
          final tag1 = m[3] ?? m[4] ?? '';
          final u = m[5]!;
          final tag2 = m[6] ?? '';
          final nextWord = m[7];
          if (nextWord != null && nextWord.isNotEmpty) {
            return '$prefix$o$tag1$u $tag2$nextWord';
          }
          return '$prefix$o$tag1$u';
        },
      );

      // 2f. 'où' / 'Où' collé au mot suivant sans espace (ex: "Oùsont" -> "Où sont", "oùtu" -> "où tu")
      s = s.replaceAllMapped(
        RegExp(r'(^|[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ])([Oo]ù)\s*(<\d+:\d+(?:\.\d+)?>)?(' + letters + r'+)'),
        (m) => '${m[1]}${m[2]} ${m[3] ?? ""}${m[4]}',
      );

      // 3. Suffixes d'accents espagnols (ex: "coraz ón" -> "corazón", "est ás" -> "estás")
      s = s.replaceAllMapped(
        RegExp(r'(' + letters + r'+)\s*(<\d+:\d+(?:\.\d+)?>)?\s+(ón|án|én|ás|és|ía|ías|ió)(?=[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ]|$)'),
        (m) => '${m[1]}${m[2] ?? ""}${m[3]}',
      );

      // 3b. Gérondifs et enclitiques espagnols (ex: "mirá ndote" -> "mirándote", "mir á ndote" -> "mirándote", "dicié ndote" -> "diciéndote")
      s = s.replaceAllMapped(
        RegExp(r'(' + letters + r'+)\s*(<\d+:\d+(?:\.\d+)?>)?\s*([áéíóúÁÉÍÓÚ])\s*(<\d+:\d+(?:\.\d+)?>)?\s*(ndo(?:te|me|se|nos|os|les?|los?|las?)?)(?=[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ]|$)'),
        (m) => '${m[1]}${m[2] ?? ""}${m[3]}${m[4] ?? ""}${m[5]}',
      );
      s = s.replaceAllMapped(
        RegExp(r'(' + letters + r'+[áéíóúÁÉÍÓÚ])\s*(<\d+:\d+(?:\.\d+)?>)?\s+(ndo(?:te|me|se|nos|os|les?|los?|las?)?)(?=[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ]|$)'),
        (m) => '${m[1]}${m[2] ?? ""}${m[3]}',
      );

      // 4. Accent isolé en FIN de mot (ex: "carr é VIP" -> "carré VIP", "carr <tag>é VIP" -> "carr<tag>é VIP")
      // IMPORTANT : Ne mange JAMAIS le mot suivant grâce au lookahead positif (espace, balise ou ponctuation)
      s = s.replaceAllMapped(
        RegExp(r'(' + letters + r'{2,})\s*(<\d+:\d+(?:\.\d+)?>)?\s*(' + wordEndingAccents + r')(?=[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ]|$)'),
        (m) => '${m[1]}${m[2] ?? ""}${m[3]}',
      );

      // 5. Caractère accentué INTERNE isolé (ç, ñ, ê, ë, î, ï, û, ü, ô, â) entre deux morceaux d'un mot
      // (ex: "fran ç ais" -> "français", "conna î tre" -> "connaître", "t ê te" -> "tête", "b â tards" -> "bâtards")
      // IMPORTANT : exige un espace ou balise des DEUX côtés de l'accent pour ne jamais manger les espaces entre mots
      s = s.replaceAllMapped(
        RegExp(r'(' + letters + r'+)(?:\s+(<\d+:\d+(?:\.\d+)?>)?\s*|(<\d+:\d+(?:\.\d+)?>)\s*)(' + internalAccents + r')(?:\s*(<\d+:\d+(?:\.\d+)?>)?\s+|\s*(<\d+:\d+(?:\.\d+)?>))(' + letters + r'+)'),
        (m) {
          final g1 = m[1]!;
          final tag1 = m[2] ?? m[3] ?? '';
          final accent = m[4]!;
          final tag2 = m[5] ?? m[6] ?? '';
          final g2 = m[7]!;

          // Si l'accent est 'ç' et que la suite est 'a', c'est le pronom 'ça', ne pas coller au mot précédent !
          if (accent.toLowerCase() == 'ç' && g2.toLowerCase() == 'a') {
            return '$g1 $tag1$accent$tag2$g2';
          }
          return '$g1$tag1$accent$tag2$g2';
        },
      );

      // 5b. Décollage des pronoms collés par erreur ("commeça" -> "comme ça", "règlereraça" -> "règlerera ça", "te-têpartout" -> "te-tê partout")
      s = s.replaceAllMapped(
        RegExp(r'\b(règlerera|règlera|comme|pour|avec|faire|fait|dis|dit|vois|voit)\s*(<\d+:\d+(?:\.\d+)?>)?\s*ça\b', caseSensitive: false),
        (m) => '${m[1]} ${m[2] ?? ""}ça',
      );
      s = s.replaceAllMapped(
        RegExp(r'\b(te-tê|te-te|te-té)\s*(<\d+:\d+(?:\.\d+)?>)?\s*(partout)\b', caseSensitive: false),
        (m) => 'te-tê ${m[2] ?? ""}${m[3]}',
      );
      s = s.replaceAllMapped(
        RegExp(r'(^|[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ])([Oo]ù)\s*(<\d+:\d+(?:\.\d+)?>)?\s*(sont)\b', caseSensitive: false),
        (m) => '${m[1]}${m[2]} ${m[3] ?? ""}${m[4]}',
      );
      s = s.replaceAllMapped(
        RegExp(r'(^|[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ])([Ll]à)\s*(<\d+:\d+(?:\.\d+)?>)?\s*(que)\b', caseSensitive: false),
        (m) => '${m[1]}${m[2]} ${m[3] ?? ""}${m[4]}',
      );

      // 7. Consonne isolée devant un accent et la suite du mot (ex: "d é faite" -> "défaite", "d è che" -> "dèche")
      // IMPORTANT : exige obligatoirement un espace ou balise entre la consonne et l'accent !
      s = s.replaceAllMapped(
        RegExp(r'(^|[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ])([b-df-hj-np-tv-zB-DF-HJ-NP-TV-Z])(?:\s+(<\d+:\d+(?:\.\d+)?>)?\s*|(<\d+:\d+(?:\.\d+)?>)\s*)(' + allAccents + r')\s*(<\d+:\d+(?:\.\d+)?>)?\s*(' + letters + r'{2,})'),
        (m) => '${m[1]}${m[2]}${m[3] ?? m[4] ?? ""}${m[5]}${m[6] ?? ""}${m[7]}',
      );

      // 8. Accent isolé en début de mot avant au moins 2 lettres (ex: "é quipe" -> "équipe")
      s = s.replaceAllMapped(
        RegExp(r'(^|[^\wáàâäãéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ])(' + initialAccents + r')\s*(<\d+:\d+(?:\.\d+)?>)?\s*(' + letters + r'{2,})'),
        (m) => '${m[1]}${m[2]}${m[3] ?? ""}${m[4]}',
      );
    } while (old != s);

    return s;
  }

  static String _sanitizeAccents(String text) {
    // 1. Correction des caractères '?' corrompus à l'intérieur des mots (ex: l?s bacs -> les bacs, f?at -> feat)
    text = text
        .replaceAll(RegExp(r'\bl\?s\b', caseSensitive: false), 'les')
        .replaceAll(RegExp(r'\bf\?at\b', caseSensitive: false), 'feat')
        .replaceAll(RegExp(r'\bd\?s\b', caseSensitive: false), 'des')
        .replaceAll(RegExp(r'\bm\?me\b', caseSensitive: false), 'même')
        .replaceAll(RegExp(r'\btr\?s\b', caseSensitive: false), 'très')
        .replaceAll(RegExp(r'\bapr\?s\b', caseSensitive: false), 'après')
        .replaceAll(RegExp(r'\bd\?j[àa\?]\b', caseSensitive: false), 'déjà')
        .replaceAll(RegExp(r'(^|\s)\?a(?=\s|[.,!?]|$)', caseSensitive: false), r'$1ça')
        .replaceAllMapped(
          RegExp(r'\b([cdjlmstn]|qu)\?([aeiouyéèêh])', caseSensitive: false),
          (m) => "${m[1]}'${m[2]}",
        );

    // 2. Séparation des mots d'argot/verlan se terminant par une apostrophe collée à un article (ex: "tej'la" -> "tej' la")
    text = text.replaceAllMapped(
      RegExp(r"\b(tej|kiff|taff|bénéf|grave)'\s*(<\d+:\d+(?:\.\d+)?>)?\s*(la|le|les|des|un|une|du)\b", caseSensitive: false),
      (m) => "${m[1]}' ${m[2] ?? ''}${m[3]}",
    );

    // 2c. Séparation de "carré" et "VIP" avec éventuelles balises (ex: "carr <tag>é<tag>V I P" -> "carré <tag>VIP")
    text = text.replaceAllMapped(
      RegExp(
        r'\b(carr[eé\ufffd]|carr\s*(?:<\d+:\d+(?:\.\d+)?>)?\s*[eé\ufffd])\s*(<\d+:\d+(?:\.\d+)?>)?\s*(?:V\s*(?:<\d+:\d+(?:\.\d+)?>)?\s*I\s*(?:<\d+:\d+(?:\.\d+)?>)?\s*P|VIP)\b',
        caseSensitive: false,
      ),
      (m) => 'carré ${m[2] ?? ""}VIP',
    );

    // 2d. Gérondifs espagnols avec pronoms enclitiques (ex: "mirá ndote" -> "mirándote", "mir á ndote" -> "mirándote")
    text = text.replaceAllMapped(
      RegExp(r'\b([a-zA-ZáéíóúÁÉÍÓÚ]+[áéíóúÁÉÍÓÚ])\s*(<\d+:\d+(?:\.\d+)?>)?\s*(ndo(?:te|me|se|nos|os|les?|los?|las?)?)\b', caseSensitive: false),
      (m) => '${m[1]}${m[2] ?? ""}${m[3]}',
    );

    // Remplacement explicite pour les corruptions d'accentuation en français
    text = text
        .replaceAll(RegExp(r'\br[\ufffdéè\?]glera\s*[\ufffd\?ea]?\s*a\b', caseSensitive: false), 'règlerera ça')
        .replaceAll(RegExp(r'\br[\ufffdéè\?]glerera\s*[\ufffd\?ea]?\s*a\b', caseSensitive: false), 'règlerera ça')
        .replaceAll(RegExp(r'\br[\ufffdéè\?]gler(a|era)ça\b', caseSensitive: false), 'règlerera ça')
        .replaceAll(RegExp(r'\bte-t[\ufffd\?eéê]partout\b', caseSensitive: false), 'te-tê partout')
        .replaceAll(RegExp(r'\bte-t[\ufffd\?eé]\b', caseSensitive: false), 'te-tê')
        .replaceAll(RegExp(r'(^|\s)[\ufffd\?]a(?=\s|[.,!?]|$)', caseSensitive: false), r'$1ça');

    if (!text.contains('\ufffd')) return text;
    return text
        // Français
        .replaceAll("jusqu'\ufffd", "jusqu'à")
        .replaceAll(" \ufffd ", " à ")
        .replaceAll("o\ufffd ", "où ")
        .replaceAll("O\ufffd ", "Où ")
        .replaceAll("f\ufffdch\ufffd", "fâché")
        .replaceAll("m\ufffdme", "même")
        .replaceAll("tra\ufffdnait", "traînait")
        .replaceAll("pr\ufffdsenter", "présenter")
        .replaceAll("d\ufffdnigr\ufffd", "dénigré")
        .replaceAll("v\ufffdrit\ufffd", "vérité")
        .replaceAll("ch\ufffdrie", "chérie")
        .replaceAll("sal\ufffde", "salée")
        .replaceAll("sal\ufffd", "salé")
        .replaceAll("ill\ufffdgal", "illégal")
        .replaceAll("baign\ufffd", "baigné")
        .replaceAll("deal\ufffd", "dealé")
        .replaceAll("d\ufffdploy\ufffd", "déployé")
        .replaceAll("prohib\ufffds", "prohibés")
        .replaceAll("conna\ufffdtre", "connaître")
        .replaceAll("fran\ufffdais", "français")
        .replaceAll("t\ufffdte", "tête")
        .replaceAll("b\ufffdtard", "bâtard")
        .replaceAll("b\ufffdtards", "bâtards")
        .replaceAll("d\ufffdche", "dèche")
        .replaceAll("d\ufffdfaite", "défaite")
        .replaceAll("miracul\ufffd", "miraculé")
        .replaceAll("carr\ufffd", "carré")
        // Espagnol
        .replaceAll("mir\ufffdndote", "mirándote")
        .replaceAll("mir\ufffd ndote", "mirándote")
        .replaceAll("coraz\ufffdn", "corazón")
        .replaceAll("canci\ufffdn", "canción")
        .replaceAll("ma\ufffdana", "mañana")
        .replaceAll("a\ufffdos", "años")
        .replaceAll("a\ufffdo", "año")
        .replaceAll("se\ufffdora", "señora")
        .replaceAll("se\ufffdor", "señor")
        .replaceAll("ni\ufffda", "niña")
        .replaceAll("ni\ufffdo", "niño")
        .replaceAll("sue\ufffdos", "sueños")
        .replaceAll("sue\ufffdo", "sueño")
        .replaceAll("est\ufffds", "estás")
        .replaceAll("est\ufffd", "está")
        .replaceAll("qui\ufffdn", "quién")
        .replaceAll("tambi\ufffdn", "también")
        .replaceAll("adi\ufffds", "adiós")
        .replaceAll("jam\ufffds", "jamás")
        .replaceAll("m\ufffds", "más")
        // Remplacement par défaut
        .replaceAll('\ufffd', 'é');
  }

  /// Parser pour fichiers LRC (standard et Enhanced LRC mot par mot <mm:ss.xx>)
  static List<LyricLine> _parseLrc(String lrcContent) {
    final List<LyricLine> parsedLines = [];
    final RegExp lineRegExp = RegExp(r'^\[(\d+):(\d+)(?:\.(\d+))?\](.*)$');
    final RegExp wordTagRegExp = RegExp(r'<(\d+):(\d+)(?:\.(\d+))?>');

    Duration parseTime(String minStr, String secStr, String? msStr) {
      final min = int.parse(minStr);
      final sec = int.parse(secStr);
      int ms = 0;
      if (msStr != null && msStr.isNotEmpty) {
        ms = int.parse(msStr);
        if (msStr.length == 2) ms *= 10;
        if (msStr.length == 1) ms *= 100;
      }
      return Duration(minutes: min, seconds: sec, milliseconds: ms);
    }

    for (var rawLine in lrcContent.split('\n')) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      final match = lineRegExp.firstMatch(trimmed);
      if (match != null) {
        final lineTime = parseTime(match.group(1)!, match.group(2)!, match.group(3));
        final rawContent = match.group(4)!.trim();
        if (rawContent.isEmpty) continue;

        final lineContent = _fixAccentSpacing(_sanitizeAccents(rawContent));

        // Marqueurs mot par mot officiels <mm:ss.xx>
        if (lineContent.contains('<') && lineContent.contains('>')) {
          final cleanText = lineContent.replaceAll(RegExp(r'<[^>]+>'), '').trim();
          if (_isCreditLine(cleanText, lineTime)) continue;

          // Découpage par vrais mots (séparés par des espaces) pour ne JAMAIS séparer les accents (ex: "é") ni les syllabes d'un même mot avec des espaces
          final List<LyricWord> words = [];
          final tokens = lineContent.split(RegExp(r'\s+'));

          for (final token in tokens) {
            final t = token.trim();
            if (t.isEmpty) continue;

            final matches = wordTagRegExp.allMatches(t).toList();
            final wordCleanText = t.replaceAll(RegExp(r'<[^>]+>'), '').trim();
            if (wordCleanText.isEmpty) continue;

            Duration wStart;
            if (matches.isNotEmpty) {
              final first = matches.first;
              wStart = parseTime(first.group(1)!, first.group(2)!, first.group(3));
            } else {
              wStart = lineTime;
            }

            words.add(LyricWord(
              text: wordCleanText,
              start: wStart,
              end: wStart + const Duration(milliseconds: 300),
            ));
          }

          // Ajustement des durées (endTime) de chaque mot
          for (int i = 0; i < words.length; i++) {
            if (i + 1 < words.length) {
              final nextStart = words[i + 1].start;
              words[i] = LyricWord(
                text: words[i].text,
                start: words[i].start,
                end: nextStart > words[i].start ? nextStart : words[i].start + const Duration(milliseconds: 250),
              );
            } else {
              words[i] = LyricWord(
                text: words[i].text,
                start: words[i].start,
                end: words[i].start + Duration(milliseconds: (words[i].text.length * 90).clamp(250, 1800)),
              );
            }
          }

          final endTime = words.isNotEmpty ? words.last.end : lineTime + const Duration(seconds: 3);
          parsedLines.add(LyricLine(
            time: lineTime,
            text: cleanText,
            endTime: endTime,
            words: words,
          ));
        } else {
          // Ligne LRC classique sans balises de mot
          if (_isCreditLine(lineContent, lineTime)) continue;
          parsedLines.add(LyricLine(
            time: lineTime,
            text: lineContent,
            words: const [],
          ));
        }
      }
    }

    parsedLines.sort((a, b) => a.time.compareTo(b.time));

    // Deuxieme passe : interpolation automatique pour les fichiers LRC classiques
    for (int i = 0; i < parsedLines.length; i++) {
      final line = parsedLines[i];
      if (line.words.isEmpty && line.text.isNotEmpty) {
        Duration duration;
        if (i + 1 < parsedLines.length) {
          final rawDiff = parsedLines[i + 1].time - line.time;
          if (rawDiff.inMilliseconds <= 0) {
            duration = const Duration(seconds: 3);
          } else if (rawDiff.inMilliseconds > 7000) {
            duration = const Duration(milliseconds: 4500);
          } else {
            duration = Duration(milliseconds: (rawDiff.inMilliseconds * 0.88).round());
          }
        } else {
          duration = const Duration(seconds: 4);
        }

        final wordsRaw = line.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        if (wordsRaw.isNotEmpty) {
          final totalChars = wordsRaw.fold<int>(0, (sum, w) => sum + w.length);
          final List<LyricWord> generatedWords = [];
          var currentStart = line.time;

          for (final w in wordsRaw) {
            final wDurationMs = totalChars > 0
                ? (duration.inMilliseconds * (w.length / totalChars)).round()
                : (duration.inMilliseconds / wordsRaw.length).round();
            final wEnd = currentStart + Duration(milliseconds: wDurationMs.clamp(120, 5000));
            generatedWords.add(LyricWord(text: w, start: currentStart, end: wEnd));
            currentStart = wEnd;
          }

          parsedLines[i] = LyricLine(
            time: line.time,
            text: line.text,
            endTime: currentStart,
            words: generatedWords,
          );
        }
      }
    }

    return parsedLines;
  }
}
