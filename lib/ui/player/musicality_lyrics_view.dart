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
  DateTime _lastUserScrollTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isPlaying = false;

  bool get _hasNoLyrics {
    if (widget.lyrics.isEmpty) return true;
    if (widget.lyrics.length == 1) {
      final text = widget.lyrics.first.text.trim().toLowerCase();
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
    WidgetsBinding.instance.addObserver(this);
    _generateKeys();

    _ticker = createTicker((_) {
      if (_isPlaying && widget.isExpanded && !_hasNoLyrics) {
        final elapsed = DateTime.now().difference(_lastPositionUpdate);
        final current = _lastKnownPosition + elapsed;
        _positionNotifier.value = current;
        _checkActiveIndex(current);
      }
    });
    if (widget.isExpanded) {
      _ticker.start();
    }

    _listenToPosition();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    });
  }

  @override
  void didUpdateWidget(MusicalityLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool songChanged = oldWidget.songId != widget.songId;
    final bool lyricsChanged = oldWidget.lyrics != widget.lyrics;

    if (songChanged || lyricsChanged) {
      _lastUserScrollTime = DateTime.fromMillisecondsSinceEpoch(0);
      _activeIndexNotifier.value = -1;
      _lastKnownPosition = Duration.zero;
      _lastPositionUpdate = DateTime.now();
      _positionNotifier.value = Duration.zero;
      _generateKeys();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0.0);
        }
      });
      setState(() {});
    }

    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        if (!_ticker.isActive) {
          _ticker.start();
        } else {
          _ticker.muted = false;
        }
        if (_activeIndexNotifier.value <= 0) {
          _scrollToTop(immediate: true);
        } else {
          _scrollToActiveIndex(_activeIndexNotifier.value, immediate: true);
        }
      } else {
        _ticker.muted = true;
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
      _isPlaying = globalAudioHandler.playbackState.value.playing;
      _positionNotifier.value = data.position;

      if (widget.isExpanded) {
        _checkActiveIndex(data.position);
      }
    });
  }

  void _checkActiveIndex(Duration position) {
    if (_hasNoLyrics) return;

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
        if (newIndex <= 0) {
          _scrollToTop();
        } else {
          _scrollToActiveIndex(newIndex);
        }
      }
    }
  }

  void _scrollToTop({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isExpanded) return;
      if (!immediate &&
          DateTime.now().difference(_lastUserScrollTime).inMilliseconds < 2500) {
        return;
      }
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

  void _scrollToActiveIndex(int targetIndex, {bool immediate = false}) {
    if (targetIndex <= 0) {
      _scrollToTop(immediate: immediate);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || targetIndex < 0 || targetIndex >= _lyricKeys.length) {
        return;
      }

      if (!widget.isExpanded) return;

      // Respect du défilement manuel de l'utilisateur pendant 2.5 secondes
      if (!immediate &&
          DateTime.now().difference(_lastUserScrollTime).inMilliseconds < 2500) {
        return;
      }

      final keyContext = _lyricKeys[targetIndex].currentContext;
      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          alignment: 0.28,
          duration:
              immediate ? Duration.zero : const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      if (widget.isExpanded) {
        if (!_ticker.isActive) {
          _ticker.start();
        } else {
          _ticker.muted = false;
        }
      }
    } else {
      _ticker.muted = true;
    }
  }

  @override
  void dispose() {
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
      final String message = widget.lyrics.isNotEmpty
          ? widget.lyrics.first.text
          : "Paroles indisponibles pour ce titre";
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: unlitColor.withValues(alpha: 0.8),
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.4,
              letterSpacing: -0.2,
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
        child: NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (notification.direction != ScrollDirection.idle) {
              _lastUserScrollTime = DateTime.now();
            }
            return false;
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(
              top: screenHeight * 0.22,
              bottom: screenHeight * 0.55,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(widget.lyrics.length, (index) {
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
                    onTap: () => globalAudioHandler.seek(line.time),
                  ),
                );
              }),
            ),
          ),
        ),
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
      blurRadius: (6.0 * f).clamp(0.1, 6.0),
    ),
    Shadow(
      color: glowColor.withValues(alpha: (f * 0.85).clamp(0.0, 1.0)),
      blurRadius: (16.0 * f).clamp(0.1, 16.0),
    ),
    Shadow(
      color: glowColor.withValues(alpha: (f * 0.35).clamp(0.0, 1.0)),
      blurRadius: (24.0 * f).clamp(0.1, 24.0),
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
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      } else {
        // La ligne n'est plus active : la lumière reste et disparaît progressivement
        _controller.animateTo(
          0.0,
          duration: const Duration(milliseconds: 2800),
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
  }

  @override
  void dispose() {
    widget.activeIndexNotifier.removeListener(_onActiveIndexChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isBatterySaverEnabledNotifier,
      builder: (context, isBatterySaver, _) {
        return AnimatedBuilder(
          animation: _animation,
          builder: (context, _) {
            final progress = _animation.value;
            final currentOpacity = lerpDouble(0.45, 1.0, progress)!;
            final effectiveUnlitColor =
                widget.unlitColor.withValues(alpha: currentOpacity);

            const kBlurSigma = 1.2;
            final currentBlur =
                isBatterySaver ? 0.0 : (1.0 - progress) * kBlurSigma;

            final Widget renderedLine;

            final bool hasWords = widget.line.words.isNotEmpty;

            if (_isActive) {
              // 1. LIGNE ACTIVE EN COURS DE CHANT :
              // Les mots non encore chantés restent à l'opacité atténuée (0.45) sans aucun flash !
              renderedLine = hasWords
                  ? _KaraokeLineWidget(
                      line: widget.line,
                      isActive: true,
                      positionNotifier: widget.positionNotifier,
                      glowColor: widget.glowColor,
                      unlitColor: widget.unlitColor.withValues(alpha: 0.45),
                      lineActiveProgress: 1.0,
                      blurRadius: currentBlur,
                    )
                  : _PlainLineWidget(
                      text: widget.line.text,
                      glowColor: widget.glowColor,
                      unlitColor: effectiveUnlitColor,
                      lineActiveProgress: progress,
                      blurRadius: currentBlur,
                    );
            } else if (progress <= 0.001) {
              // 2. LIGNE TOTALEMENT INACTIVE :
              // Conserve rigoureusement le même conteneur (Wrap) pour éviter tout saut de taille ou de retour à la ligne
              renderedLine = hasWords
                  ? _KaraokeLineWidget(
                      line: widget.line,
                      isActive: false,
                      positionNotifier: widget.positionNotifier,
                      glowColor: widget.glowColor,
                      unlitColor: effectiveUnlitColor,
                      lineActiveProgress: 0.0,
                      blurRadius: isBatterySaver ? 0.0 : kBlurSigma,
                    )
                  : _PlainLineWidget(
                      text: widget.line.text,
                      glowColor: widget.glowColor,
                      unlitColor: effectiveUnlitColor,
                      lineActiveProgress: 0.0,
                      blurRadius: isBatterySaver ? 0.0 : kBlurSigma,
                    );
            } else {
              // 3. TRANSITION DE FIN DE LIGNE (la lumière s'estompe sur 2,8s) :
              // Lueur qui disparaît progressivement et flou qui remonte en douceur
              renderedLine = hasWords
                  ? _KaraokeLineWidget(
                      line: widget.line,
                      isActive: false,
                      positionNotifier: widget.positionNotifier,
                      glowColor: widget.glowColor,
                      unlitColor: widget.unlitColor.withValues(alpha: 0.45),
                      lineActiveProgress: progress,
                      blurRadius: currentBlur,
                    )
                  : _PlainLineWidget(
                      text: widget.line.text,
                      glowColor: widget.glowColor,
                      unlitColor: effectiveUnlitColor,
                      lineActiveProgress: progress,
                      blurRadius: currentBlur,
                    );
            }

            final Widget lineWidget = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 16,
                ),
                child: renderedLine,
              ),
            );

            // Isole CHAQUE ligne dans son propre calque GPU (RepaintBoundary).
            // Les 80+ lignes inactives restent ainsi en cache de texture GPU et ne sont jamais
            // repeintes pendant que le mot en cours de chant s'anime à 120 FPS.
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
  final double blurRadius;

  const _KaraokeLineWidget({
    required this.line,
    required this.isActive,
    required this.positionNotifier,
    required this.glowColor,
    required this.unlitColor,
    required this.lineActiveProgress,
    this.blurRadius = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    if (!isActive) {
      if (lineActiveProgress > 0.001) {
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
              blurRadius: blurRadius,
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
            blurRadius: blurRadius,
          );
        }).toList(),
      );
    }

    // LIGNE ACTIVE :
    // Le Wrap est instancié UNE SEULE FOIS pour toute la ligne.
    // Chaque mot écoute individuellement et ne se rafraîchit à 120 FPS QUE lorsqu'il est en train d'être chanté !
    // Les 20+ autres mots restent totalement immobiles sans aucun recalcul de disposition (performLayout) de Wrap.
    return Wrap(
      spacing: 7.0,
      runSpacing: 7.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: List.generate(line.words.length, (index) {
        final word = line.words[index];
        return _DynamicKaraokeWord(
          key: ValueKey(word.start.inMilliseconds),
          word: word,
          positionNotifier: positionNotifier,
          glowColor: glowColor,
          unlitColor: unlitColor,
          blurRadius: blurRadius,
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
  final double blurRadius;

  const _DynamicKaraokeWord({
    super.key,
    required this.word,
    required this.positionNotifier,
    required this.glowColor,
    required this.unlitColor,
    this.blurRadius = 0.0,
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
      // Ce mot précis est en cours de chant : animation fluide du balayage lumineux (sweep)
      final elapsed = (pos - start).inMilliseconds;
      final duration = (end - start).inMilliseconds.clamp(1, 5000);
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
    return _KaraokeWord(
      text: widget.word.text,
      lightFactor: _progress,
      isCurrent: _state == _WordState.singing,
      glowColor: widget.glowColor,
      unlitColor: widget.unlitColor,
      blurRadius: widget.blurRadius,
    );
  }
}

class _KaraokeWord extends StatelessWidget {
  final String text;
  final double lightFactor;
  final bool isCurrent;
  final Color glowColor;
  final Color unlitColor;
  final double blurRadius;

  const _KaraokeWord({
    required this.text,
    required this.lightFactor,
    required this.isCurrent,
    required this.glowColor,
    required this.unlitColor,
    this.blurRadius = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    const baseTextStyle = TextStyle(
      fontSize: 27,
      fontWeight: FontWeight.bold,
      height: 1.35,
    );

    // 1. Mot non encore chanté : couleur unlit avec flou direct sur glyphes (120 FPS ultra fluide)
    if (lightFactor <= 0.005) {
      if (blurRadius > 0.08) {
        return Text(
          text,
          style: baseTextStyle.copyWith(
            foreground: Paint()
              ..color = unlitColor
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius),
          ),
        );
      }
      return Text(
        text,
        style: baseTextStyle.copyWith(color: unlitColor),
      );
    }

    // 2. Mot entièrement chanté : texte blanc avec aura lumineuse
    if (lightFactor >= 0.995) {
      final shadows = _buildGlowShadows(glowColor, 1.0);
      return Text(
        text,
        style: baseTextStyle.copyWith(
          color: Colors.white,
          shadows: shadows,
        ),
      );
    }

    // 3. Ligne qui se termine (estompage progressif de la lumière et du blanc sur 2,8s)
    if (!isCurrent) {
      final shadows = _buildGlowShadows(glowColor, lightFactor);
      final wordColor = Color.lerp(unlitColor, Colors.white, lightFactor)!;
      if (blurRadius > 0.08) {
        return Text(
          text,
          style: baseTextStyle.copyWith(
            foreground: Paint()
              ..color = wordColor
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius),
            shadows: shadows,
          ),
        );
      }
      return Text(
        text,
        style: baseTextStyle.copyWith(
          color: wordColor,
          shadows: shadows,
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
            style: baseTextStyle.copyWith(
              color: Colors.transparent,
              shadows: shadows,
            ),
          )
        : null;

    final litWidget = Text(
      text,
      style: baseTextStyle.copyWith(
        color: Colors.white,
        shadows: const [],
      ),
    );
    final unlitWidget = Text(
      text,
      style: baseTextStyle.copyWith(color: unlitColor),
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
            stops: [0.0, lightFactor, lightFactor, 1.0],
          ).createShader(bounds),
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
  final double blurRadius;

  const _PlainLineWidget({
    required this.text,
    required this.glowColor,
    required this.unlitColor,
    required this.lineActiveProgress,
    this.blurRadius = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    const baseTextStyle = TextStyle(
      fontSize: 27,
      fontWeight: FontWeight.bold,
      height: 1.35,
    );

    if (lineActiveProgress <= 0.005) {
      if (blurRadius > 0.08) {
        return Text(
          text,
          textAlign: TextAlign.left,
          style: baseTextStyle.copyWith(
            foreground: Paint()
              ..color = unlitColor
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius),
          ),
        );
      }
      return Text(
        text,
        textAlign: TextAlign.left,
        style: baseTextStyle.copyWith(color: unlitColor),
      );
    }

    if (lineActiveProgress >= 0.995) {
      final shadows = _buildGlowShadows(glowColor, 1.0);
      return Text(
        text,
        textAlign: TextAlign.left,
        style: baseTextStyle.copyWith(
          color: Colors.white,
          shadows: shadows,
        ),
      );
    }

    final shadows = _buildGlowShadows(glowColor, lineActiveProgress);
    final color = Color.lerp(unlitColor, Colors.white, lineActiveProgress)!;
    if (blurRadius > 0.08) {
      return Text(
        text,
        textAlign: TextAlign.left,
        style: baseTextStyle.copyWith(
          foreground: Paint()
            ..color = color
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius),
          shadows: shadows,
        ),
      );
    }
    return Text(
      text,
      textAlign: TextAlign.left,
      style: baseTextStyle.copyWith(
        color: color,
        shadows: shadows,
      ),
    );
  }
}
