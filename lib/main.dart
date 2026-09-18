// ignore_for_file: experimental_member_use, deprecated_member_use, depend_on_referenced_packages, invalid_use_of_experimental_api

import 'package:musicality/core/globals.dart';
import 'package:musicality/ui/pages/home_screen.dart';
import 'package:musicality/core/my_audio_handler.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:mmkv/mmkv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:musicality/core/objectbox_service.dart';
import 'package:musicality/core/app_config.dart';

import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:cronet_http/cronet_http.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force le verrouillage en mode portrait (vertical) par défaut.
  // Seul le mode horizontal dédié (LandscapeStereoPlayer) bascule en paysage.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Activation du mode bord-à-bord (Edge-to-Edge) Android 15 & 16 avec barres transparentes
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  // 1. Initialisation de Firebase en premier pour activer Crashlytics
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FlutterError.onError = (details) {
    debugPrint("FlutterError: ${details.exceptionAsString()}\n${details.stack}");
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint("PlatformDispatcher error: $error\n$stack");
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

  bool isCronetAvailable = cronetEngine != null;

  http.Client createHttpClient() {
    if (isCronetAvailable && cronetEngine != null) {
      return ResilientHttpClient(
        cronetEngine: cronetEngine,
        onCronetFailure: () {
          isCronetAvailable = false;
        },
      );
    }
    return http.Client();
  }

  // 2. Exécution de l'application avec le client Cronet optimisé (HTTP/2, HTTP/3, QUIC).
  await http.runWithClient(() async {
    // Initialisation de MMKV
    try {
      await MMKV.initialize(rootDir: dir.path);
    } catch (e) {
      debugPrint("Erreur initialisation MMKV : $e");
    }

    // Initialisation de la synchronisation instantanée cross-app (Musicality <-> Musicality Studio)
    LyricsService.initCrossAppSync();

    // Mise à jour du numéro de build sans effacer les fichiers locaux (pochettes et paroles)
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      AppConfig.initFromPackageName(packageInfo.packageName);
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      final mmkv = MMKV.defaultMMKV();
      final lastBuild = mmkv.decodeInt('last_run_build_number');

      if (currentBuild > lastBuild) {
        if (dir.existsSync()) {
          // Nettoyage uniquement des fichiers résiduels corrompus de 0 octet si présents
          for (var file in dir.listSync().whereType<File>()) {
            if (file.path.endsWith('.jpg') && file.lengthSync() == 0) {
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

    try {
      await ConnectivityService.initialize();
      ConnectivityService.onReconnected = () {
        fetchMusiques();
      };
    } catch (e, st) {
      debugPrint("Erreur initialisation ConnectivityService : $e\n$st");
    }

    try {
      obx = await ObjectBoxService.create();
      loadMusiquesFromCache();
    } catch (e, st) {
      debugPrint("Erreur initialisation ObjectBox : $e\n$st");
    }

    if (globalPlaylist.isEmpty) {
      try {
        await fetchMusiques();
      } catch (e, st) {
        debugPrint("Erreur chargement musiques : $e\n$st");
      }
    } else {
      // Synchronisation avec le VPS en arrière-plan sans bloquer l'affichage de l'application
      unawaited(fetchMusiques());
    }

    try {
      await initPersistence();
      // Préchargement asynchrone du cache des pochettes pour éliminer les I/O synchrones au scroll
      unawaited(initCoverCache());
      // Slider Liquid Glass bloqué à la demande de l'utilisateur (0 ressource consommée)
      // if (isLiquidGlassEnabledNotifier.value && !isBatterySaverEnabledNotifier.value) {
      //   unawaited(AGSLSliderGlass.preload());
      // }
    } catch (e, st) {
      debugPrint("Erreur initPersistence : $e\n$st");
    }

    try {
      await clearTemporaryFiles();
    } catch (e, st) {
      debugPrint("Erreur clearTemporaryFiles : $e\n$st");
    }

    // --- NOUVEAUTÉ : ON LANCE LA SYNCHRONISATION AUTOMATIQUE ---
    try {
      initAutoSyncListeners();
      performCloudRestore().catchError((e) {
        debugPrint("Erreur cloud restore au démarrage : $e");
      }); // Télécharge les données si on est déjà connecté en tâche de fond
    } catch (e) {
      debugPrint("Erreur init auto sync : $e");
    }
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

    // Restauration de la dernière session d'écoute (titre, position, queue) en mode pause
    try {
      await (globalAudioHandler as MyAudioHandler).restoreLastSession();
    } catch (e) {
      debugPrint("Erreur restauration session audio : $e");
    }

    runApp(const MusicalityApp());
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

/// Client HTTP résilient assurant une bascule transparente et permanente vers IOClient
/// si le moteur natif Cronet (Google Play Services) est absent ou rencontre une erreur d'exécution.
class ResilientHttpClient extends http.BaseClient {
  final CronetEngine cronetEngine;
  final VoidCallback onCronetFailure;
  final http.Client _fallbackClient;
  http.Client? _cronetClient;

  ResilientHttpClient({
    required this.cronetEngine,
    required this.onCronetFailure,
  })  : _fallbackClient = http.Client() {
    try {
      _cronetClient = CronetClient.fromCronetEngine(cronetEngine, closeEngine: false);
    } catch (e) {
      debugPrint("[ResilientHttpClient] Échec instanciation CronetClient : $e. Repli standard.");
      onCronetFailure();
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_cronetClient != null) {
      List<int>? cachedBody;
      if (request is http.Request) {
        cachedBody = request.bodyBytes;
      }

      try {
        return await _cronetClient!.send(request);
      } catch (e) {
        debugPrint("[ResilientHttpClient] Cronet a échoué ($e). Repli immédiat et permanent sur IOClient.");
        onCronetFailure();
        _cronetClient = null;

        if (request is http.Request && cachedBody != null) {
          final fallbackRequest = http.Request(request.method, request.url)
            ..headers.addAll(request.headers)
            ..maxRedirects = request.maxRedirects
            ..followRedirects = request.followRedirects
            ..persistentConnection = request.persistentConnection
            ..bodyBytes = cachedBody;
          return await _fallbackClient.send(fallbackRequest);
        }
      }
    }
    return await _fallbackClient.send(request);
  }

  @override
  void close() {
    _cronetClient?.close();
    _fallbackClient.close();
    super.close();
  }
}
