import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:musicality/core/models.dart';

class VpsSyncService {
  static const String _apiUrl = 'https://musicality.duckdns.org/api/upload-lyrics';
  static const String _apiToken = 'msc_sec_89f3a912e742c091d34e6b12a87c10b7';

  /// Convertit une liste de LyricLine en chaîne standardisée au format LRC / Enhanced LRC :
  /// Si des mots synchronisés sont présents : [mm:ss.xx] <mm:ss.xx>Mot1 <mm:ss.xx>Mot2
  /// Sinon : [mm:ss.xx] Paroles
  static String formatLrc(List<LyricLine> lines) {
    final sortedLines = List<LyricLine>.from(lines)
      ..sort((a, b) => a.time.compareTo(b.time));

    final buffer = StringBuffer();
    for (final line in sortedLines) {
      final formattedTime = formatTimestamp(line.time);
      if (line.words.isNotEmpty) {
        final wordsFormatted = line.words.map((w) {
          final wordTime = formatWordTimestamp(w.start);
          return '$wordTime${w.text.trim()}';
        }).join(' ');
        buffer.writeln('$formattedTime $wordsFormatted');
      } else {
        buffer.writeln('$formattedTime ${line.text.trim()}');
      }
    }
    return buffer.toString().trim();
  }

  /// Formate une durée au standard LRC [mm:ss.xx] (centisecondes)
  static String formatTimestamp(Duration d) {
    if (d.isNegative) {
      return '[00:00.00]';
    }
    final totalCentiseconds = (d.inMilliseconds / 10).floor();
    final centiseconds = totalCentiseconds % 100;
    final totalSeconds = (totalCentiseconds / 100).floor();
    final seconds = totalSeconds % 60;
    final minutes = (totalSeconds / 60).floor();

    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');
    final cStr = centiseconds.toString().padLeft(2, '0');
    return '[$mStr:$sStr.$cStr]';
  }

  /// Formate une durée au standard Enhanced LRC <mm:ss.xx> pour les mots
  static String formatWordTimestamp(Duration d) {
    if (d.isNegative) {
      return '<00:00.00>';
    }
    final totalCentiseconds = (d.inMilliseconds / 10).floor();
    final centiseconds = totalCentiseconds % 100;
    final totalSeconds = (totalCentiseconds / 100).floor();
    final seconds = totalSeconds % 60;
    final minutes = (totalSeconds / 60).floor();

    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');
    final cStr = centiseconds.toString().padLeft(2, '0');
    return '<$mStr:$sStr.$cStr>';
  }

  /// Téléverse directement le contenu LRC sur le serveur VPS via l'API Web HTTPS sécurisée
  static Future<void> uploadLrc({
    required String baseName,
    required String lrcContent,
  }) async {
    final cleanBaseName = baseName.trim();
    if (cleanBaseName.isEmpty) {
      throw Exception('Nom de fichier invalide');
    }

    final targetFilename = cleanBaseName.endsWith('.lrc')
        ? cleanBaseName
        : '$cleanBaseName.lrc';

    debugPrint('Téléversement HTTPS des paroles vers $_apiUrl pour $targetFilename...');

    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'X-Musicality-Token': _apiToken,
      },
      body: jsonEncode({
        'filename': targetFilename,
        'content': lrcContent,
      }),
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw Exception('Délai d\'attente dépassé lors de l\'envoi des paroles'),
    );

    if (response.statusCode == 200) {
      debugPrint('Fichier $targetFilename enregistré avec succès sur le VPS via HTTPS.');
    } else {
      String errorMessage = 'Erreur HTTP ${response.statusCode}';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] != null) {
          errorMessage = body['error'].toString();
        }
      } catch (_) {}
      throw Exception('Échec de la synchronisation des paroles : $errorMessage');
    }
  }
}
