import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:musicality/core/globals.dart';
import 'package:musicality/core/models.dart';
import 'package:musicality/core/vps_sync_service.dart';
import 'package:musicality/ui/widgets/hyper_os_button.dart';
import 'package:musicality/ui/widgets/hyper_os_slider.dart';
import 'package:musicality/ui/widgets/marquee_widget.dart';
import 'package:musicality/ui/widgets/real_album_blurred_background.dart';
import 'package:musicality/ui/widgets/smooth_icon.dart';

class _EditableLyricItem {
  Duration time;
  Duration? endTime;
  List<LyricWord> words;
  TextEditingController controller;
  final FocusNode focusNode;

  _EditableLyricItem({
    required this.time,
    required String text,
    this.endTime,
    List<LyricWord>? words,
  })  : words = words != null ? List<LyricWord>.from(words) : [],
        controller = TextEditingController(text: text),
        focusNode = FocusNode();

  void shift(int deltaMs) {
    final newTimeMs = (time.inMilliseconds + deltaMs).clamp(0, 9999999);
    time = Duration(milliseconds: newTimeMs);

    if (endTime != null) {
      final newEndMs = (endTime!.inMilliseconds + deltaMs).clamp(0, 9999999);
      endTime = Duration(milliseconds: newEndMs);
    }

    if (words.isNotEmpty) {
      words = words.map((w) {
        final newStartMs = (w.start.inMilliseconds + deltaMs).clamp(0, 9999999);
        final newEndMs = (w.end.inMilliseconds + deltaMs).clamp(0, 9999999);
        return LyricWord(
          text: w.text,
          start: Duration(milliseconds: newStartMs),
          end: Duration(milliseconds: newEndMs),
        );
      }).toList();
    }
  }

  /// Retourne les mots synchronisés avec le texte actuel du contrôleur.
  /// Si le texte a été édité, conserve au maximum les timestamps des mots correspondants.
  List<LyricWord> getSynchronizedWords() {
    final currentText = controller.text.trim();
    if (currentText.isEmpty) return [];

    final rawTokens = currentText.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (rawTokens.isEmpty) return [];

    if (words.isNotEmpty && rawTokens.length == words.length) {
      final result = <LyricWord>[];
      for (int i = 0; i < words.length; i++) {
        result.add(LyricWord(
          text: rawTokens[i],
          start: words[i].start,
          end: words[i].end,
        ));
      }
      return result;
    }

    if (words.isNotEmpty) {
      final start = words.first.start;
      final end = endTime ?? (words.last.end > start ? words.last.end : start + const Duration(seconds: 3));
      final totalMs = (end - start).inMilliseconds;
      final result = <LyricWord>[];
      var curStart = start;

      final totalChars = rawTokens.fold<int>(0, (sum, t) => sum + t.length);
      for (final t in rawTokens) {
        final wMs = totalChars > 0
            ? (totalMs * (t.length / totalChars)).round()
            : (totalMs / rawTokens.length).round();
        final wEnd = curStart + Duration(milliseconds: wMs.clamp(120, 5000));
        result.add(LyricWord(text: t, start: curStart, end: wEnd));
        curStart = wEnd;
      }
      return result;
    }

    return [];
  }

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class LrcEditorView extends StatefulWidget {
  final MediaItem mediaItem;
  final List<LyricLine> initialLyrics;
  final Stream<PositionData> positionStream;
  final List<Color>? themeColors;
  final VoidCallback onSaved;

  const LrcEditorView({
    super.key,
    required this.mediaItem,
    required this.initialLyrics,
    required this.positionStream,
    this.themeColors,
    required this.onSaved,
  });

  @override
  State<LrcEditorView> createState() => _LrcEditorViewState();
}

class _LrcEditorViewState extends State<LrcEditorView>
    with SingleTickerProviderStateMixin {
  final List<_EditableLyricItem> _items = [];
  final ScrollController _scrollController = ScrollController();
  List<GlobalKey> _itemKeys = [];
  int _activeLineIndex = -1;
  bool _autoScroll = true;
  DateTime _lastUserScrollTime = DateTime.fromMillisecondsSinceEpoch(0);

  double _globalOffsetSeconds = 0.0;
  bool _isSaving = false;
  int _editingIndex = -1;

  late final Ticker _ticker;
  Duration _lastKnownPosition = Duration.zero;
  DateTime _lastPositionUpdate = DateTime.now();
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(Duration.zero);
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isPlaying = false;
  StreamSubscription<PositionData>? _positionSub;
  StreamSubscription<PlaybackState>? _playbackSub;

  List<Color> get _effectiveThemeColors {
    if (widget.themeColors != null && widget.themeColors!.isNotEmpty) {
      return widget.themeColors!;
    }
    return const [Colors.purple, Colors.blueAccent];
  }

  @override
  void initState() {
    super.initState();
    _initLyricsList();

    _ticker = createTicker((_) {
      if (_isPlaying) {
        final elapsed = DateTime.now().difference(_lastPositionUpdate);
        final current = _lastKnownPosition + elapsed;
        _positionNotifier.value = current;
        _currentPosition = current;
        final newIndex = _calculateActiveIndex(current);
        if (newIndex != _activeLineIndex) {
          _activeLineIndex = newIndex;
          if (_autoScroll && newIndex >= 0) {
            _scrollToActiveIndex(newIndex);
          }
        }
      }
    });

    _positionSub = widget.positionStream.listen((pos) {
      if (!mounted) return;
      _lastKnownPosition = pos.position;
      _lastPositionUpdate = DateTime.now();
      _positionNotifier.value = pos.position;
      _currentPosition = pos.position;
      _totalDuration = pos.duration;

      final newIndex = _calculateActiveIndex(pos.position);
      final indexChanged = newIndex != _activeLineIndex;
      _activeLineIndex = newIndex;

      if (indexChanged && _autoScroll && _isPlaying && newIndex >= 0) {
        _scrollToActiveIndex(newIndex);
      }
    });

    _playbackSub = globalAudioHandler.playbackState.listen((state) {
      if (!mounted) return;
      final wasPlaying = _isPlaying;
      setState(() {
        _isPlaying = state.playing;
      });
      _lastKnownPosition = state.position;
      _lastPositionUpdate = DateTime.now();
      _positionNotifier.value = state.position;
      _currentPosition = state.position;

      if (state.playing) {
        if (!_ticker.isActive) {
          _ticker.start();
        } else {
          _ticker.muted = false;
        }
      } else {
        _ticker.muted = true;
      }

      if (!wasPlaying && state.playing && _autoScroll && _activeLineIndex >= 0) {
        _scrollToActiveIndex(_activeLineIndex);
      }
    });

    if (globalAudioHandler.playbackState.value.playing) {
      _isPlaying = true;
      _lastKnownPosition = globalAudioHandler.playbackState.value.position;
      _lastPositionUpdate = DateTime.now();
      _positionNotifier.value = _lastKnownPosition;
      _ticker.start();
    }
  }

  int _calculateActiveIndex(Duration position) {
    if (_items.isEmpty) return -1;
    for (int i = 0; i < _items.length; i++) {
      if (position >= _items[i].time) {
        if (i == _items.length - 1 || position < _items[i + 1].time) {
          return i;
        }
      }
    }
    return -1;
  }

  void _scrollToActiveIndex(int index, {bool immediate = false}) {
    if (index < 0 || index >= _itemKeys.length) return;
    if (!immediate &&
        DateTime.now().difference(_lastUserScrollTime).inMilliseconds < 2500) {
      return;
    }
    for (final item in _items) {
      if (item.focusNode.hasFocus) return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _itemKeys[index].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.32,
          duration: immediate ? Duration.zero : const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      } else if (_scrollController.hasClients) {
        final estimatedOffset = index * 100.0;
        final maxScroll = _scrollController.position.maxScrollExtent;
        final target = estimatedOffset.clamp(0.0, maxScroll);
        if (immediate) {
          _scrollController.jumpTo(target);
        } else {
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
        }
      }
    });
  }

  void _initLyricsList() {
    _items.clear();
    for (final line in widget.initialLyrics) {
      if (line.text.toLowerCase().contains('paroles indisponibles')) {
        continue;
      }
      _items.add(
        _EditableLyricItem(
          time: line.time,
          text: line.text,
          endTime: line.endTime,
          words: line.words,
        ),
      );
    }
    _itemKeys = List.generate(_items.length, (_) => GlobalKey());
  }

  @override
  void dispose() {
    _ticker.dispose();
    _positionNotifier.dispose();
    _positionSub?.cancel();
    _playbackSub?.cancel();
    _scrollController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _applyGlobalOffset(double deltaSeconds) {
    if (isHapticFeedbackEnabledNotifier.value) {
      HapticFeedback.selectionClick();
    }
    setState(() {
      _globalOffsetSeconds += deltaSeconds;
      final deltaMs = (deltaSeconds * 1000).round();
      for (final item in _items) {
        item.shift(deltaMs);
      }
    });
  }

  void _resetGlobalOffset() {
    if (isHapticFeedbackEnabledNotifier.value) {
      HapticFeedback.mediumImpact();
    }
    if (_globalOffsetSeconds == 0.0) return;
    setState(() {
      final deltaMs = (-_globalOffsetSeconds * 1000).round();
      for (final item in _items) {
        item.shift(deltaMs);
      }
      _globalOffsetSeconds = 0.0;
    });
  }

  void _adjustLine(int index, int deltaMs) {
    if (isHapticFeedbackEnabledNotifier.value) {
      HapticFeedback.selectionClick();
    }
    setState(() {
      _items[index].shift(deltaMs);
    });
  }

  void _syncLineToCurrentPosition(int index) {
    if (isHapticFeedbackEnabledNotifier.value) {
      HapticFeedback.heavyImpact();
    }
    final curPos = _positionNotifier.value;
    final deltaMs = curPos.inMilliseconds - _items[index].time.inMilliseconds;
    setState(() {
      _items[index].shift(deltaMs);
    });
    final wordCount = _items[index].words.length;
    final wordMsg = wordCount > 0 ? ' ($wordCount mots synchronisés)' : '';
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Ligne calée à ${VpsSyncService.formatTimestamp(curPos)}$wordMsg',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.purple.shade700,
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _seekAndPreview(Duration targetTime) {
    if (isHapticFeedbackEnabledNotifier.value) {
      HapticFeedback.selectionClick();
    }
    final seekTime = targetTime - const Duration(milliseconds: 1500);
    final safeSeek = seekTime.isNegative ? Duration.zero : seekTime;
    _lastKnownPosition = safeSeek;
    _lastPositionUpdate = DateTime.now();
    _positionNotifier.value = safeSeek;
    globalAudioHandler.seek(safeSeek);
    if (!_isPlaying) {
      globalAudioHandler.play();
    }
    _lastUserScrollTime = DateTime.fromMillisecondsSinceEpoch(0);
    final idx = _calculateActiveIndex(safeSeek);
    if (idx >= 0) {
      _scrollToActiveIndex(idx);
    }
  }

  void _addNewLine() {
    if (isHapticFeedbackEnabledNotifier.value) {
      HapticFeedback.mediumImpact();
    }
    final curPos = _positionNotifier.value;
    setState(() {
      final newItem = _EditableLyricItem(
        time: curPos,
        text: '',
        endTime: curPos + const Duration(seconds: 3),
        words: const [],
      );
      _items.add(newItem);
      _sortItems();
      _itemKeys = List.generate(_items.length, (_) => GlobalKey());
      _editingIndex = _items.indexOf(newItem);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _removeLine(int index) {
    if (isHapticFeedbackEnabledNotifier.value) {
      HapticFeedback.mediumImpact();
    }
    setState(() {
      final item = _items.removeAt(index);
      item.dispose();
      _itemKeys = List.generate(_items.length, (_) => GlobalKey());
      if (_editingIndex == index) {
        _editingIndex = -1;
      } else if (_editingIndex > index) {
        _editingIndex--;
      }
    });
  }

  void _sortItems() {
    _items.sort((a, b) => a.time.compareTo(b.time));
    _itemKeys = List.generate(_items.length, (_) => GlobalKey());
  }

  Future<void> _saveAndUpload() async {
    if (_isSaving) return;

    final totalWords = _items.fold<int>(0, (sum, item) => sum + item.words.length);
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Remplacer les paroles sur le VPS ?'),
        content: Text(
          'Cette action va formater ${_items.length} lignes ($totalWords mots synchronisés) au format .lrc, '
          'mettre à jour votre copie locale, et remplacer directement le fichier sur le serveur VPS :\n\n'
          '${LyricsService.getBaseName(widget.mediaItem.id)}.lrc',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Annuler'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Remplacer sur le VPS'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isSaving = true;
    });

    try {
      _sortItems();

      final updatedLyrics = _items
          .map(
            (item) => LyricLine(
              time: item.time,
              text: item.controller.text.trim(),
              endTime: item.endTime,
              words: item.getSynchronizedWords(),
            ),
          )
          .toList();

      final lrcString = VpsSyncService.formatLrc(updatedLyrics);
      final baseName = LyricsService.getBaseName(widget.mediaItem.id);

      // 1. Sauvegarde locale et rafraîchissement mémoire instantané
      await LyricsService.updateAndSaveLyrics(
        songId: widget.mediaItem.id,
        baseName: baseName,
        lrcContent: lrcString,
        newLyrics: updatedLyrics,
      );

      // 2. Téléversement SFTP vers le VPS
      await VpsSyncService.uploadLrc(
        baseName: baseName,
        lrcContent: lrcString,
      );

      if (!mounted) return;

      widget.onSaved();

      if (isHapticFeedbackEnabledNotifier.value) {
        HapticFeedback.heavyImpact();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            '✅ Paroles enregistrées et remplacées sur le VPS avec succès !',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      if (isHapticFeedbackEnabledNotifier.value) {
        HapticFeedback.vibrate();
      }
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Erreur d\'envoi'),
          content: Text('Impossible d\'écraser le fichier sur le VPS : $e'),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  List<Shadow> _buildGlowShadows(Color glowColor, double factor) {
    if (isBatterySaverEnabledNotifier.value || factor <= 0.01) return const [];
    final f = factor.clamp(0.0, 1.0);
    return [
      Shadow(
        color: Colors.white.withValues(alpha: (f * 0.85).clamp(0.0, 1.0)),
        blurRadius: (6.0 * f).clamp(0.1, 6.0),
      ),
      Shadow(
        color: glowColor.withValues(alpha: (f * 0.7).clamp(0.0, 1.0)),
        blurRadius: (18.0 * f).clamp(0.1, 18.0),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = _effectiveThemeColors;
    final glowColor = themeColors.first;
    final unlitColor = Color.lerp(glowColor, Colors.white, 0.45)!;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Fond d'album flouté dynamique identique au lecteur de paroles
          Positioned.fill(
            child: RealAlbumBlurredBackground(
              key: ValueKey<String>('studio_${widget.mediaItem.id}'),
              item: widget.mediaItem,
            ),
          ),

          // 2. Voile sombre translucide pour un contraste et une lisibilité parfaits
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.35),
            ),
          ),

          // 3. Contenu principal (En-tête, Paroles, Contrôles & Millisecondes)
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildTopBar(themeColors),
                _buildHeaderOffsetBar(themeColors),
                Expanded(
                  child: _buildLyricsList(glowColor, unlitColor),
                ),
                _buildBottomControls(themeColors),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(List<Color> themeColors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(CupertinoIcons.chevron_down, color: Colors.white, size: 26),
            onPressed: () {
              if (isHapticFeedbackEnabledNotifier.value) {
                HapticFeedback.lightImpact();
              }
              Navigator.pop(context);
            },
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: themeColors,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: themeColors.first.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.slider_horizontal_3, color: Colors.white, size: 12),
                SizedBox(width: 4),
                Text(
                  'STUDIO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: _autoScroll
                ? 'Défilement automatique activé'
                : 'Défilement automatique en pause',
            icon: Icon(
              _autoScroll
                  ? CupertinoIcons.arrow_down_circle_fill
                  : CupertinoIcons.arrow_down_circle,
              color: _autoScroll ? Colors.cyanAccent : Colors.white38,
              size: 22,
            ),
            onPressed: () {
              if (isHapticFeedbackEnabledNotifier.value) {
                HapticFeedback.selectionClick();
              }
              setState(() {
                _autoScroll = !_autoScroll;
              });
              if (_autoScroll && _activeLineIndex >= 0) {
                _scrollToActiveIndex(_activeLineIndex, immediate: true);
              }
            },
          ),
          const SizedBox(width: 4),
          _isSaving
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : TextButton.icon(
                  onPressed: _saveAndUpload,
                  icon: const Icon(
                    CupertinoIcons.cloud_upload_fill,
                    color: Colors.cyanAccent,
                    size: 19,
                  ),
                  label: const Text(
                    'Remplacer VPS',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  /// Remplace la pochette de l'album par les outils de calage global rapide (+0.1, +0.5, etc.)
  Widget _buildHeaderOffsetBar(List<Color> themeColors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // À la place de la pochette 60x60 : Le bloc de boutons d'offset
          _TopOffsetGrid(
            onOffset: _applyGlobalOffset,
          ),

          const SizedBox(width: 14),

          // Titre avec gradient ShaderMask, artiste et décalage global
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MarqueeWidget(
                  resetKey: 'studio_title_${widget.mediaItem.id}',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) {
                          return LinearGradient(
                            colors: themeColors,
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ).createShader(
                            Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                          );
                        },
                        child: Text(
                          widget.mediaItem.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                      if (widget.mediaItem.extras?['isFlac'] == true) ...[
                        const SizedBox(width: 6),
                        ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              colors: themeColors,
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ).createShader(bounds);
                          },
                          child: Text(
                            widget.mediaItem.extras?['isHiRes'] == true
                                ? "• HI-RES"
                                : "• LOSSLESS",
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  formatArtist(widget.mediaItem.artist),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color.lerp(
                      const Color(0xFFCCCCCC),
                      themeColors.first,
                      0.35,
                    ),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text(
                      'Décalage : ',
                      style: TextStyle(color: Colors.white60, fontSize: 11.5),
                    ),
                    Text(
                      '${_globalOffsetSeconds >= 0 ? '+' : ''}${_globalOffsetSeconds.toStringAsFixed(1)}s',
                      style: TextStyle(
                        color: _globalOffsetSeconds != 0.0
                            ? Colors.cyanAccent
                            : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (_globalOffsetSeconds != 0.0) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _resetGlobalOffset,
                        child: const Icon(
                          CupertinoIcons.arrow_counterclockwise,
                          color: Colors.orangeAccent,
                          size: 13,
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      '• ${_items.length} lignes',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Section Paroles avec le style du lecteur et le timestamp affiché à côté
  Widget _buildLyricsList(Color glowColor, Color unlitColor) {
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.music_note_list,
              color: Colors.white30,
              size: 56,
            ),
            const SizedBox(height: 12),
            const Text(
              'Aucune parole trouvée pour ce titre.',
              style: TextStyle(color: Colors.white60, fontSize: 15),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _addNewLine,
              icon: const Icon(CupertinoIcons.add, size: 16),
              label: const Text('Ajouter une première ligne'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ShaderMask(
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
                0.07,
                0.90,
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
            child: ListView.builder(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
              itemCount: _items.length + 1,
              itemBuilder: (context, index) {
                if (index == _items.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: OutlinedButton.icon(
                        onPressed: _addNewLine,
                        icon: const Icon(CupertinoIcons.add, color: Colors.cyanAccent),
                        label: const Text(
                          'Ajouter une ligne à la position actuelle',
                          style: TextStyle(
                            color: Colors.cyanAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.cyanAccent),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return _buildLyricRow(index, glowColor, unlitColor);
              },
            ),
          ),
        ),

        // Bouton flottant pour recentrer si l'utilisateur a défilé manuellement
        if (_autoScroll &&
            _isPlaying &&
            _activeLineIndex >= 0 &&
            DateTime.now().difference(_lastUserScrollTime).inMilliseconds < 3000)
          Positioned(
            right: 16,
            bottom: 12,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  _lastUserScrollTime = DateTime.fromMillisecondsSinceEpoch(0);
                  _scrollToActiveIndex(_activeLineIndex, immediate: true);
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.shade700,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.location_fill, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Suivre la lecture',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLyricRow(int index, Color glowColor, Color unlitColor) {
    final item = _items[index];
    final isCurrent = index == _activeLineIndex;
    final isEditing = _editingIndex == index;

    return Container(
      key: (index < _itemKeys.length) ? _itemKeys[index] : null,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isCurrent
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? Colors.cyanAccent.withValues(alpha: 0.5)
              : Colors.transparent,
          width: 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Colonne gauche : Le temps de la ligne (timestamp) et actions de calage
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Badge de l'horodatage
              GestureDetector(
                onTap: () => _seekAndPreview(item.time),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? Colors.cyanAccent.withValues(alpha: 0.25)
                        : Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCurrent ? Colors.cyanAccent : Colors.white24,
                      width: isCurrent ? 1.2 : 0.8,
                    ),
                  ),
                  child: Text(
                    VpsSyncService.formatTimestamp(item.time),
                    style: TextStyle(
                      color: isCurrent ? Colors.cyanAccent : Colors.white70,
                      fontFamily: 'monospace',
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              // Boutons de calage rapide : Caler + micro-ajustements
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'Caler cette ligne sur la position actuelle',
                    child: InkWell(
                      onTap: () => _syncLineToCurrentPosition(index),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                        decoration: BoxDecoration(
                          color: isCurrent ? Colors.purple.shade700 : Colors.white12,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.scope, color: Colors.white, size: 11),
                            SizedBox(width: 3),
                            Text(
                              'Caler',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _MicroAdjustButton(
                    label: '-0.1',
                    onTap: () => _adjustLine(index, -100),
                  ),
                  const SizedBox(width: 3),
                  _MicroAdjustButton(
                    label: '+0.1',
                    onTap: () => _adjustLine(index, 100),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(width: 14),

          // 2. Colonne centrale : Texte des paroles style Menu des Paroles
          Expanded(
            child: isEditing
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: item.controller,
                          focusNode: item.focusNode,
                          autofocus: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.cyanAccent),
                            ),
                            hintText: 'Texte des paroles...',
                            hintStyle: TextStyle(color: Colors.white30),
                          ),
                          onSubmitted: (_) {
                            setState(() {
                              _editingIndex = -1;
                            });
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: Colors.cyanAccent,
                          size: 24,
                        ),
                        onPressed: () {
                          setState(() {
                            _editingIndex = -1;
                          });
                        },
                      ),
                    ],
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _seekAndPreview(item.time),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: _buildLyricText(item, isCurrent, glowColor, unlitColor),
                    ),
                  ),
          ),

          // 3. Colonne droite : Outils d'édition de texte & suppression
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  isEditing ? CupertinoIcons.checkmark : CupertinoIcons.pencil,
                  color: isEditing ? Colors.cyanAccent : Colors.white38,
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    if (isEditing) {
                      _editingIndex = -1;
                    } else {
                      _editingIndex = index;
                      item.focusNode.requestFocus();
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              IconButton(
                icon: const Icon(CupertinoIcons.trash, color: Colors.white24, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _removeLine(index),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLyricText(
    _EditableLyricItem item,
    bool isCurrent,
    Color glowColor,
    Color unlitColor,
  ) {
    final text = item.controller.text.isEmpty ? '—' : item.controller.text;

    // Si la ligne possède des mots synchronisés et est en cours de chant
    if (isCurrent && item.words.isNotEmpty) {
      return Wrap(
        spacing: 6.0,
        runSpacing: 4.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: item.words.map((w) {
          final isActive = _currentPosition >= w.start && _currentPosition < w.end;
          final isPast = _currentPosition >= w.end;

          final Color wordColor = isActive
              ? Colors.white
              : (isPast
                  ? Colors.white
                  : unlitColor.withValues(alpha: 0.5));

          final shadows = isActive
              ? _buildGlowShadows(glowColor, 1.0)
              : (isPast ? _buildGlowShadows(glowColor, 0.4) : null);

          return Text(
            w.text,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: wordColor,
              shadows: shadows,
              height: 1.3,
            ),
          );
        }).toList(),
      );
    }

    // Ligne normale
    final shadows = isCurrent ? _buildGlowShadows(glowColor, 1.0) : null;
    final color = isCurrent ? Colors.white : unlitColor.withValues(alpha: 0.45);

    return Text(
      text,
      style: TextStyle(
        fontSize: isCurrent ? 22 : 20,
        fontWeight: FontWeight.bold,
        color: color,
        shadows: shadows,
        height: 1.3,
      ),
    );
  }

  /// Barre de lecture inférieure avec contrôles complets et temps de musique affichant les millisecondes
  Widget _buildBottomControls(List<Color> themeColors) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        MediaQuery.of(context).padding.bottom + 14,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        border: const Border(
          top: BorderSide(color: Colors.white12, width: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Slider de progression avec millisecondes
          ValueListenableBuilder<Duration>(
            valueListenable: _positionNotifier,
            builder: (context, pos, _) {
              return HyperOSSlider(
                position: pos,
                duration: _totalDuration,
                gradientColors: themeColors,
                showMilliseconds: true,
                onSeek: (target) {
                  _lastKnownPosition = target;
                  _lastPositionUpdate = DateTime.now();
                  _positionNotifier.value = target;
                  globalAudioHandler.seek(target);
                },
              );
            },
          ),
          const SizedBox(height: 8),

          // Contrôles de lecture
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Recul 3s
              HyperOSButton(
                onTap: () {
                  final target = _currentPosition - const Duration(seconds: 3);
                  final safeTarget = target.isNegative ? Duration.zero : target;
                  _lastKnownPosition = safeTarget;
                  _lastPositionUpdate = DateTime.now();
                  _positionNotifier.value = safeTarget;
                  globalAudioHandler.seek(safeTarget);
                },
                child: const SmoothIcon(
                  icon: CupertinoIcons.gobackward,
                  color: Colors.white70,
                  size: 26,
                ),
              ),
              const SizedBox(width: 18),

              // Précédent
              HyperOSButton(
                onTap: () {
                  globalAudioHandler.skipToPrevious();
                },
                child: const SmoothIcon(
                  icon: CupertinoIcons.backward_fill,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 24),

              // Play / Pause
              HyperOSButton(
                isPlayPause: true,
                onTap: () {
                  if (_isPlaying) {
                    globalAudioHandler.pause();
                  } else {
                    globalAudioHandler.play();
                  }
                },
                child: SmoothIcon(
                  icon: _isPlaying
                      ? CupertinoIcons.pause_solid
                      : CupertinoIcons.play_arrow_solid,
                  color: Colors.white,
                  size: 46,
                ),
              ),
              const SizedBox(width: 24),

              // Suivant
              HyperOSButton(
                onTap: () {
                  globalAudioHandler.skipToNext();
                },
                child: const SmoothIcon(
                  icon: CupertinoIcons.forward_fill,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 18),

              // Avance 3s
              HyperOSButton(
                onTap: () {
                  final target = _currentPosition + const Duration(seconds: 3);
                  _lastKnownPosition = target;
                  _lastPositionUpdate = DateTime.now();
                  _positionNotifier.value = target;
                  globalAudioHandler.seek(target);
                },
                child: const SmoothIcon(
                  icon: CupertinoIcons.goforward,
                  color: Colors.white70,
                  size: 26,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Grille 2x2 des boutons d'offset rapide remplaçant la pochette d'album
class _TopOffsetGrid extends StatelessWidget {
  final Function(double) onOffset;

  const _TopOffsetGrid({required this.onOffset});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 60,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(
            children: [
              Expanded(
                child: _QuickOffsetButton(
                  label: '-0.5s',
                  onTap: () => onOffset(-0.5),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _QuickOffsetButton(
                  label: '+0.5s',
                  onTap: () => onOffset(0.5),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _QuickOffsetButton(
                  label: '-0.1s',
                  onTap: () => onOffset(-0.1),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _QuickOffsetButton(
                  label: '+0.1s',
                  onTap: () => onOffset(0.1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickOffsetButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickOffsetButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 23,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

class _MicroAdjustButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _MicroAdjustButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24, width: 0.5),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
