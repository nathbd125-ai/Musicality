import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final ValueNotifier<bool> isOfflineNotifier = ValueNotifier<bool>(false);

  static bool get isOffline => isOfflineNotifier.value;
  static bool get isOnline => !isOfflineNotifier.value;

  static StreamSubscription<List<ConnectivityResult>>? _sub;
  static bool _initialized = false;

  /// Callback optionnel déclenché lorsque la connexion Internet revient
  static VoidCallback? onReconnected;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final initialResults = await Connectivity().checkConnectivity();
      _updateStatus(initialResults, isInitial: true);
    } catch (e) {
      debugPrint("Erreur checkConnectivity initial: $e");
    }

    _sub = Connectivity().onConnectivityChanged.listen((results) {
      _updateStatus(results);
    });
  }

  static void _updateStatus(List<ConnectivityResult> results, {bool isInitial = false}) {
    final bool currentlyOffline =
        results.isEmpty ||
        results.every((r) => r == ConnectivityResult.none);

    final bool wasOffline = isOfflineNotifier.value;
    isOfflineNotifier.value = currentlyOffline;

    if (!isInitial && wasOffline && !currentlyOffline) {
      debugPrint("📶 [ConnectivityService] Connexion réseau rétablie !");
      onReconnected?.call();
    } else if (currentlyOffline) {
      debugPrint("📶 [ConnectivityService] Mode hors-ligne détecté.");
    }
  }

  static void dispose() {
    _sub?.cancel();
    _sub = null;
    _initialized = false;
  }
}
