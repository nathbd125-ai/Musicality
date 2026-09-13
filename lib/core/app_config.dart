import 'package:flutter/foundation.dart';

class AppConfig {
  /// Défini au moment du build avec `--dart-define=STUDIO_MODE=true`
  static const bool isStudioBuild = bool.fromEnvironment(
    'STUDIO_MODE',
    defaultValue: false,
  );

  static final ValueNotifier<bool> isStudioModeNotifier = ValueNotifier<bool>(
    isStudioBuild,
  );

  static bool get isStudioMode => isStudioModeNotifier.value;

  static void initFromPackageName(String packageName) {
    // Musicality Studio a pour applicationId "com.musicality.studio" (ou contient ".studio")
    // Musicality de base a pour applicationId "com.musicality"
    isStudioModeNotifier.value = packageName.contains('.studio');
  }
}
