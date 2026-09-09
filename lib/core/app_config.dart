import 'package:flutter/foundation.dart';
import 'package:mmkv/mmkv.dart';

class AppConfig {
  /// Défini au moment du build avec `--dart-define=STUDIO_MODE=true`
  static const bool isStudioBuild = bool.fromEnvironment(
    'STUDIO_MODE',
    defaultValue: false,
  );

  static final ValueNotifier<bool> isStudioModeNotifier = ValueNotifier<bool>(
    isStudioBuild || _loadStudioPreference(),
  );

  static bool get isStudioMode => isStudioModeNotifier.value;

  static bool _loadStudioPreference() {
    try {
      final mmkv = MMKV.defaultMMKV();
      return mmkv.decodeBool('is_studio_mode_override', defaultValue: false);
    } catch (_) {
      return false;
    }
  }

  static void setStudioModeOverride(bool enabled) {
    try {
      final mmkv = MMKV.defaultMMKV();
      mmkv.encodeBool('is_studio_mode_override', enabled);
    } catch (_) {}
    isStudioModeNotifier.value = isStudioBuild || enabled;
  }
}
