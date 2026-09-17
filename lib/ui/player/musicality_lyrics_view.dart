import 'package:musicality/core/globals.dart';
import 'package:musicality/core/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'dart:async';
import 'dart:ui';

class MusicalityLyricsView extends StatefulWidget {
  final String? songId;
  final List<LyricLine> lyrics;
  final Stream<PositionData> positionStream;
  final List<Color> themeColors;
  final bool isExpanded;

  const MusicalityLyricsView({
    super.key,
    this.songId,
    required this.lyrics,
    required this.positionStream,
    this.themeColors = const [Colors.purple, Colors.blue],
    this.isExpanded = true,
  });

  @override
  State<MusicalityLyricsView> createState() => _MusicalityLyricsViewState();
}

class _MusicalityLyricsViewState extends State<MusicalityLyricsView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<int> _activeIndexNotifier = ValueNotifier<int>(-1);
  StreamSubscription<PositionData>? _positionSubscription;
  List<GlobalKey> _lyricKeys = [];

  late final Ticker _ticker;
  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier<Duration>(Duration.zero);
  Duration _lastKnownPosition = Duration.zero;
  DateTime _lastPositionUpdate = DateTime.now();
  Timer? _autoScrollResumeTimer;
  bool _isPlaying = false;
  bool _isUserInteracting = false;

  bool _hasNoLyricsCached = true;
  bool _isUnsyncedLyricsCached = true;

  bool get _hasNoLyrics => _hasNoLyricsCached;
  bool get _isUnsyncedLyrics => _isUnsyncedLyricsCached;

  void _computeLyricsMetadata() {
    if (widget.lyrics.isEmpty) {
      _hasNoLyricsCached = true;
      _isUnsyncedLyricsCached = true;
      return;
    }
    if (widget.lyrics.length == 1) {
      final text = widget.lyrics.first.text.trim().toLowerCase();
      if (text.contains('indisponible') ||
          text.contains('pas de parole') ||
          text.contains('instrumental') ||
          text.isEmpty) {
        _hasNoLyricsCached = true;
        _isUnsyncedLyricsCached = true;
        return;
      }
    }
    _hasNoLyricsCached = false;
    _isUnsyncedLyricsCached = widget.lyrics.every((l) => l.time == Duration.zero);
  }

  @override
  void initState() {
    super.initState();
    _computeLyricsMetadata();
    WidgetsBinding.instance.addObserver(this);
    _generateKeys();

    _ticker = createTicker((_) {
      if (_isPlaying && widget.isExpanded && !_isUnsyncedLyricsCached) {
        final elapsed = DateTime.now().difference(_lastPositionUpdate);
        final current = _lastKnownPosition + elapsed;
        _positionNotifier.value = current;
        _checkActiveIndex(current);
      }
    });

    final currentPos = globalAudioHandler.playbackState.value.position;
    _lastKnownPosition = currentPos;
    _lastPositionUpdate = DateTime.now();
    _positionNotifier.value = currentPos;
    _isPlaying = globalAudioHandler.playbackState.value.playing;
    _updateTickerState();

    if (!_hasNoLyrics) {
      _checkActiveIndex(currentPos);
    }

    _listenToPosition();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final active = _activeIndexNotifier.value;
      if (active > 0) {
        _scrollToActiveIndex(active, immediate: true, force: true);
      } else if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    });
  }

  void _updateTickerState() {
    final shouldTick = _isPlaying && widget.isExpanded && !_isUnsyncedLyricsCached;
    if (shouldTick) {
      if (!_ticker.isActive) {
        _ticker.start();
      } else {
        _ticker.muted = false;
      }
    } else {
      if (_ticker.isActive) {
        _ticker.muted = true;
      }
    }
  }

  @override
  void didUpdateWidget(MusicalityLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool songChanged = oldWidget.songId != widget.songId;
    final bool lyricsChanged = oldWidget.lyrics != widget.lyrics;

    if (songChanged || lyricsChanged) {
      _autoScrollResumeTimer?.cancel();
      _computeLyricsMetadata();
      _isUserInteracting = false;
      _generateKeys();
      final currentPos = globalAudioHandler.playbackState.value.position;
      _lastKnownPosition = currentPos;
      _lastPositionUpdate = DateTime.now();
      _positionNotifier.value = currentPos;
      _activeIndexNotifier.value = -1;
      _checkActiveIndex(currentPos);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final active = _activeIndexNotifier.value;
        if (active > 0) {
          _scrollToActiveIndex(active, immediate: true, force: true);
        } else if (_scrollController.hasClients) {
          _scrollController.jumpTo(0.0);
        }
      });
      setState(() {});
    }

    if (widget.positionStream != oldWidget.positionStream) {
      _positionSubscription?.cancel();
      _listenToPosition();
    }

    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded && !_isUnsyncedLyrics) {
        final currentPos = globalAudioHandler.playbackState.value.position;
        _lastKnownPosition = currentPos;
        _lastPositionUpdate = DateTime.now();
        _positionNotifier.value = currentPos;
        _isUserInteracting = false;
        _checkActiveIndex(currentPos);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !widget.isExpanded) return;
          final active = _activeIndexNotifier.value;
          if (active > 0) {
            _scrollToActiveIndex(active, immediate: true, force: true);
          } else {
            _scrollToTop(immediate: true);
          }
        });

        // Activer le Ticker haute fréquence après que la transition d'ouverture (410ms) soit achevée
        Timer(const Duration(milliseconds: 380), () {
          if (mounted && widget.isExpanded) {
            _updateTickerState();
          }
        });
      } else {
        _updateTickerState();
      }
    }
  }

  void _generateKeys() {
    _lyricKeys = List.generate(widget.lyrics.length, (index) => GlobalKey());
  }

  void _listenToPosition() {
    _positionSubscription = widget.positionStream.listen((data) {
      if (!mounted || _hasNoLyrics) return;

      _lastKnownPosition = data.position;
      _lastPositionUpdate = DateTime.now();
      final wasPlaying = _isPlaying;
      _isPlaying = globalAudioHandler.playbackState.value.playing;

      if (_isPlaying != wasPlaying) {
        _updateTickerState();
      }

      if (widget.isExpanded) {
        _positionNotifier.value = data.position;
        _checkActiveIndex(data.position);
      }
    });
  }

  void _checkActiveIndex(Duration position) {
    if (_hasNoLyrics) return;

    final currentIndex = _activeIndexNotifier.value;
    if (currentIndex == -1) {
      if (widget.lyrics.isNotEmpty &&
          (position < widget.lyrics.first.time ||
           (widget.lyrics.first.time == Duration.zero &&
            position < const Duration(milliseconds: 250)))) {
        return;
      }
    } else if (currentIndex >= 0 && currentIndex < widget.lyrics.length) {
      final currentLineTime = widget.lyrics[currentIndex].time;
      final nextLineTime = (currentIndex + 1 < widget.lyrics.length)
          ? widget.lyrics[currentIndex + 1].time
          : const Duration(days: 365);
      if (position >= currentLineTime && position < nextLineTime) {
        return;
      }
    }

    int newIndex = -1;
    int left = 0;
    int right = widget.lyrics.length - 1;

    while (left <= right) {
      int mid = left + (right - left) ~/ 2;
      if (position >= widget.lyrics[mid].time) {
        newIndex = mid;
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }

    if (newIndex != _activeIndexNotifier.value) {
      _activeIndexNotifier.value = newIndex;
      if (widget.isExpanded) {
        if (!_isUserInteracting) {
          if (newIndex <= 0) {
            _scrollToTop();
          } else {
            _scrollToActiveIndex(newIndex);
          }
        }
      }
    }
  }

  void _scrollToTop({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isExpanded) return;
      if (_scrollController.hasClients) {
        if (immediate) {
          _scrollController.jumpTo(0.0);
        } else {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
        }
      }
    });
  }

  void _scrollToActiveIndex(int targetIndex, {bool immediate = false, bool force = false}) {
    if (targetIndex <= 0) {
      _scrollToTop(immediate: immediate);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || targetIndex < 0 || targetIndex >= _lyricKeys.length) {
        return;
      }

      if (!widget.isExpanded) return;

      if (!force && _isUserInteracting) {
        return;
      }

      final keyContext = _lyricKeys[targetIndex].currentContext;
      if (keyContext != null && keyContext.mounted) {
        Scrollable.ensureVisible(
          keyContext,
          alignment: 0.30,
          duration:
              immediate ? Duration.zero : const Duration(milliseconds: 500),
          curve: Curves.easeInOutCubic,
        );
      } else if (_scrollController.hasClients && widget.lyrics.isNotEmpty) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final approxOffset = (targetIndex / widget.lyrics.length) * maxScroll;
        if (immediate) {
          _scrollController.jumpTo(approxOffset.clamp(0.0, maxScroll));
        } else {
          _scrollController.animateTo(
            approxOffset.clamp(0.0, maxScroll),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeInOutCubic,
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !widget.isExpanded) return;
          final retryContext = _lyricKeys[targetIndex].currentContext;
          if (retryContext != null && retryContext.mounted) {
            Scrollable.ensureVisible(
              retryContext,
              alignment: 0.30,
              duration:
                  immediate ? Duration.zero : const Duration(milliseconds: 350),
              curve: Curves.easeInOutCubic,
            );
          }
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      if (widget.isExpanded && !_isUnsyncedLyrics) {
        if (!_ticker.isActive) {
          _ticker.start();
        } else {
          _ticker.muted = false;
        }
      }
    } else {
      if (_ticker.isActive) {
        _ticker.muted = true;
      }
    }
  }

  @override
  void dispose() {
    _autoScrollResumeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _positionNotifier.dispose();
    _activeIndexNotifier.dispose();
    _positionSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Color _getUnlitColor() {
    if (widget.themeColors.isNotEmpty) {
      return Color.lerp(widget.themeColors.first, Colors.white, 0.45)!;
    }
    return Colors.white70;
  }

  @override
  Widget build(BuildContext context) {
    final unlitColor = _getUnlitColor();

    if (_hasNoLyrics) {
      final String message = (widget.lyrics.isNotEmpty &&
              !widget.lyrics.first.text.toLowerCase().contains('indisponible'))
          ? widget.lyrics.first.text
          : "Paroles indisponibles";
      final gradientColors = widget.themeColors.isNotEmpty
          ? (widget.themeColors.length == 1
              ? [widget.themeColors.first, widget.themeColors.first]
              : widget.themeColors)
          : [Colors.cyanAccent, Colors.blueAccent];

      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              return LinearGradient(
                colors: gradientColors,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: getGradientStops(gradientColors.length),
              ).createShader(
                Rect.fromLTWH(
                  0,
                  0,
                  bounds.width,
                  bounds.height,
                ),
              );
            },
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                height: 1.4,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      );
    }

    final screenHeight = MediaQuery.of(context).size.height;
    final glowColor = widget.themeColors.isNotEmpty
        ? widget.themeColors.first
        : Colors.cyanAccent;

    return RepaintBoundary(
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [
              0.0,
              0.15,
              0.75,
              1.0,
            ],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is UserScrollNotification) {
              if (notification.direction != ScrollDirection.idle) {
                _isUserInteracting = true;
                _autoScrollResumeTimer?.cancel();
              }
            } else if (notification is ScrollStartNotification) {
              if (notification.dragDetails != null) {
                _isUserInteracting = true;
                _autoScrollResumeTimer?.cancel();
              }
            } else if (notification is ScrollUpdateNotification) {
              if (notification.dragDetails != null) {
                _isUserInteracting = true;
                _autoScrollResumeTimer?.cancel();
              }
            } else if (notification is ScrollEndNotification) {
              // On ne relance le timer de recentrage QUE si l'utilisateur était en train d'interagir manuellement
              if (_isUserInteracting) {
                _autoScrollResumeTimer?.cancel();
                _autoScrollResumeTimer =
                    Timer(const Duration(milliseconds: 3000), () {
                  if (!mounted || !widget.isExpanded) return;
                  _isUserInteracting = false;
                  final target = _activeIndexNotifier.value;
                  if (target >= 0) {
                    _scrollToActiveIndex(target, force: true);
                  }
                });
              }
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            scrollCacheExtent: const ScrollCacheExtent.pixels(800.0),
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(
              top: screenHeight * 0.22,
              bottom: screenHeight * 0.55,
            ),
            itemCount: widget.lyrics.length,
            itemBuilder: (context, index) {
              final line = widget.lyrics[index];

              return KeyedSubtree(
                key: _lyricKeys[index],
                child: _LyricLineItem(
                  index: index,
                  line: line,
                  activeIndexNotifier: _activeIndexNotifier,
                  positionNotifier: _positionNotifier,
                  glowColor: glowColor,
                  unlitColor: unlitColor,
                  onTap: () {
                    _isUserInteracting = false;
                    _autoScrollResumeTimer?.cancel();
                    globalAudioHandler.seek(line.time);
                    _scrollToActiveIndex(index, force: true);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

List<Shadow> _buildGlowShadows(Color glowColor, double factor) {
  if (isBatterySaverEnabledNotifier.value || factor <= 0.05) return const [];
  final f = factor.clamp(0.0, 1.0);
  return [
    Shadow(
      color: Colors.white.withValues(alpha: (f * 0.7).clamp(0.0, 1.0)),
      blurRadius: 4.0,
    ),
    Shadow(
      color: glowColor.withValues(alpha: (f * 0.5).clamp(0.0, 1.0)),
      blurRadius: 8.0,
    ),
  ];
}

class _LyricLineItem extends StatefulWidget {
  final int index;
  final LyricLine line;
  final ValueNotifier<int> activeIndexNotifier;
  final ValueNotifier<Duration> positionNotifier;
  final Color glowColor;
  final Color unlitColor;
  final VoidCallback onTap;

  const _LyricLineItem({
    required this.index,
    required this.line,
    required this.activeIndexNotifier,
    required this.positionNotifier,
    required this.glowColor,
    required this.unlitColor,
    required this.onTap,
  });

  @override
  State<_LyricLineItem> createState() => _LyricLineItemState();
}

class _LyricLineItemState extends State<_LyricLineItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    _isActive = widget.activeIndexNotifier.value == widget.index;
    _controller = AnimationController(
      vsync: this,
      value: _isActive ? 1.0 : 0.0,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    widget.activeIndexNotifier.addListener(_onActiveIndexChanged);
  }

  void _onActiveIndexChanged() {
    final nowActive = widget.activeIndexNotifier.value == widget.index;
    if (nowActive != _isActive) {
      setState(() {
        _isActive = nowActive;
      });
      if (_isActive) {
        _controller.animateTo(
          1.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      } else {
        _controller.animateTo(
          0.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
        );
      }
    }
  }

  @override
  void didUpdateWidget(covariant _LyricLineItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeIndexNotifier != oldWidget.activeIndexNotifier) {
      oldWidget.activeIndexNotifier.removeListener(_onActiveIndexChanged);
      widget.activeIndexNotifier.addListener(_onActiveIndexChanged);
      _onActiveIndexChanged();
    }
    if (widget.line != oldWidget.line || widget.index != oldWidget.index) {
      final bool nowActive = widget.activeIndexNotifier.value == widget.index;
      _isActive = nowActive;
      _controller.stop();
      _controller.value = nowActive ? 1.0 : 0.0;
    }
  }

  @override
  void dispose() {
    widget.activeIndexNotifier.removeListener(_onActiveIndexChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final progress = _animation.value;
        final currentOpacity = lerpDouble(0.40, 1.0, progress)!;
        final effectiveUnlitColor =
            widget.unlitColor.withValues(alpha: currentOpacity);

        return ValueListenableBuilder<bool>(
          valueListenable: isBatterySaverEnabledNotifier,
          builder: (context, isBatterySaver, _) {
            final currentBlur = isBatterySaver
                ? 0.0
                : lerpDouble(1.3, 0.0, progress)!;

            final Widget renderedLine;
            final bool hasWords = widget.line.words.isNotEmpty;

            if (_isActive) {
              renderedLine = hasWords
                  ? _KaraokeLineWidget(
                      line: widget.line,
                      isActive: true,
                      positionNotifier: widget.positionNotifier,
                      glowColor: widget.glowColor,
                      unlitColor: widget.unlitColor.withValues(alpha: 0.40),
                      lineActiveProgress: 1.0,
                    )
                  : _PlainLineWidget(
                      text: widget.line.text,
                      glowColor: widget.glowColor,
                      unlitColor: effectiveUnlitColor,
                      lineActiveProgress: progress,
                    );
            } else if (progress <= 0.001) {
              renderedLine = hasWords
                  ? _KaraokeLineWidget(
                      line: widget.line,
                      isActive: false,
                      positionNotifier: widget.positionNotifier,
                      glowColor: widget.glowColor,
                      unlitColor: effectiveUnlitColor,
                      lineActiveProgress: 0.0,
                    )
                  : _PlainLineWidget(
                      text: widget.line.text,
                      glowColor: widget.glowColor,
                      unlitColor: effectiveUnlitColor,
                      lineActiveProgress: 0.0,
                    );
            } else {
              renderedLine = hasWords
                  ? _KaraokeLineWidget(
                      line: widget.line,
                      isActive: false,
                      positionNotifier: widget.positionNotifier,
                      glowColor: widget.glowColor,
                      unlitColor: widget.unlitColor.withValues(alpha: 0.40),
                      lineActiveProgress: progress,
                    )
                  : _PlainLineWidget(
                      text: widget.line.text,
                      glowColor: widget.glowColor,
                      unlitColor: effectiveUnlitColor,
                      lineActiveProgress: progress,
                    );
            }

            final Widget contentWithBlur;
            if (currentBlur > 0.05) {
              contentWithBlur = ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: currentBlur,
                  sigmaY: currentBlur,
                  tileMode: TileMode.decal,
                ),
                child: renderedLine,
              );
            } else {
              contentWithBlur = renderedLine;
            }

            final Widget lineWidget = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 16,
                ),
                child: contentWithBlur,
              ),
            );

            return RepaintBoundary(child: lineWidget);
          },
        );
      },
    );
  }
}

class _KaraokeLineWidget extends StatelessWidget {
  final LyricLine line;
  final bool isActive;
  final ValueNotifier<Duration> positionNotifier;
  final Color glowColor;
  final Color unlitColor;
  final double lineActiveProgress;

  const _KaraokeLineWidget({
    required this.line,
    required this.isActive,
    required this.positionNotifier,
    required this.glowColor,
    required this.unlitColor,
    required this.lineActiveProgress,
  });

  @override
  Widget build(BuildContext context) {
    if (!isActive) {
      if (lineActiveProgress > 0.001) {
        final shadows = _buildGlowShadows(glowColor, lineActiveProgress);
        final wordColor =
            Color.lerp(unlitColor, Colors.white, lineActiveProgress)!;
        return Wrap(
          spacing: 7.0,
          runSpacing: 7.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: line.words.map((word) {
            return _KaraokeWord(
              text: word.text,
              lightFactor: lineActiveProgress,
              isCurrent: false,
              glowColor: glowColor,
              unlitColor: unlitColor,
              cachedFadeShadows: shadows,
              cachedFadeColor: wordColor,
            );
          }).toList(),
        );
      }
      return Wrap(
        spacing: 7.0,
        runSpacing: 7.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: line.words.map((word) {
          return _KaraokeWord(
            text: word.text,
            lightFactor: 0.0,
            isCurrent: false,
            glowColor: glowColor,
            unlitColor: unlitColor,
          );
        }).toList(),
      );
    }

    // LIGNE ACTIVE :
    return Wrap(
      spacing: 7.0,
      runSpacing: 7.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: List.generate(line.words.length, (index) {
        final word = line.words[index];
        return RepaintBoundary(
          child: _DynamicKaraokeWord(
            key: ValueKey(word.start.inMilliseconds),
            word: word,
            positionNotifier: positionNotifier,
            glowColor: glowColor,
            unlitColor: unlitColor,
          ),
        );
      }),
    );
  }
}

enum _WordState { unsung, singing, sung }

class _DynamicKaraokeWord extends StatefulWidget {
  final LyricWord word;
  final ValueNotifier<Duration> positionNotifier;
  final Color glowColor;
  final Color unlitColor;

  const _DynamicKaraokeWord({
    super.key,
    required this.word,
    required this.positionNotifier,
    required this.glowColor,
    required this.unlitColor,
  });

  @override
  State<_DynamicKaraokeWord> createState() => _DynamicKaraokeWordState();
}

class _DynamicKaraokeWordState extends State<_DynamicKaraokeWord> {
  _WordState _state = _WordState.unsung;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _updateState(widget.positionNotifier.value, initial: true);
    widget.positionNotifier.addListener(_onPositionChanged);
  }

  @override
  void didUpdateWidget(_DynamicKaraokeWord oldWidget) {
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
      final duration = (end - start).inMilliseconds.clamp(1, 5000);
      final newProgress = (elapsed / duration).clamp(0.0, 1.0);
      if (mounted) {
        if ((newProgress - _progress).abs() >= 0.003 ||
            newProgress == 1.0 ||
            newProgress == 0.0 ||
            _state != _WordState.singing) {
          setState(() {
            _state = _WordState.singing;
            _progress = newProgress;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _KaraokeWord(
      text: widget.word.text,
      lightFactor: _progress,
      isCurrent: _state == _WordState.singing,
      glowColor: widget.glowColor,
      unlitColor: widget.unlitColor,
    );
  }
}

class _HorizontalPercentClipper extends CustomClipper<Rect> {
  final double factor;
  const _HorizontalPercentClipper(this.factor);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(
      0,
      0,
      size.width * factor.clamp(0.0, 1.0),
      size.height,
    );
  }

  @override
  bool shouldReclip(_HorizontalPercentClipper oldClipper) =>
      oldClipper.factor != factor;
}

class _KaraokeWord extends StatelessWidget {
  final String text;
  final double lightFactor;
  final bool isCurrent;
  final Color glowColor;
  final Color unlitColor;
  final List<Shadow>? cachedFadeShadows;
  final Color? cachedFadeColor;

  const _KaraokeWord({
    required this.text,
    required this.lightFactor,
    required this.isCurrent,
    required this.glowColor,
    required this.unlitColor,
    this.cachedFadeShadows,
    this.cachedFadeColor,
  });

  static const TextStyle _baseTextStyle = TextStyle(
    fontSize: 27,
    fontWeight: FontWeight.bold,
    height: 1.35,
  );

  @override
  Widget build(BuildContext context) {
    // 1. Mot non encore chanté : couleur unlit propre (40% opacité)
    if (lightFactor <= 0.005) {
      return Text(
        text,
        style: _baseTextStyle.copyWith(color: unlitColor),
      );
    }

    // 2. Mot entièrement chanté : texte blanc avec aura lumineuse
    if (lightFactor >= 0.995) {
      final shadows = _buildGlowShadows(glowColor, 1.0);
      return Text(
        text,
        style: _baseTextStyle.copyWith(
          color: Colors.white,
          shadows: shadows,
        ),
      );
    }

    // 3. Ligne qui se termine (estompage progressif de la couleur)
    if (!isCurrent) {
      final wordColor = cachedFadeColor ??
          Color.lerp(unlitColor, Colors.white, lightFactor)!;
      return Text(
        text,
        style: _baseTextStyle.copyWith(
          color: wordColor,
        ),
      );
    }

    // 4. Mot en cours de chant actif (sweep fluide de gauche à droite uniquement sur ce mot précis)
    final shadows = _buildGlowShadows(
      glowColor,
      lightFactor,
    );
    final glowWidget = shadows.isNotEmpty
        ? Text(
            text,
            style: _baseTextStyle.copyWith(
              color: Colors.transparent,
              shadows: shadows,
            ),
          )
        : null;

    final litWidget = Text(
      text,
      style: _baseTextStyle.copyWith(
        color: Colors.white,
        shadows: const [],
      ),
    );
    final unlitWidget = Text(
      text,
      style: _baseTextStyle.copyWith(color: unlitColor),
    );

    return Stack(
      children: [
        ?glowWidget,
        unlitWidget,
        ClipRect(
          clipper: _HorizontalPercentClipper(lightFactor),
          child: litWidget,
        ),
      ],
    );
  }
}

class _PlainLineWidget extends StatelessWidget {
  final String text;
  final Color glowColor;
  final Color unlitColor;
  final double lineActiveProgress;

  const _PlainLineWidget({
    required this.text,
    required this.glowColor,
    required this.unlitColor,
    required this.lineActiveProgress,
  });

  @override
  Widget build(BuildContext context) {
    if (lineActiveProgress <= 0.005) {
      return Text(
        text,
        textAlign: TextAlign.left,
        style: _KaraokeWord._baseTextStyle.copyWith(color: unlitColor),
      );
    }

    if (lineActiveProgress >= 0.995) {
      final shadows = _buildGlowShadows(glowColor, 1.0);
      return Text(
        text,
        textAlign: TextAlign.left,
        style: _KaraokeWord._baseTextStyle.copyWith(
          color: Colors.white,
          shadows: shadows,
        ),
      );
    }

    final color = Color.lerp(unlitColor, Colors.white, lineActiveProgress)!;
    return Text(
      text,
      textAlign: TextAlign.left,
      style: _KaraokeWord._baseTextStyle.copyWith(
        color: color,
      ),
    );
  }
}
