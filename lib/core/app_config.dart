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

  static bool get isStudioMode => isStudioBuild;
}
