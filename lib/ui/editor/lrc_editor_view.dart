import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:musicality/core/globals.dart';
import 'package:musicality/core/models.dart';
import 'package:musicality/core/vps_sync_service.dart';

class _EditableLyricItem {
  Duration time;
  TextEditingController controller;
  final FocusNode focusNode;

  _EditableLyricItem({
    required this.time,
    required String text,
  })  : controller = TextEditingController(text: text),
        focusNode = FocusNode();

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
      if (mounted) {
        setState(() {
          _currentPosition = pos.position;
          _totalDuration = pos.duration;
        });
      }
    });

    _playbackSub = globalAudioHandler.playbackState.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });
  }

  void _initLyricsList() {
    for (final line in widget.initialLyrics) {
      // Ignorer les lignes de fallback
      if (line.text.toLowerCase().contains('paroles indisponibles')) {
        continue;
      }
      _items.add(_EditableLyricItem(time: line.time, text: line.text));
    }
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
        final newMs = (item.time.inMilliseconds + deltaMs).clamp(0, 9999999);
        item.time = Duration(milliseconds: newMs);
      }
    });
  }

  void _resetGlobalOffset() {
    HapticFeedback.mediumImpact();
    if (_globalOffsetSeconds == 0.0) return;
    setState(() {
      final deltaMs = (-_globalOffsetSeconds * 1000).round();
      for (final item in _items) {
        final newMs = (item.time.inMilliseconds + deltaMs).clamp(0, 9999999);
        item.time = Duration(milliseconds: newMs);
      }
      _globalOffsetSeconds = 0.0;
    });
  }

  void _adjustLine(int index, int deltaMs) {
    HapticFeedback.selectionClick();
    setState(() {
      final newMs = (_items[index].time.inMilliseconds + deltaMs).clamp(0, 9999999);
      _items[index].time = Duration(milliseconds: newMs);
    });
  }

  void _syncLineToCurrentPosition(int index) {
    HapticFeedback.heavyImpact();
    setState(() {
      _items[index].time = _currentPosition;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Ligne calée à ${VpsSyncService.formatTimestamp(_currentPosition)}',
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
  }

  void _addNewLine() {
    HapticFeedback.mediumImpact();
    setState(() {
      final newItem = _EditableLyricItem(
        time: _currentPosition,
        text: '',
      );
      _items.add(newItem);
      _sortItems();
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
    });
  }

  void _sortItems() {
    _items.sort((a, b) => a.time.compareTo(b.time));
  }

  Future<void> _saveAndUpload() async {
    if (_isSaving) return;

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Remplacer les paroles sur le VPS ?'),
        content: Text(
          'Cette action va formater ${_items.length} lignes de paroles au format .lrc, '
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
                    ],
                  ),
                ),
                // Boutons d'offset global rapide
                _OffsetButton(
                  label: '-0.5s',
                  onTap: () => _applyGlobalOffset(-0.5),
                ),
                const SizedBox(width: 4),
                _OffsetButton(
                  label: '-0.1s',
                  onTap: () => _applyGlobalOffset(-0.1),
                ),
                const SizedBox(width: 4),
                _OffsetButton(
                  label: '+0.1s',
                  onTap: () => _applyGlobalOffset(0.1),
                ),
                const SizedBox(width: 4),
                _OffsetButton(
                  label: '+0.5s',
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
                : ListView.separated(
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
                      final isCurrent = _currentPosition >= item.time &&
                          (index == _items.length - 1 ||
                              _currentPosition < _items[index + 1].time);

                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? Colors.purple.withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent
                                ? Colors.purpleAccent.withValues(alpha: 0.5)
                                : Colors.white12,
                          ),
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
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(6),
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
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
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
                          ],
                        ),
                      );
                    },
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
  final VoidCallback onTap;

  const _OffsetButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
