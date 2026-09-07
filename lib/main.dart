// ignore_for_file: experimental_member_use, deprecated_member_use, depend_on_referenced_packages, invalid_use_of_experimental_api

import 'package:musicality/core/globals.dart';
import 'package:musicality/ui/pages/home_screen.dart';
import 'package:musicality/core/my_audio_handler.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:mmkv/mmkv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:musicality/core/objectbox_service.dart';

import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:cronet_http/cronet_http.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialisation de Firebase en premier pour activer Crashlytics
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  final dir = await getApplicationDocumentsDirectory();

  // Initialisation du moteur Cronet partagé (singleton) avec cache disque pour QUIC 0-RTT
  CronetEngine? cronetEngine;
  if (!kIsWeb && Platform.isAndroid) {
    try {
      final cacheDir = Directory('${dir.path}/cronet_cache');
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
      cronetEngine = CronetEngine.build(
        cacheMode: CacheMode.disk,
        cacheMaxSize: 20 * 1024 * 1024,
        storagePath: cacheDir.path,
        enableHttp2: true,
        enableQuic: true,
        enableBrotli: true,
        quicHints: [
          ('musicality.duckdns.org', 443, 443),
        ],
      );
      debugPrint("Cronet initialisé avec succès (HTTP/2, HTTP/3 QUIC 0-RTT, Brotli, Cache disque)");
    } catch (e) {
      debugPrint("Erreur initialisation Cronet, fallback sur Client standard: $e");
    }
  }

  http.Client createHttpClient() {
    if (cronetEngine != null) {
      return CronetClient.fromCronetEngine(cronetEngine, closeEngine: false);
    }
    return http.Client();
  }

  // 2. Exécution de l'application avec le client Cronet optimisé (HTTP/2, HTTP/3, QUIC).
  await http.runWithClient(() async {
    // Initialisation de MMKV
    await MMKV.initialize(rootDir: dir.path);

    // Vérification de la version pour purger les fichiers .lrc après une MAJ
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      final mmkv = MMKV.defaultMMKV();
      final lastBuild = mmkv.decodeInt('last_run_build_number');

      if (currentBuild > lastBuild) {
        if (dir.existsSync()) {
          for (var file in dir.listSync().whereType<File>()) {
            if (file.path.endsWith('.lrc')) {
              try {
                file.deleteSync();
              } catch (_) {}
            }
          }
        }
        mmkv.encodeInt('last_run_build_number', currentBuild);
      }
    } catch (e) {
      debugPrint("Erreur lors de la vérification de la MAJ : $e");
    }

    obx = await ObjectBoxService.create();

    await fetchMusiques();

    await initPersistence();
    await clearTemporaryFiles();

    // --- NOUVEAUTÉ : ON LANCE LA SYNCHRONISATION AUTOMATIQUE ---
    initAutoSyncListeners();
    performCloudRestore().catchError((e) {
      debugPrint("Erreur cloud restore au démarrage : $e");
    }); // Télécharge les données si on est déjà connecté en tâche de fond
    // -----------------------------------------------------------

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    globalAudioHandler = await AudioService.init(
      builder: () => MyAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.musicality.channel.audio',
        androidNotificationChannelName: 'Musicality Playback',
        androidNotificationOngoing: true,
        androidNotificationIcon: 'drawable/ic_notification',
      ),
    );

    await LiquidGlassWidgets.initialize();
    runApp(LiquidGlassWidgets.wrap(child: const MusicalityApp()));
  }, createHttpClient);
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

Future<void> cacheGoogleAvatar(String url) async {
  try {
    final mmkv = MMKV.defaultMMKV();
    final savedUrl = mmkv.decodeString('last_google_avatar_url');
    final cacheFile = File('$globalDocumentPath/cached_google_avatar.jpg');

    if (savedUrl != url || !cacheFile.existsSync()) {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await cacheFile.writeAsBytes(response.bodyBytes);
        mmkv.encodeString('last_google_avatar_url', url);
      }
    }
  } catch (e) {
    debugPrint('Failed to cache Google avatar: $e');
  }
}
