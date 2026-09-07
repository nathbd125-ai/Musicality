import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:musicality/core/globals.dart';

class AudioQualitySettingsCard extends StatelessWidget {
  final int downloadedCount;
  final VoidCallback onDownloadsDeleted;

  const AudioQualitySettingsCard({
    super.key,
    required this.downloadedCount,
    required this.onDownloadsDeleted,
  });

  void _deleteDownloads() {
    final docDir = Directory(globalDocumentPath);
    if (docDir.existsSync()) {
      final files = docDir.listSync().whereType<File>();
      for (var file in files) {
        if (file.path.endsWith('.flac') || file.path.endsWith('.mp3')) {
          // Not in cache, meaning it's a manual download
          if (!file.path.replaceAll('\\', '/').contains('/cache/')) {
            try {
              file.deleteSync();
            } catch (e) {
              debugPrint("Erreur suppression téléchargement : $e");
            }
          }
        }
      }
    }
    onDownloadsDeleted();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
                CupertinoIcons.waveform,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                "Qualité sonore",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        AnimatedBuilder(
          animation: Listenable.merge([
            isLosslessNotifier,
            isHiResNotifier,
          ]),
          builder: (context, _) {
            int currentQuality = 0;
            if (isHiResNotifier.value) {
              currentQuality = 2;
            } else if (isLosslessNotifier.value) {
              currentQuality = 1;
            }

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
                groupValue: currentQuality,
                onValueChanged: (int? value) {
                  if (value == 0) {
                    isHiResNotifier.value = false;
                    isLosslessNotifier.value = false;
                  } else if (value == 1) {
                    isHiResNotifier.value = false;
                    isLosslessNotifier.value = true;
                  } else if (value == 2) {
                    isHiResNotifier.value = true;
                    isLosslessNotifier.value = true; // Flac is needed for Hi-Res
                  }
                },
                children: {
                  0: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                    ),
                    child: Text(
                      "MP3",
                      style: TextStyle(
                        color: currentQuality == 0
                            ? Colors.white
                            : Colors.white54,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  1: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                    ),
                    child: Text(
                      "Lossless",
                      style: TextStyle(
                        color: currentQuality == 1
                            ? Colors.white
                            : Colors.white54,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  2: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                    ),
                    child: Text(
                      "Hi-Res",
                      style: TextStyle(
                        color: currentQuality == 2
                            ? Colors.white
                            : Colors.white54,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                },
              ),
            );
          },
        ),

        const SizedBox(height: 30),

        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                CupertinoIcons.cloud_download,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                "Préférence de téléchargement",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        AnimatedBuilder(
          animation: Listenable.merge([
            isDownloadLosslessNotifier,
            isDownloadHiResNotifier,
          ]),
          builder: (context, _) {
            int currentQuality = 0;
            if (isDownloadHiResNotifier.value) {
              currentQuality = 2;
            } else if (isDownloadLosslessNotifier.value) {
              currentQuality = 1;
            }

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
                groupValue: currentQuality,
                onValueChanged: (int? value) {
                  if (value == 0) {
                    isDownloadHiResNotifier.value = false;
                    isDownloadLosslessNotifier.value = false;
                  } else if (value == 1) {
                    isDownloadHiResNotifier.value = false;
                    isDownloadLosslessNotifier.value = true;
                  } else if (value == 2) {
                    isDownloadHiResNotifier.value = true;
                    isDownloadLosslessNotifier.value = true;
                  }
                },
                children: {
                  0: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                    ),
                    child: Text(
                      "MP3",
                      style: TextStyle(
                        color: currentQuality == 0
                            ? Colors.white
                            : Colors.white54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  1: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                    ),
                    child: Text(
                      "Lossless",
                      style: TextStyle(
                        color: currentQuality == 1
                            ? Colors.white
                            : Colors.white54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  2: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                    ),
                    child: Text(
                      "Hi-Res",
                      style: TextStyle(
                        color: currentQuality == 2
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
        if (downloadedCount > 0) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _deleteDownloads,
              child: Text(
                "Supprimer $downloadedCount téléchargement${downloadedCount > 1 ? 's' : ''}",
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
    );
  }
}
