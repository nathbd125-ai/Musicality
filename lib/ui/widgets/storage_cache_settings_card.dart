import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:musicality/core/globals.dart';

class StorageCacheSettingsCard extends StatelessWidget {
  final Color activeTrackColor;
  final int cacheSizeBytes;
  final VoidCallback onCacheCleared;
  final VoidCallback onCacheLimitChanged;

  const StorageCacheSettingsCard({
    super.key,
    required this.activeTrackColor,
    required this.cacheSizeBytes,
    required this.onCacheCleared,
    required this.onCacheLimitChanged,
  });

  void _clearCache() {
    final cacheDir = Directory('$globalDocumentPath/cache');
    if (cacheDir.existsSync()) {
      final files = cacheDir.listSync().whereType<File>();
      for (var file in files) {
        try {
          file.deleteSync();
        } catch (e) {
          debugPrint("Erreur suppression fichier cache : $e");
        }
      }
    }
    // Vider aussi les pochettes dans le dossier parent (seulement si la musique n'est pas téléchargée)
    final docDir = Directory(globalDocumentPath);
    if (docDir.existsSync()) {
      final files = docDir.listSync().whereType<File>();
      for (var file in files) {
        if (file.path.endsWith('.jpg') || file.path.endsWith('.lrc')) {
          try {
            final baseName = file.path
                .split(Platform.pathSeparator)
                .last
                .replaceAll(RegExp(r'\.(jpg|lrc)$'), '');
            final hasMp3 = File(
              '${docDir.path}${Platform.pathSeparator}$baseName.mp3',
            ).existsSync();
            final hasFlac = File(
              '${docDir.path}${Platform.pathSeparator}$baseName.flac',
            ).existsSync();
            final hasHiRes = File(
              '${docDir.path}${Platform.pathSeparator}$baseName-hires.flac',
            ).existsSync();

            if (!hasMp3 && !hasFlac && !hasHiRes) {
              file.deleteSync();
            }
          } catch (e) {
            debugPrint("Erreur suppression image : $e");
          }
        }
      }
    }

    onCacheCleared();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                CupertinoIcons.archivebox,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Mise en cache",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Conserver temporairement les musiques lues",
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: isCacheEnabledNotifier,
              builder: (context, isCacheEnabled, _) {
                return CupertinoSwitch(
                  value: isCacheEnabled,
                  activeTrackColor: activeTrackColor,
                  onChanged: (val) {
                    isCacheEnabledNotifier.value = val;
                  },
                );
              },
            ),
          ],
        ),
        ValueListenableBuilder<bool>(
          valueListenable: isCacheEnabledNotifier,
          builder: (context, isCacheEnabled, _) {
            if (!isCacheEnabled) return const SizedBox();
            return Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Column(
                children: [
                  ValueListenableBuilder<int>(
                    valueListenable: cacheLimitNotifier,
                    builder: (context, cacheLimit, _) {
                      return Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                        child: CupertinoSlidingSegmentedControl<int>(
                          backgroundColor: Colors.transparent,
                          thumbColor: Colors.white.withValues(alpha: 0.2),
                          groupValue: (cacheLimit == 50 ||
                                  ![100, 500, 1024, 5120].contains(cacheLimit))
                              ? 100
                              : cacheLimit,
                          onValueChanged: (int? value) {
                            if (value != null) {
                              cacheLimitNotifier.value = value;
                              Future.delayed(
                                const Duration(milliseconds: 100),
                                onCacheLimitChanged,
                              );
                            }
                          },
                          children: {
                            100: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                "100 Mo",
                                style: TextStyle(
                                  color: cacheLimit == 100
                                      ? Colors.white
                                      : Colors.white54,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            500: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                "500 Mo",
                                style: TextStyle(
                                  color: cacheLimit == 500
                                      ? Colors.white
                                      : Colors.white54,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            1024: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                "1 Go",
                                style: TextStyle(
                                  color: cacheLimit == 1024
                                      ? Colors.white
                                      : Colors.white54,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            5120: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                "5 Go",
                                style: TextStyle(
                                  color: cacheLimit == 5120
                                      ? Colors.white
                                      : Colors.white54,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          },
                        ),
                      );
                    },
                  ),
                  if (cacheSizeBytes > 0) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        onPressed: _clearCache,
                        child: Text(
                          "Vider le cache (${(cacheSizeBytes / (1024 * 1024)).toStringAsFixed(1)} Mo)",
                          style: const TextStyle(
                            color: Color(0xFFFF5252),
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
