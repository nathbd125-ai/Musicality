import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:musicality/core/api_config.dart';
import 'package:musicality/ui/widgets/update_dialog.dart';

class AppUpdateInfo {
  final String serverVersion;
  final String releaseNotes;
  final String downloadUrl;

  const AppUpdateInfo({
    required this.serverVersion,
    required this.releaseNotes,
    required this.downloadUrl,
  });
}

class AppUpdateService {
  /// Vérifie si une mise à jour est disponible sur le serveur (uniquement sous Android).
  static Future<AppUpdateInfo?> checkForUpdates() async {
    // Les mises à jour directes par APK sont réservées à Android. Sur iOS, les MAJ passent par TestFlight / App Store.
    if (!Platform.isAndroid) return null;

    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.baseUrl}/version.json?t=${DateTime.now().millisecondsSinceEpoch}',
            ),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        String decodedBody;
        try {
          decodedBody = utf8.decode(response.bodyBytes);
        } catch (e) {
          decodedBody = latin1.decode(response.bodyBytes);
        }

        Map<String, dynamic>? data;
        try {
          data = jsonDecode(decodedBody) as Map<String, dynamic>;
        } catch (_) {
          // Fallback avec regex si le JSON contient des guillemets non échappés dans releaseNotes
          final versionMatch =
              RegExp(r'"version"\s*:\s*"([^"]+)"').firstMatch(decodedBody);
          final buildMatch =
              RegExp(r'"buildNumber"\s*:\s*(\d+)').firstMatch(decodedBody);
          final downloadMatch =
              RegExp(r'"downloadUrl"\s*:\s*"([^"]+)"').firstMatch(decodedBody);
          final notesMatch = RegExp(
            r'"releaseNotes"\s*:\s*"(.*)"\s*\}',
            dotAll: true,
          ).firstMatch(decodedBody);

          if (versionMatch != null && buildMatch != null) {
            data = {
              'version': versionMatch.group(1),
              'buildNumber': int.tryParse(buildMatch.group(1)!) ?? 0,
              'downloadUrl': downloadMatch?.group(1),
              'releaseNotes': notesMatch?.group(1),
            };
          }
        }

        if (data == null) return null;

        final serverVersion =
            (data['version'] as String?) ?? 'Nouvelle version';
        final serverBuild = (data['buildNumber'] as int?) ?? 0;

        final packageInfo = await PackageInfo.fromPlatform();
        final localBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

        if (serverBuild > localBuild) {
          String downloadUrl =
              (data['downloadUrl'] as String?) ??
              '${ApiConfig.baseUrl}/app-release.apk';
          // S'assurer que le téléchargement passe en HTTPS
          if (downloadUrl.startsWith('http://164.132.104.67')) {
            downloadUrl = downloadUrl.replaceFirst(
              'http://164.132.104.67',
              'https://musicality.duckdns.org',
            );
          }

          return AppUpdateInfo(
            serverVersion: serverVersion,
            releaseNotes:
                data['releaseNotes'] ?? 'Nouvelle version disponible !',
            downloadUrl: downloadUrl,
          );
        }
      }
    } catch (e) {
      debugPrint("Impossible de vérifier les mises à jour : $e");
    }

    return null;
  }

  /// Affiche le dialogue modal de mise à jour.
  static void showUpdateDialog(BuildContext context, AppUpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return UpdateDialog(
          serverVersion: info.serverVersion,
          releaseNotes: info.releaseNotes,
          downloadUrl: info.downloadUrl,
        );
      },
    );
  }
}
