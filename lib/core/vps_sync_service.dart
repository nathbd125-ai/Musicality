import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:musicality/core/models.dart';

class VpsSyncService {
  static const String _host = '164.132.104.67';
  static const int _port = 22;
  static const String _username = 'ubuntu';
  static const String _password = 'NAthan@1306';
  static const String _remoteDirectory = '/var/www/html/media/Musicality';

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

  /// Téléverse directement le contenu LRC sur le VPS via SFTP et remplace le fichier distant
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
    final remotePath = '$_remoteDirectory/$targetFilename';

    debugPrint('Connexion SFTP au VPS $_host:$_port pour $remotePath...');

    final socket = await SSHSocket.connect(
      _host,
      _port,
      timeout: const Duration(seconds: 12),
    );

    final client = SSHClient(
      socket,
      username: _username,
      onPasswordRequest: () => _password,
    );

    try {
      final sftp = await client.sftp();
      final file = await sftp.open(
        remotePath,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );

      final bytes = Uint8List.fromList(utf8.encode(lrcContent));
      await file.writeBytes(bytes);
      await file.close();

      debugPrint('Fichier $remotePath remplacé avec succès sur le VPS.');
    } finally {
      client.close();
    }
  }
}
