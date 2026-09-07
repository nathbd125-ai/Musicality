import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:musicality/core/globals.dart';

class AccountPageView extends StatefulWidget {
  final List<Color> dynamicGradientColors;

  const AccountPageView({super.key, required this.dynamicGradientColors});

  @override
  State<AccountPageView> createState() => _AccountPageViewState();
}

class _AccountPageViewState extends State<AccountPageView> {
  int _cacheSizeBytes = 0;
  int _downloadedCount = 0;

  @override
  void initState() {
    super.initState();
    _calculateSizes();
  }

  void _calculateSizes() {
    int cacheSize = 0;
    int dlCount = 0;

    // Cache calculation
    final cacheDir = Directory('$globalDocumentPath/cache');
    if (cacheDir.existsSync()) {
      for (var file in cacheDir.listSync().whereType<File>()) {
        cacheSize += file.lengthSync();
      }
    }

    // Downloads calculation (only counting .flac and .mp3 in root docDir)
    final docDir = Directory(globalDocumentPath);
    if (docDir.existsSync()) {
      for (var file in docDir.listSync().whereType<File>()) {
        if (file.path.endsWith('.flac') || file.path.endsWith('.mp3')) {
          dlCount++;
        }
      }
    }

    if (mounted) {
      setState(() {
        _cacheSizeBytes = cacheSize;
        _downloadedCount = dlCount;
      });
    }
  }

  void _calculateCacheSize() {
    _calculateSizes();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: isError
            ? const Color(0xFFFF5252)
            : const Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 20),
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) {
                  return LinearGradient(
                    colors: widget.dynamicGradientColors,
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ).createShader(bounds);
                },
                child: const Text(
                  "Mon Compte",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),

          // Profil utilisateur, avatar temps réel et authentification
          AccountProfileHeader(
            dynamicGradientColors: widget.dynamicGradientColors,
            showSnackBar: _showSnackBar,
          ),

          const SizedBox(height: 30),

          // Paramètres
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: const Text(
                "Paramètres",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          Container(
            margin: const EdgeInsets.only(left: 16, right: 16, top: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Qualités audio & téléchargements
                      AudioQualitySettingsCard(
                        downloadedCount: _downloadedCount,
                        onDownloadsDeleted: _calculateSizes,
                      ),

                      const SizedBox(height: 30),

                      // Liquid Glass
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              CupertinoIcons.drop,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Row(
                                  children: [
                                    Text(
                                      "Liquid Glass",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(
                                      Icons.lock_outline,
                                      size: 16,
                                      color: Colors.white54,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: isLiquidGlassEnabledNotifier,
                            builder: (context, isLiquidGlassEnabled, _) {
                              return CupertinoSwitch(
                                value: false, // Forcé à false
                                activeTrackColor:
                                    widget.dynamicGradientColors[0],
                                onChanged: null, // Verrouillé
                              );
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 30),

                      // Économiseur de batterie
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              CupertinoIcons.battery_charging,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Text(
                              "Économiseur de batterie",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: isBatterySaverEnabledNotifier,
                            builder: (context, isBatterySaver, _) {
                              return CupertinoSwitch(
                                value: isBatterySaver,
                                activeTrackColor:
                                    widget.dynamicGradientColors[0],
                                onChanged: (val) {
                                  isBatterySaverEnabledNotifier.value = val;
                                },
                              );
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 30),

                      // Cache & Stockage
                      StorageCacheSettingsCard(
                        activeTrackColor: widget.dynamicGradientColors[0],
                        cacheSizeBytes: _cacheSizeBytes,
                        onCacheCleared: _calculateCacheSize,
                        onCacheLimitChanged: _calculateSizes,
                      ),

                      const SizedBox(height: 30),

                      // Fondu enchaîné (Crossfade)
                      CrossfadeSettingsCard(
                        dynamicGradientColors: widget.dynamicGradientColors,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 220),
        ],
      ),
    );
  }
}
