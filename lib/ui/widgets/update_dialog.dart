import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:io';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class UpdateDialog extends StatefulWidget {
  final String serverVersion;
  final String releaseNotes;
  final String downloadUrl;

  const UpdateDialog({
    super.key,
    required this.serverVersion,
    required this.releaseNotes,
    required this.downloadUrl,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog>
    with SingleTickerProviderStateMixin {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _status = "Prêt à télécharger";
  bool _showChangelog = false;

  late AnimationController _bgAnimController;

  @override
  void initState() {
    super.initState();
    _bgAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
  }

  @override
  void dispose() {
    _bgAnimController.dispose();
    super.dispose();
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _status = "Téléchargement en cours...";
      _showChangelog = false;
    });

    try {
      // Utilise dart:io HttpClient directement pour contourner l'interception
      // de Cronet via runWithClient() — Cronet peut couper les gros téléchargements binaires
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(widget.downloadUrl));
      final response = await request.close();

      if (response.statusCode != 200) {
        httpClient.close();
        throw Exception('Serveur a répondu ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/app-update.apk';
      final file = File(filePath);
      final sink = file.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          setState(() {
            _progress = receivedBytes / totalBytes;
            _status =
                "Téléchargement : ${(receivedBytes / 1024 / 1024).toStringAsFixed(1)} Mo / ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} Mo";
          });
        }
      }
      await sink.close();
      httpClient.close();

      // Vérifier que le fichier a bien été téléchargé en entier
      final downloadedSize = await file.length();
      if (totalBytes > 0 && downloadedSize < totalBytes) {
        throw Exception('Téléchargement incomplet ($downloadedSize / $totalBytes octets)');
      }

      setState(() {
        _status = "Lancement de l'installation...";
      });

      await OpenFilex.open(filePath);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _status = "Erreur : $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      elevation: 0,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _bgAnimController,
                builder: (context, child) {
                  final double t = _bgAnimController.value * 2 * math.pi;
                  return Stack(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF0F0F1A), Color(0xFF1E3A8A)],
                          ),
                        ),
                      ),
                      Positioned(
                        left: size.width * 0.2 - 200 + 150 * math.cos(t),
                        top: size.height * 0.2 - 200 + 150 * math.sin(t),
                        child: Container(
                          width: 400,
                          height: 400,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                      ),
                      Positioned(
                        right:
                            size.width * 0.2 -
                            200 +
                            180 * math.cos(t + math.pi / 2),
                        bottom:
                            size.height * 0.2 -
                            200 +
                            180 * math.sin(t + math.pi / 2),
                        child: Container(
                          width: 400,
                          height: 400,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF0D9488),
                          ),
                        ),
                      ),
                      Positioned(
                        left:
                            size.width * 0.2 -
                            200 +
                            120 * math.cos(t + math.pi),
                        bottom:
                            size.height * 0.2 -
                            200 +
                            120 * math.sin(t + math.pi),
                        child: Container(
                          width: 400,
                          height: 400,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF9333EA),
                          ),
                        ),
                      ),
                      Positioned(
                        right:
                            size.width * 0.2 -
                            200 +
                            140 * math.cos(t + 3 * math.pi / 2),
                        top:
                            size.height * 0.2 -
                            200 +
                            140 * math.sin(t + 3 * math.pi / 2),
                        child: Container(
                          width: 400,
                          height: 400,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF4C1D95),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: const SizedBox(),
              ),
            ),
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.4),
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Mise à jour ${widget.serverVersion}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          if (!_isDownloading) ...[
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _showChangelog = !_showChangelog;
                                });
                              },
                              child: Row(
                                children: [
                                  Text(
                                    _showChangelog
                                        ? "Masquer les nouveautés"
                                        : "Voir les nouveautés",
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                      fontSize: 14,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                  Icon(
                                    _showChangelog
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                    color: Colors.white.withValues(alpha: 0.8),
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                              child: _showChangelog
                                  ? Container(
                                      margin: const EdgeInsets.only(top: 12),
                                      constraints: const BoxConstraints(
                                        maxHeight: 350,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: ShaderMask(
                                        shaderCallback: (Rect bounds) {
                                          return LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.white,
                                              Colors.white,
                                              Colors.transparent,
                                            ],
                                            stops: const [0.0, 0.1, 0.9, 1.0],
                                          ).createShader(bounds);
                                        },
                                        blendMode: BlendMode.dstIn,
                                        child: SingleChildScrollView(
                                          padding: const EdgeInsets.all(16.0),
                                          physics:
                                              const BouncingScrollPhysics(),
                                          child: Text(
                                            widget.releaseNotes,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],

                          if (_isDownloading) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: _progress > 0 ? _progress : null,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.1,
                                ),
                                color: Colors.white,
                                minHeight: 6,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _status,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],

                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (!_isDownloading)
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text(
                                    "Plus tard",
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              if (!_isDownloading)
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.15,
                                    ),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                  ),
                                  onPressed: _downloadAndInstall,
                                  child: const Text("Mettre à jour"),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
