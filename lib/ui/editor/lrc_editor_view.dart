import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:musicality/core/globals.dart';
import 'package:musicality/core/models.dart';
import 'package:musicality/core/vps_sync_service.dart';

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

    // Si le nombre de mots correspond au nombre de mots d'origine
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

    // Si les mots d'origine existent mais que le nombre de mots a changé, interpolation
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
  final VoidCallback onSaved;

  const LrcEditorView({
    super.key,
    required this.mediaItem,
    required this.initialLyrics,
    required this.positionStream,
    required this.onSaved,
  });

  @override
  State<LrcEditorView> createState() => _LrcEditorViewState();
}

class _LrcEditorViewState extends State<LrcEditorView> {
  final List<_EditableLyricItem> _items = [];
  final ScrollController _scrollController = ScrollController();
  List<GlobalKey> _itemKeys = [];
  int _activeLineIndex = -1;
  bool _autoScroll = true;
  DateTime _lastUserScrollTime = DateTime.fromMillisecondsSinceEpoch(0);

  double _globalOffsetSeconds = 0.0;
  bool _isSaving = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isPlaying = false;
  StreamSubscription<PositionData>? _positionSub;
  StreamSubscription<PlaybackState>? _playbackSub;

  @override
  void initState() {
    super.initState();
    _initLyricsList();

    _positionSub = widget.positionStream.listen((pos) {
      if (!mounted) return;
      final newIndex = _calculateActiveIndex(pos.position);
      final indexChanged = newIndex != _activeLineIndex;
      _activeLineIndex = newIndex;

      setState(() {
        _currentPosition = pos.position;
        _totalDuration = pos.duration;
      });

      if (indexChanged && _autoScroll && _isPlaying && newIndex >= 0) {
        _scrollToActiveIndex(newIndex);
      }
    });

    _playbackSub = globalAudioHandler.playbackState.listen((state) {
      if (mounted) {
        final wasPlaying = _isPlaying;
        setState(() {
          _isPlaying = state.playing;
        });
        if (!wasPlaying && state.playing && _autoScroll && _activeLineIndex >= 0) {
          _scrollToActiveIndex(_activeLineIndex);
        }
      }
    });
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
    // Ne pas défiler si un champ de saisie est en train d'être tapé
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
        final estimatedOffset = index * 125.0;
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
      // Ignorer les lignes de fallback
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
    _positionSub?.cancel();
    _playbackSub?.cancel();
    _scrollController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _applyGlobalOffset(double deltaSeconds) {
    HapticFeedback.selectionClick();
    setState(() {
      _globalOffsetSeconds += deltaSeconds;
      final deltaMs = (deltaSeconds * 1000).round();
      for (final item in _items) {
        item.shift(deltaMs);
      }
    });
  }

  void _resetGlobalOffset() {
    HapticFeedback.mediumImpact();
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
    HapticFeedback.selectionClick();
    setState(() {
      _items[index].shift(deltaMs);
    });
  }

  void _syncLineToCurrentPosition(int index) {
    HapticFeedback.heavyImpact();
    final deltaMs = _currentPosition.inMilliseconds - _items[index].time.inMilliseconds;
    setState(() {
      _items[index].shift(deltaMs);
    });
    final wordCount = _items[index].words.length;
    final wordMsg = wordCount > 0 ? ' ($wordCount mots synchronisés)' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Ligne calée à ${VpsSyncService.formatTimestamp(_currentPosition)}$wordMsg',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.purple.shade700,
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _seekAndPreview(Duration targetTime) {
    HapticFeedback.selectionClick();
    final seekTime = targetTime - const Duration(milliseconds: 1500);
    final safeSeek = seekTime.isNegative ? Duration.zero : seekTime;
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
    HapticFeedback.mediumImpact();
    setState(() {
      final newItem = _EditableLyricItem(
        time: _currentPosition,
        text: '',
        endTime: _currentPosition + const Duration(seconds: 3),
        words: const [],
      );
      _items.add(newItem);
      _sortItems();
      _itemKeys = List.generate(_items.length, (_) => GlobalKey());
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
    HapticFeedback.mediumImpact();
    setState(() {
      final item = _items.removeAt(index);
      item.dispose();
      _itemKeys = List.generate(_items.length, (_) => GlobalKey());
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

      HapticFeedback.heavyImpact();
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
      HapticFeedback.vibrate();
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

  String _formatTimer(Duration d) {
    final totalCentis = (d.inMilliseconds / 10).floor();
    final centis = totalCentis % 100;
    final totalSecs = (totalCentis / 100).floor();
    final secs = totalSecs % 60;
    final mins = (totalSecs / 60).floor();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${centis.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final baseName = LyricsService.getBaseName(widget.mediaItem.id);

    return Scaffold(
      backgroundColor: const Color(0xFF101012),
      appBar: AppBar(
        backgroundColor: const Color(0xFF18181C),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_down, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Éditeur LRC',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.purple, Colors.blueAccent],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'STUDIO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              widget.mediaItem.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        actions: [
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
              setState(() {
                _autoScroll = !_autoScroll;
              });
              if (_autoScroll && _activeLineIndex >= 0) {
                _scrollToActiveIndex(_activeLineIndex, immediate: true);
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: _isSaving
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : TextButton.icon(
                    onPressed: _saveAndUpload,
                    icon: const Icon(
                      CupertinoIcons.cloud_upload_fill,
                      color: Colors.cyanAccent,
                      size: 18,
                    ),
                    label: const Text(
                      'Remplacer VPS',
                      style: TextStyle(
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Barre de décalage global & informations
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF18181C).withValues(alpha: 0.6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fichier : $baseName.lrc',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Text(
                            'Décalage global : ',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          Text(
                            '${_globalOffsetSeconds >= 0 ? '+' : ''}${_globalOffsetSeconds.toStringAsFixed(1)}s',
                            style: TextStyle(
                              color: _globalOffsetSeconds != 0.0
                                  ? Colors.cyanAccent
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          if (_globalOffsetSeconds != 0.0) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: _resetGlobalOffset,
                              child: const Icon(
                                CupertinoIcons.arrow_counterclockwise,
                                color: Colors.orangeAccent,
                                size: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            CupertinoIcons.textformat_size,
                            color: Colors.purpleAccent,
                            size: 11,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Cible : ${_items.length} lignes • ${_items.fold<int>(0, (sum, i) => sum + i.words.length)} mots',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Boutons d'offset global rapide
                _OffsetButton(
                  label: '-0.5s',
                  tooltip: 'Décale toutes les lignes et tous les mots de -0.5s',
                  onTap: () => _applyGlobalOffset(-0.5),
                ),
                const SizedBox(width: 4),
                _OffsetButton(
                  label: '-0.1s',
                  tooltip: 'Décale toutes les lignes et tous les mots de -0.1s',
                  onTap: () => _applyGlobalOffset(-0.1),
                ),
                const SizedBox(width: 4),
                _OffsetButton(
                  label: '+0.1s',
                  tooltip: 'Décale toutes les lignes et tous les mots de +0.1s',
                  onTap: () => _applyGlobalOffset(0.1),
                ),
                const SizedBox(width: 4),
                _OffsetButton(
                  label: '+0.5s',
                  tooltip: 'Décale toutes les lignes et tous les mots de +0.5s',
                  onTap: () => _applyGlobalOffset(0.5),
                ),
              ],
            ),
          ),

          // 2. Liste des lignes de paroles
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          CupertinoIcons.music_note_list,
                          color: Colors.white30,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Aucune parole trouvée pour ce titre.',
                          style: TextStyle(color: Colors.white60, fontSize: 14),
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
                  )
                : Stack(
                    children: [
                      NotificationListener<UserScrollNotification>(
                        onNotification: (notification) {
                          if (notification.direction != ScrollDirection.idle) {
                            _lastUserScrollTime = DateTime.now();
                          }
                          return false;
                        },
                        child: ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: _items.length + 1,
                          separatorBuilder: (context, index) => const Divider(
                            color: Colors.white10,
                            height: 16,
                          ),
                          itemBuilder: (context, index) {
                            if (index == _items.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16.0),
                                child: OutlinedButton.icon(
                                  onPressed: _addNewLine,
                                  icon: const Icon(CupertinoIcons.add, color: Colors.cyanAccent),
                                  label: const Text(
                                    'Ajouter une ligne à la position actuelle',
                                    style: TextStyle(color: Colors.cyanAccent),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.cyanAccent),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              );
                            }

                            final item = _items[index];
                            final isCurrent = index == _activeLineIndex;

                            return Container(
                              key: (index < _itemKeys.length) ? _itemKeys[index] : null,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: isCurrent
                                    ? LinearGradient(
                                        colors: [
                                          Colors.purple.withValues(alpha: 0.32),
                                          Colors.cyanAccent.withValues(alpha: 0.14),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                color: isCurrent
                                    ? null
                                    : Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isCurrent
                                      ? Colors.cyanAccent.withValues(alpha: 0.8)
                                      : Colors.white12,
                                  width: isCurrent ? 1.5 : 1.0,
                                ),
                                boxShadow: isCurrent
                                    ? [
                                        BoxShadow(
                                          color: Colors.cyanAccent.withValues(alpha: 0.18),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // En-tête de la ligne (timestamp + actions de calage)
                                  Row(
                                    children: [
                                      // Badge Timestamp
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isCurrent
                                              ? Colors.cyanAccent.withValues(alpha: 0.2)
                                              : Colors.black45,
                                          borderRadius: BorderRadius.circular(6),
                                          border: isCurrent
                                              ? Border.all(color: Colors.cyanAccent, width: 0.8)
                                              : null,
                                        ),
                                        child: Text(
                                          VpsSyncService.formatTimestamp(item.time),
                                          style: TextStyle(
                                            color: isCurrent
                                                ? Colors.cyanAccent
                                                : Colors.white,
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      if (item.words.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.purple.withValues(alpha: 0.22),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: Colors.purpleAccent.withValues(alpha: 0.4),
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                CupertinoIcons.sparkles,
                                                color: Colors.purpleAccent,
                                                size: 10,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                '${item.words.length} mots',
                                                style: const TextStyle(
                                                  color: Colors.purpleAccent,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      const SizedBox(width: 8),

                                      // Bouton TARGET "Caler ici"
                                      Tooltip(
                                        message: 'Caler sur la position actuelle',
                                        child: InkWell(
                                          onTap: () => _syncLineToCurrentPosition(index),
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.purple.shade700,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  CupertinoIcons.scope,
                                                  color: Colors.white,
                                                  size: 14,
                                                ),
                                                SizedBox(width: 4),
                                                Text(
                                                  'Caler',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),

                                      const Spacer(),

                                      // Boutons micro-ajustement (-0.1s / +0.1s)
                                      _MicroAdjustButton(
                                        label: '-0.1s',
                                        onTap: () => _adjustLine(index, -100),
                                      ),
                                      const SizedBox(width: 4),
                                      _MicroAdjustButton(
                                        label: '+0.1s',
                                        onTap: () => _adjustLine(index, 100),
                                      ),
                                      const SizedBox(width: 8),

                                      // Écouter la ligne (Seek -1.5s)
                                      IconButton(
                                        icon: const Icon(
                                          CupertinoIcons.play_circle_fill,
                                          color: Colors.white70,
                                          size: 22,
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => _seekAndPreview(item.time),
                                      ),
                                      const SizedBox(width: 8),

                                      // Supprimer la ligne
                                      IconButton(
                                        icon: const Icon(
                                          CupertinoIcons.trash,
                                          color: Colors.white38,
                                          size: 18,
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => _removeLine(index),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 8),

                                  // Champ de texte éditable
                                  TextField(
                                    controller: item.controller,
                                    focusNode: item.focusNode,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: isCurrent ? 16 : 15,
                                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8,
                                      ),
                                      border: InputBorder.none,
                                      hintText: 'Texte des paroles...',
                                      hintStyle: TextStyle(color: Colors.white24),
                                    ),
                                  ),

                                  // Affichage temps réel karaoké des mots si présents
                                  if (item.words.isNotEmpty && isCurrent) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: item.words.map((w) {
                                        final bool isPast = _currentPosition >= w.end;
                                        final bool isActive = _currentPosition >= w.start && _currentPosition < w.end;
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isActive
                                                ? Colors.cyanAccent.withValues(alpha: 0.28)
                                                : (isPast
                                                    ? Colors.purple.withValues(alpha: 0.22)
                                                    : Colors.black38),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: isActive
                                                  ? Colors.cyanAccent
                                                  : (isPast
                                                      ? Colors.purpleAccent.withValues(alpha: 0.6)
                                                      : Colors.white12),
                                              width: isActive ? 1.0 : 0.6,
                                            ),
                                          ),
                                          child: Text(
                                            w.text,
                                            style: TextStyle(
                                              color: isActive
                                                  ? Colors.cyanAccent
                                                  : (isPast ? Colors.white : Colors.white54),
                                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 12,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
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
                  ),
          ),

          // 3. Barre de lecture Audio collante en bas
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            decoration: BoxDecoration(
              color: const Color(0xFF18181C),
              border: const Border(
                top: BorderSide(color: Colors.white12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Slider de progression
                Row(
                  children: [
                    Text(
                      _formatTimer(_currentPosition),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          activeTrackColor: Colors.purpleAccent,
                          inactiveTrackColor: Colors.white12,
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: _currentPosition.inMilliseconds
                              .toDouble()
                              .clamp(
                                0.0,
                                (_totalDuration.inMilliseconds > 0
                                        ? _totalDuration.inMilliseconds
                                        : 1)
                                    .toDouble(),
                              ),
                          max: (_totalDuration.inMilliseconds > 0
                                  ? _totalDuration.inMilliseconds
                                  : 1)
                              .toDouble(),
                          onChanged: (val) {
                            final target = Duration(milliseconds: val.toInt());
                            globalAudioHandler.seek(target);
                          },
                        ),
                      ),
                    ),
                    Text(
                      _formatTimer(_totalDuration),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),

                // Contrôles Play / Pause / Recul / Avance
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Recul 3s
                    IconButton(
                      icon: const Icon(CupertinoIcons.gobackward),
                      color: Colors.white70,
                      iconSize: 26,
                      onPressed: () {
                        final target =
                            _currentPosition - const Duration(seconds: 3);
                        globalAudioHandler.seek(
                          target.isNegative ? Duration.zero : target,
                        );
                      },
                    ),
                    const SizedBox(width: 20),

                    // Play / Pause
                    IconButton(
                      icon: Icon(
                        _isPlaying
                            ? CupertinoIcons.pause_circle_fill
                            : CupertinoIcons.play_circle_fill,
                      ),
                      color: Colors.white,
                      iconSize: 52,
                      onPressed: () {
                        if (_isPlaying) {
                          globalAudioHandler.pause();
                        } else {
                          globalAudioHandler.play();
                        }
                      },
                    ),
                    const SizedBox(width: 20),

                    // Avance 3s
                    IconButton(
                      icon: const Icon(CupertinoIcons.goforward),
                      color: Colors.white70,
                      iconSize: 26,
                      onPressed: () {
                        final target =
                            _currentPosition + const Duration(seconds: 3);
                        globalAudioHandler.seek(target);
                      },
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
}

class _OffsetButton extends StatelessWidget {
  final String label;
  final String? tooltip;
  final VoidCallback onTap;

  const _OffsetButton({
    required this.label,
    this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
