import 'package:musicality/ui/widgets/hyper_os_slider.dart';
import 'package:musicality/core/models.dart';
import 'package:musicality/core/globals.dart';

import 'dart:async';
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
  StreamSubscription<MediaItem?>? _mediaItemSub;
  StreamSubscription<PositionData>? _positionSub;
  StreamSubscription<PlaybackState>? _playbackSub;
  MediaItem? _currentItem;
  List<LyricLine> _currentLyrics = [];
  late List<Color> _currentThemeColors;

  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<int> _activeIndexNotifier = ValueNotifier<int>(-1);
  Duration _lastKnownPosition = Duration.zero;
  DateTime _lastPositionUpdate = DateTime.now();
  bool _isPlaying = false;

  bool get _hasNoLyrics {
    if (_currentLyrics.isEmpty) return true;
    if (_currentLyrics.length == 1) {
      final text = _currentLyrics.first.text.trim().toLowerCase();
      if (text.contains('indisponible') ||
          text.contains('pas de parole') ||
          text.contains('instrumental') ||
          text.isEmpty) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    _currentLyrics = widget.lyrics;
    _currentThemeColors = widget.themeColors;

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _visualizerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _visualizerController.addListener(_onVisualizerTick);

    _extractWaveform(widget.localFilePath);

    _playbackSub = widget.audioHandler.playbackState.listen((state) {
      _isPlaying = state.playing;
    });

    _positionSub = widget.positionStream.listen((data) {
      _lastKnownPosition = data.position;
      _lastPositionUpdate = DateTime.now();
      _positionNotifier.value = data.position;
      _updateActiveIndex(data.position);
    });

    _mediaItemSub = widget.audioHandler.mediaItem.listen((item) {
      if (item != null && item.id != _currentItem?.id) {
        if (mounted) {
          setState(() {
            _currentItem = item;
            _currentThemeColors = getAlbumGradientColors(item);
          });
          _activeIndexNotifier.value = -1;
          _extractWaveform(SongDownloadService.getLocalFilePath(item));
          _loadLyrics(item);
        }
      }
    });
  }

  void _onVisualizerTick() {
    if (_isPlaying && !_hasNoLyrics) {
      final elapsed = DateTime.now().difference(_lastPositionUpdate);
      final current = _lastKnownPosition + elapsed;
      _positionNotifier.value = current;
      _updateActiveIndex(current);
    }
  }

  void _updateActiveIndex(Duration position) {
    if (_hasNoLyrics) {
      if (_activeIndexNotifier.value != -1) {
        _activeIndexNotifier.value = -1;
      }
      return;
    }
    int newIndex = -1;
    for (int i = 0; i < _currentLyrics.length; i++) {
      if (position >= _currentLyrics[i].time) {
        if (i == _currentLyrics.length - 1 ||
            position < _currentLyrics[i + 1].time) {
          newIndex = i;
          break;
        }
      }
    }
    if (_activeIndexNotifier.value != newIndex) {
      _activeIndexNotifier.value = newIndex;
    }
  }

  Future<void> _loadLyrics(MediaItem item) async {
    final cached = LyricsService.getCached(item.id);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _currentLyrics = cached;
        });
        _updateActiveIndex(_positionNotifier.value);
      }
      return;
    }
    final lyrics = await LyricsService.fetchLyrics(item);
    if (mounted && _currentItem?.id == item.id) {
      setState(() {
        _currentLyrics = lyrics;
      });
      _updateActiveIndex(_positionNotifier.value);
    }
  }

  @override
  void dispose() {
    _visualizerController.removeListener(_onVisualizerTick);
    _mediaItemSub?.cancel();
    _positionSub?.cancel();
    _playbackSub?.cancel();
    _positionNotifier.dispose();
    _activeIndexNotifier.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _visualizerController.dispose();
    super.dispose();
  }

  Future<void> _extractWaveform(String path) async {
    try {
      if (path.isNotEmpty) {
        final audioFile = File(path);
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
              image: _currentItem?.artUri != null
                  ? DecorationImage(
                      image:
                          (_currentItem!.artUri!.scheme == 'file'
                                  ? FileImage(
                                      File(_currentItem!.artUri!.toFilePath()),
                                    )
                                  : NetworkImage(
                                      _currentItem!.artUri!.toString(),
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
                padding: const EdgeInsets.symmetric(horizontal: 80),
                child: _hasNoLyrics
                    ? Center(
                        key: const ValueKey('no_lyrics'),
                        child: Text(
                          _currentLyrics.isNotEmpty
                              ? _currentLyrics.first.text
                              : "Instrumental",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _getUnlitColor(_currentThemeColors)
                                .withValues(alpha: 0.8),
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : ValueListenableBuilder<int>(
                        valueListenable: _activeIndexNotifier,
                        builder: (context, activeIndex, _) {
                          final LyricLine? activeLine = (activeIndex >= 0 &&
                                  activeIndex < _currentLyrics.length)
                              ? _currentLyrics[activeIndex]
                              : null;

                          final glowColor = _currentThemeColors.isNotEmpty
                              ? _currentThemeColors.first
                              : Colors.cyanAccent;
                          final unlitColor =
                              _getUnlitColor(_currentThemeColors);

                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder:
                                (Widget child, Animation<double> animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                            child: activeLine == null
                                ? const SizedBox.shrink(
                                    key: ValueKey<int>(-1),
                                  )
                                : _LandscapeLyricLineView(
                                    key: ValueKey<int>(activeIndex),
                                    line: activeLine,
                                    positionNotifier: _positionNotifier,
                                    glowColor: glowColor,
                                    unlitColor: unlitColor,
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
                                  _lastKnownPosition = target;
                                  _lastPositionUpdate = DateTime.now();
                                  _positionNotifier.value = target;
                                  _updateActiveIndex(target);
                                  widget.audioHandler.seek(target);
                                },
                                gradientColors: _currentThemeColors,
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

List<Shadow> _buildGlowShadows(Color glowColor, double factor) {
  if (isBatterySaverEnabledNotifier.value || factor <= 0.01) return const [];
  final f = factor.clamp(0.0, 1.0);
  return [
    Shadow(
      color: Colors.white.withValues(alpha: (f * 0.95).clamp(0.0, 1.0)),
      blurRadius: (8.0 * f).clamp(0.1, 8.0),
    ),
    Shadow(
      color: glowColor.withValues(alpha: (f * 0.85).clamp(0.0, 1.0)),
      blurRadius: (20.0 * f).clamp(0.1, 20.0),
    ),
    Shadow(
      color: glowColor.withValues(alpha: (f * 0.35).clamp(0.0, 1.0)),
      blurRadius: (30.0 * f).clamp(0.1, 30.0),
    ),
  ];
}

Color _getUnlitColor(List<Color> themeColors) {
  if (themeColors.isNotEmpty) {
    return Color.lerp(themeColors.first, Colors.white, 0.45)!;
  }
  return Colors.white70;
}

double _calculateFontSize(String text) {
  if (text.length > 55) return 28.0;
  if (text.length > 35) return 34.0;
  return 40.0;
}

class _LandscapeLyricLineView extends StatelessWidget {
  final LyricLine line;
  final ValueNotifier<Duration> positionNotifier;
  final Color glowColor;
  final Color unlitColor;

  const _LandscapeLyricLineView({
    super.key,
    required this.line,
    required this.positionNotifier,
    required this.glowColor,
    required this.unlitColor,
  });

  @override
  Widget build(BuildContext context) {
    final double fontSize = _calculateFontSize(line.text);
    final bool hasWords = line.words.isNotEmpty;

    if (hasWords) {
      return RepaintBoundary(
        child: Wrap(
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: (fontSize * 0.26).clamp(8.0, 14.0),
          runSpacing: 8.0,
          children: List.generate(line.words.length, (index) {
            final word = line.words[index];
            return _LandscapeKaraokeWord(
              key: ValueKey(word.start.inMilliseconds),
              word: word,
              positionNotifier: positionNotifier,
              glowColor: glowColor,
              unlitColor: unlitColor.withValues(alpha: 0.45),
              fontSize: fontSize,
            );
          }),
        ),
      );
    }

    return _LandscapePlainLineView(
      text: line.text,
      glowColor: glowColor,
      unlitColor: unlitColor,
      fontSize: fontSize,
    );
  }
}

enum _WordState { unsung, singing, sung }

class _LandscapeKaraokeWord extends StatefulWidget {
  final LyricWord word;
  final ValueNotifier<Duration> positionNotifier;
  final Color glowColor;
  final Color unlitColor;
  final double fontSize;

  const _LandscapeKaraokeWord({
    super.key,
    required this.word,
    required this.positionNotifier,
    required this.glowColor,
    required this.unlitColor,
    required this.fontSize,
  });

  @override
  State<_LandscapeKaraokeWord> createState() => _LandscapeKaraokeWordState();
}

class _LandscapeKaraokeWordState extends State<_LandscapeKaraokeWord> {
  _WordState _state = _WordState.unsung;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _updateState(widget.positionNotifier.value, initial: true);
    widget.positionNotifier.addListener(_onPositionChanged);
  }

  @override
  void didUpdateWidget(_LandscapeKaraokeWord oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionNotifier != widget.positionNotifier) {
      oldWidget.positionNotifier.removeListener(_onPositionChanged);
      widget.positionNotifier.addListener(_onPositionChanged);
      _updateState(widget.positionNotifier.value, initial: true);
    }
  }

  @override
  void dispose() {
    widget.positionNotifier.removeListener(_onPositionChanged);
    super.dispose();
  }

  void _onPositionChanged() {
    _updateState(widget.positionNotifier.value);
  }

  void _updateState(Duration pos, {bool initial = false}) {
    final start = widget.word.start;
    final end = widget.word.end;

    if (pos < start) {
      if (_state != _WordState.unsung || initial) {
        if (!initial && mounted) {
          setState(() {
            _state = _WordState.unsung;
            _progress = 0.0;
          });
        } else {
          _state = _WordState.unsung;
          _progress = 0.0;
        }
      }
    } else if (pos >= end) {
      if (_state != _WordState.sung || initial) {
        if (!initial && mounted) {
          setState(() {
            _state = _WordState.sung;
            _progress = 1.0;
          });
        } else {
          _state = _WordState.sung;
          _progress = 1.0;
        }
      }
    } else {
      final elapsed = (pos - start).inMilliseconds;
      final duration = (end - start).inMilliseconds.clamp(1, 10000);
      final newProgress = (elapsed / duration).clamp(0.0, 1.0);
      if (mounted) {
        setState(() {
          _state = _WordState.singing;
          _progress = newProgress;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseTextStyle = TextStyle(
      fontSize: widget.fontSize,
      fontWeight: FontWeight.bold,
      height: 1.3,
    );

    // 1. Mot non encore chanté : couleur unlit atténuée
    if (_state == _WordState.unsung || _progress <= 0.005) {
      return Text(
        widget.word.text,
        style: baseTextStyle.copyWith(color: widget.unlitColor),
      );
    }

    // 2. Mot entièrement chanté : blanc éclatant avec aura lumineuse
    if (_state == _WordState.sung || _progress >= 0.995) {
      final shadows = _buildGlowShadows(widget.glowColor, 1.0);
      return Text(
        widget.word.text,
        style: baseTextStyle.copyWith(
          color: Colors.white,
          shadows: shadows,
        ),
      );
    }

    // 3. Mot en cours de chant actif : balayage lumineux par gradient + ombre de lueur
    final shadows = _buildGlowShadows(widget.glowColor, _progress);
    final glowWidget = shadows.isNotEmpty
        ? Text(
            widget.word.text,
            style: baseTextStyle.copyWith(
              color: Colors.transparent,
              shadows: shadows,
            ),
          )
        : null;

    final litWidget = Text(
      widget.word.text,
      style: baseTextStyle.copyWith(
        color: Colors.white,
        shadows: const [],
      ),
    );
    final unlitWidget = Text(
      widget.word.text,
      style: baseTextStyle.copyWith(color: widget.unlitColor),
    );

    return Stack(
      children: [
        ?glowWidget,
        unlitWidget,
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            colors: const [
              Colors.white,
              Colors.white,
              Colors.transparent,
              Colors.transparent,
            ],
            stops: [0.0, _progress, _progress, 1.0],
          ).createShader(bounds),
          child: litWidget,
        ),
      ],
    );
  }
}

class _LandscapePlainLineView extends StatefulWidget {
  final String text;
  final Color glowColor;
  final Color unlitColor;
  final double fontSize;

  const _LandscapePlainLineView({
    required this.text,
    required this.glowColor,
    required this.unlitColor,
    required this.fontSize,
  });

  @override
  State<_LandscapePlainLineView> createState() => _LandscapePlainLineViewState();
}

class _LandscapePlainLineViewState extends State<_LandscapePlainLineView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTextStyle = TextStyle(
      fontSize: widget.fontSize,
      fontWeight: FontWeight.bold,
      height: 1.3,
    );

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final progress = _animation.value;
        final shadows = _buildGlowShadows(widget.glowColor, progress);
        final color = Color.lerp(
          widget.unlitColor.withValues(alpha: 0.55),
          Colors.white,
          progress,
        )!;

        return Text(
          widget.text,
          textAlign: TextAlign.center,
          style: baseTextStyle.copyWith(
            color: color,
            shadows: shadows,
          ),
        );
      },
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
