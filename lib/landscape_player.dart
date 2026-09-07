import 'package:musicality/ui/widgets/hyper_os_slider.dart';
import 'package:musicality/core/models.dart';

import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:audio_service/audio_service.dart';

class LandscapeStereoPlayer extends StatefulWidget {
  final AudioHandler audioHandler;
  final List<LyricLine> lyrics;
  final Stream<PositionData> positionStream;
  final MediaItem? item;
  final String localFilePath;
  final List<Color> themeColors;

  const LandscapeStereoPlayer({
    super.key,
    required this.audioHandler,
    required this.lyrics,
    required this.positionStream,
    required this.item,
    required this.localFilePath,
    required this.themeColors,
  });

  @override
  State<LandscapeStereoPlayer> createState() => _LandscapeStereoPlayerState();
}

class _LandscapeStereoPlayerState extends State<LandscapeStereoPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _visualizerController;
  Waveform? _waveform;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _visualizerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _extractWaveform();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _visualizerController.dispose();
    super.dispose();
  }

  Future<void> _extractWaveform() async {
    try {
      if (widget.localFilePath.isNotEmpty) {
        final audioFile = File(widget.localFilePath);
        if (await audioFile.exists()) {
          final waveFile = File('${audioFile.path}.wave');
          if (!await waveFile.exists()) {
            final progressStream = JustWaveform.extract(
              audioInFile: audioFile,
              waveOutFile: waveFile,
            );
            await progressStream.last;
          }
          final waveform = await JustWaveform.parse(waveFile);
          if (mounted) {
            setState(() {
              _waveform = waveform;
            });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint("Waveform error: $e");
    }

    // Fallback dummy waveform for visualizer when streaming
    if (mounted) {
      final List<int> dummyData = List.generate(1000, (index) {
        return (5000 + 15000 * math.sin(index * 0.1)).abs().toInt();
      });
      setState(() {
        _waveform = Waveform(
          version: 1,
          flags: 0,
          sampleRate: 44100,
          samplesPerPixel: 256,
          length: 1000,
          data: dummyData,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background
          Container(
            decoration: BoxDecoration(
              image: widget.item?.artUri != null
                  ? DecorationImage(
                      image:
                          (widget.item!.artUri!.scheme == 'file'
                                  ? FileImage(
                                      File(widget.item!.artUri!.toFilePath()),
                                    )
                                  : NetworkImage(
                                      widget.item!.artUri!.toString(),
                                    ))
                              as ImageProvider,
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(color: Colors.black.withAlpha(100)),
            ),
          ),

          // Stereo Visualizer
          StreamBuilder<PlaybackState>(
            stream: widget.audioHandler.playbackState,
            builder: (context, playbackSnapshot) {
              final isPlaying = playbackSnapshot.data?.playing ?? false;
              return StreamBuilder<PositionData>(
                stream: widget.positionStream,
                builder: (context, positionSnapshot) {
                  final position =
                      positionSnapshot.data?.position ?? Duration.zero;
                  final duration =
                      positionSnapshot.data?.duration ?? Duration.zero;
                  return AnimatedBuilder(
                    animation: _visualizerController,
                    builder: (context, child) {
                      double intensityLeft = 1.0;
                      double intensityRight = 1.0;
                      double dt =
                          _visualizerController.value - RippleState.lastTime;
                      if (dt < 0) dt += 1.0;
                      RippleState.lastTime = _visualizerController.value;
                      double speed = 0.6 * dt;

                      if (_waveform != null &&
                          _waveform!.data.isNotEmpty &&
                          duration.inMilliseconds > 0 &&
                          isPlaying) {
                        final double progress =
                            position.inMilliseconds / duration.inMilliseconds;
                        final int index = (progress * _waveform!.data.length)
                            .floor()
                            .clamp(0, _waveform!.data.length - 1);
                        int windowSize = 5;

                        double sum = 0;
                        int count = 0;
                        for (
                          int i = index - windowSize;
                          i <= index + windowSize;
                          i++
                        ) {
                          if (i >= 0 && i < _waveform!.data.length) {
                            sum += _waveform!.data[i].abs();
                            count++;
                          }
                        }
                        double averageAmp = count > 0 ? (sum / count) : 0;
                        intensityLeft =
                            1.0 +
                            ((averageAmp / 32768.0).clamp(0.0, 1.0) * 2.0);

                        final int indexRight = (index + 2).clamp(
                          0,
                          _waveform!.data.length - 1,
                        );
                        double sumRight = 0;
                        int countRight = 0;
                        for (
                          int i = indexRight - windowSize;
                          i <= indexRight + windowSize;
                          i++
                        ) {
                          if (i >= 0 && i < _waveform!.data.length) {
                            sumRight += _waveform!.data[i].abs();
                            countRight++;
                          }
                        }
                        double averageAmpRight = countRight > 0
                            ? (sumRight / countRight)
                            : 0;
                        intensityRight =
                            1.0 +
                            ((averageAmpRight / 32768.0).clamp(0.0, 1.0) * 2.0);

                        // True Peak Detection
                        if (intensityLeft > 1.25 &&
                            intensityLeft >
                                RippleState.lastIntensityLeft + 0.05) {
                          if (RippleState.leftProgress.isEmpty ||
                              RippleState.leftProgress.last > 0.15) {
                            RippleState.leftProgress.add(0.0);
                            RippleState.leftIntensities.add(intensityLeft);
                          }
                        }
                        if (intensityRight > 1.25 &&
                            intensityRight >
                                RippleState.lastIntensityRight + 0.05) {
                          if (RippleState.rightProgress.isEmpty ||
                              RippleState.rightProgress.last > 0.15) {
                            RippleState.rightProgress.add(0.0);
                            RippleState.rightIntensities.add(intensityRight);
                          }
                        }
                        RippleState.lastIntensityLeft = intensityLeft;
                        RippleState.lastIntensityRight = intensityRight;
                      }

                      if (isPlaying) {
                        for (
                          int i = RippleState.leftProgress.length - 1;
                          i >= 0;
                          i--
                        ) {
                          RippleState.leftProgress[i] += speed;
                          if (RippleState.leftProgress[i] >= 1.0) {
                            RippleState.leftProgress.removeAt(i);
                            RippleState.leftIntensities.removeAt(i);
                          }
                        }
                        for (
                          int i = RippleState.rightProgress.length - 1;
                          i >= 0;
                          i--
                        ) {
                          RippleState.rightProgress[i] += speed;
                          if (RippleState.rightProgress[i] >= 1.0) {
                            RippleState.rightProgress.removeAt(i);
                            RippleState.rightIntensities.removeAt(i);
                          }
                        }
                      }

                      List<Widget> ripples = [];
                      void addRipple(double p, double intensity, bool isLeft) {
                        double r = 60.0 + (p * 250.0);
                        double fadeOut = 1.0 - p;
                        double strokeW = 15.0;

                        ripples.add(
                          Positioned.fill(
                            child: ClipPath(
                              clipper: RingClipper(
                                radius: r,
                                thickness: strokeW,
                                isLeft: isLeft,
                              ),
                              child: BackdropFilter(
                                filter: ImageFilter.matrix(
                                  Matrix4.diagonal3Values(
                                    1.03,
                                    1.03,
                                    1.0,
                                  ).storage,
                                ),
                                child: CustomPaint(
                                  painter: _RippleStrokePainter(
                                    radius: r,
                                    thickness: strokeW,
                                    isLeft: isLeft,
                                    color: Colors.white.withAlpha(
                                      (90 * fadeOut * intensity)
                                          .clamp(0, 255)
                                          .toInt(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      for (
                        int i = 0;
                        i < RippleState.leftProgress.length;
                        i++
                      ) {
                        addRipple(
                          RippleState.leftProgress[i],
                          RippleState.leftIntensities[i],
                          true,
                        );
                      }
                      for (
                        int i = 0;
                        i < RippleState.rightProgress.length;
                        i++
                      ) {
                        addRipple(
                          RippleState.rightProgress[i],
                          RippleState.rightIntensities[i],
                          false,
                        );
                      }

                      return Stack(children: ripples);
                    },
                  );
                },
              );
            },
          ),

          // Lyrics in the center
          Align(
            alignment: Alignment.center,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 100),
                child: widget.lyrics.isEmpty
                    ? const Center(
                        child: Text(
                          "Instrumental",
                          style: TextStyle(color: Colors.white54, fontSize: 24),
                        ),
                      )
                    : StreamBuilder<PositionData>(
                        stream: widget.positionStream,
                        builder: (context, snapshot) {
                          final position =
                              snapshot.data?.position ?? Duration.zero;
                          String currentLine = "";
                          for (int i = 0; i < widget.lyrics.length; i++) {
                            if (position >= widget.lyrics[i].time) {
                              if (i == widget.lyrics.length - 1 ||
                                  position < widget.lyrics[i + 1].time) {
                                currentLine = widget.lyrics[i].text;
                                break;
                              }
                            }
                          }
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder:
                                (Widget child, Animation<double> animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  );
                                },
                            child: Text(
                              currentLine,
                              key: ValueKey<String>(currentLine),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                                height: 1.3,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),

          // Controls & Info
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Controls Row with Slider in the middle
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Album Art & Info
                        Expanded(
                          flex: 3,
                          child: StreamBuilder<MediaItem?>(
                            stream: widget.audioHandler.mediaItem,
                            builder: (context, snapshot) {
                              final song = snapshot.data;
                              if (song == null) return const SizedBox.shrink();
                              return Row(
                                children: [
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      image: song.artUri != null
                                          ? DecorationImage(
                                              image:
                                                  (song.artUri!.scheme == 'file'
                                                          ? FileImage(
                                                              File(
                                                                song.artUri!
                                                                    .toFilePath(),
                                                              ),
                                                            )
                                                          : NetworkImage(
                                                              song.artUri!
                                                                  .toString(),
                                                            ))
                                                      as ImageProvider,
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          song.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          song.artist ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Slider
                        Expanded(
                          flex: 4,
                          child: StreamBuilder<PositionData>(
                            stream: widget.positionStream,
                            initialData: PositionData(
                              Duration.zero,
                              Duration.zero,
                              Duration.zero,
                            ),
                            builder: (context, posSnapshot) {
                              final position = posSnapshot.data!.position;
                              final duration = posSnapshot.data!.duration;
                              return HyperOSSlider(
                                position: position,
                                duration: duration,
                                onSeek: (target) {
                                  widget.audioHandler.seek(target);
                                },
                                gradientColors: widget.themeColors,
                              );
                            },
                          ),
                        ),

                        const SizedBox(width: 32),

                        // Controls
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () =>
                                  widget.audioHandler.skipToPrevious(),
                              icon: const Icon(CupertinoIcons.backward_fill),
                              color: Colors.white70,
                              iconSize: 28,
                            ),
                            const SizedBox(width: 16),
                            StreamBuilder<PlaybackState>(
                              stream: widget.audioHandler.playbackState,
                              builder: (context, snapshot) {
                                final isPlaying =
                                    snapshot.data?.playing ?? false;
                                return IconButton(
                                  onPressed: () {
                                    if (isPlaying) {
                                      widget.audioHandler.pause();
                                    } else {
                                      widget.audioHandler.play();
                                    }
                                  },
                                  icon: Icon(
                                    isPlaying
                                        ? CupertinoIcons.pause_fill
                                        : CupertinoIcons.play_fill,
                                  ),
                                  color: Colors.white,
                                  iconSize: 42,
                                );
                              },
                            ),
                            const SizedBox(width: 16),
                            IconButton(
                              onPressed: () => widget.audioHandler.skipToNext(),
                              icon: const Icon(CupertinoIcons.forward_fill),
                              color: Colors.white70,
                              iconSize: 28,
                            ),
                            const SizedBox(width: 32),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(CupertinoIcons.clear),
                              color: Colors.white38,
                              iconSize: 24,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // High Quality Icon Top Right
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Icon(
                  CupertinoIcons.bolt_fill,
                  color: Colors.greenAccent.shade400,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RingClipper extends CustomClipper<Path> {
  final double radius;
  final double thickness;
  final bool isLeft;

  RingClipper({
    required this.radius,
    required this.thickness,
    required this.isLeft,
  });

  @override
  Path getClip(Size size) {
    final center = isLeft
        ? Offset(0, size.height / 2)
        : Offset(size.width, size.height / 2);
    return Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..addOval(Rect.fromCircle(center: center, radius: radius - thickness))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(RingClipper oldClipper) =>
      radius != oldClipper.radius ||
      thickness != oldClipper.thickness ||
      isLeft != oldClipper.isLeft;
}

class RippleState {
  static List<double> leftProgress = [];
  static List<double> leftIntensities = [];
  static List<double> rightProgress = [];
  static List<double> rightIntensities = [];
  static double lastTime = 0.0;
  static double lastIntensityLeft = 0.0;
  static double lastIntensityRight = 0.0;
}

class _RippleStrokePainter extends CustomPainter {
  final double radius;
  final double thickness;
  final bool isLeft;
  final Color color;

  _RippleStrokePainter({
    required this.radius,
    required this.thickness,
    required this.isLeft,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = isLeft
        ? Offset(0, size.height / 2)
        : Offset(size.width, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;

    canvas.drawCircle(center, radius - thickness / 2, paint);
  }

  @override
  bool shouldRepaint(covariant _RippleStrokePainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.thickness != thickness ||
        oldDelegate.isLeft != isLeft ||
        oldDelegate.color != color;
  }
}
