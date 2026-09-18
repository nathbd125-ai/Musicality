import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:musicality/core/globals.dart';
import 'package:flutter/material.dart';
import 'package:mmkv/mmkv.dart';

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _playerA = AudioPlayer(
    handleInterruptions: false,
    androidApplyAudioAttributes: false,
  );
  final AudioPlayer _playerB = AudioPlayer(
    handleInterruptions: false,
    androidApplyAudioAttributes: false,
  );

  late AudioPlayer _activePlayer;
  late AudioPlayer _nextPlayer;

  int _currentIndex = 0;
  bool _isSourceLoaded = false;
  String? _loadedSongId;
  bool _isPreparing = false;
  bool _isCrossfading = false;
  bool _isPreloading = false;
  int? _preloadedIndex;
  Future<void>? _preloadFuture;

  int _loadRequestId = 0;
  Timer? _skipDebounceTimer;
  Timer? _crossfadeTimer;
  Timer? _listeningTimer;
  int _currentSongListeningSeconds = 0;
  bool _hasScoredCurrentSong = false;
  String? _lastSongId;
  int _lastKnownPositionSecs = 0;

  String? _currentCachingUrl;
  HttpClient? _cacheHttpClient;
  IOSink? _currentCacheSink;

  final StreamController<LoopMode> _loopModeController =
      StreamController<LoopMode>.broadcast();
  final StreamController<bool> _shuffleModeController =
      StreamController<bool>.broadcast();

  LoopMode _loopMode = LoopMode.all;
  bool _shuffleModeEnabled = false;
  List<int> _shuffledIndices = [];
  final Map<String, bool> _contextShuffleStates = {};

  MyAudioHandler() {
    _activePlayer = _playerA;
    _nextPlayer = _playerB;

    try {
      final mmkv = MMKV.defaultMMKV();
      final savedLoop = mmkv.decodeString('saved_loop_mode');
      if (savedLoop == 'one') {
        _loopMode = LoopMode.one;
      } else if (savedLoop == 'off') {
        _loopMode = LoopMode.off;
      } else {
        _loopMode = LoopMode.all;
      }
      _shuffleModeEnabled = mmkv.decodeBool('saved_shuffle_mode', defaultValue: false);
      _contextShuffleStates['all_musics'] = _shuffleModeEnabled;
    } catch (e) {
      debugPrint("Erreur chargement persistance loop/shuffle: $e");
    }

    _initListeners();
    mediaItem.add(null);

    mediaItem.listen((item) {
      if (item != null && item.id != _lastSongId) {
        _flushPendingArtistListeningTime();
        _lastSongId = item.id;
        _currentSongListeningSeconds = 0;
        _hasScoredCurrentSong = false;
        _lastKnownPositionSecs = 0;
      }
    });

    isCrossfadeEnabledNotifier.addListener(() {
      if (isCrossfadeEnabledNotifier.value) {
        _checkNextPreload();
      } else if (_isCrossfading) {
        _cancelCrossfade();
      }
    });

    _initAudioSession();
    _broadcastState();
  }

  bool _playInterrupted = false;

  void _initAudioSession() async {
    final session = await AudioSession.instance;
    try {
      await session.configure(const AudioSessionConfiguration.music());
    } catch (e) {
      debugPrint("Erreur configuration AudioSession: $e");
    }

    // Gestion des priorités audio & interruptions (appels entrants, alarmes, etc.)
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            // Mise en pause immédiate lors d'un appel pour ne pas continuer à jouer en arrière-plan
            if (playbackState.value.playing) {
              _playInterrupted = true;
              pause();
            }
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
          case AudioInterruptionType.pause:
            // Fin de l'appel : reprise automatique
            if (_playInterrupted) {
              _playInterrupted = false;
              play();
            }
            break;
          case AudioInterruptionType.unknown:
            _playInterrupted = false;
            break;
        }
      }
    });

    // Casque ou écouteurs débranchés
    session.becomingNoisyEventStream.listen((_) {
      if (playbackState.value.playing) {
        pause();
      }
    });
  }

  int _pendingArtistSeconds = 0;
  String? _pendingArtistName;

  void _flushPendingArtistListeningTime() {
    if (_pendingArtistSeconds <= 0 || _pendingArtistName == null) return;
    final currentTimes = Map<String, int>.from(
      artistListeningTimeNotifier.value,
    );
    for (var a in extractArtists(_pendingArtistName!)) {
      currentTimes[a] = (currentTimes[a] ?? 0) + _pendingArtistSeconds;
    }
    _pendingArtistSeconds = 0;
    artistListeningTimeNotifier.value = currentTimes;
  }

  void _stopListeningTimer() {
    _flushPendingArtistListeningTime();
    _listeningTimer?.cancel();
    _listeningTimer = null;
  }

  void _startListeningTimer() {
    if (_listeningTimer != null && _listeningTimer!.isActive) return;
    _listeningTimer?.cancel();
    _listeningTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final playing = playbackState.value.playing;
      final currentItem = mediaItem.value;

      if (playing && currentItem != null) {
        // Sécurité volume : garantit qu'hors fondu le volume ne reste jamais bloqué à 0 en arrière-plan
        if (!_isCrossfading && _activePlayer.volume < 1.0) {
          _activePlayer.setVolume(1.0);
        }

        final currentPositionSecs = _activePlayer.position.inSeconds;
        if (_lastKnownPositionSecs > 10 && currentPositionSecs < 5) {
          _flushPendingArtistListeningTime();
          _currentSongListeningSeconds = 0;
          _hasScoredCurrentSong = false;
        }
        _lastKnownPositionSecs = currentPositionSecs;
        _currentSongListeningSeconds++;

        final artist = currentItem.artist ?? 'Inconnu';
        if (_pendingArtistName != null && _pendingArtistName != artist) {
          _flushPendingArtistListeningTime();
        }
        _pendingArtistName = artist;
        _pendingArtistSeconds++;

        // Sauvegarde groupée toutes les 5 secondes pour préserver le CPU et la batterie
        if (_pendingArtistSeconds >= 5) {
          _flushPendingArtistListeningTime();
        }

        final durationSecs = currentItem.duration?.inSeconds ?? 0;
        final fadeSecs = isCrossfadeEnabledNotifier.value
            ? (crossfadeDurationNotifier.value < 1 || crossfadeDurationNotifier.value > 12 ? 5 : crossfadeDurationNotifier.value)
            : 0;
        // Durée effective du titre en soustrayant le fondu enchaîné
        final effectiveDurationSecs = (durationSecs - fadeSecs).clamp(1, durationSecs);

        if (effectiveDurationSecs > 0 && !_hasScoredCurrentSong) {
          // Une écoute est comptabilisée quand le titre est écouté quasi entièrement (90% de la durée effective)
          if (_currentSongListeningSeconds >= (effectiveDurationSecs * 0.90)) {
            _hasScoredCurrentSong = true;
            updateArtistScore(artist, 1);

            final currentPlayCounts = Map<String, int>.from(
              songPlayCountNotifier.value,
            );
            currentPlayCounts[currentItem.id] =
                (currentPlayCounts[currentItem.id] ?? 0) + 1;
            songPlayCountNotifier.value = currentPlayCounts;
          }
        }

        // Vérification de déclenchement du Crossfade
        _checkCrossfadeTrigger();

        // Sauvegarde périodique de la session (debouncée)
        saveCurrentPlaybackSession();
      } else {
        _stopListeningTimer();
      }
    });
  }

  void _checkCrossfadeTrigger() {
    if (_isCrossfading || _isPreparing) return;

    final duration = _activePlayer.duration ?? mediaItem.value?.duration;
    final position = _activePlayer.position;
    if (duration == null || duration == Duration.zero) return;

    final totalSecs = duration.inSeconds;
    if (totalSecs <= 2) return;

    if (isCrossfadeEnabledNotifier.value) {
      int fadeSecs = crossfadeDurationNotifier.value;
      if (fadeSecs < 1 || fadeSecs > 12) fadeSecs = 5;
      if (fadeSecs * 2 >= totalSecs) {
        fadeSecs = (totalSecs / 2).floor();
      }
      if (fadeSecs < 1) fadeSecs = 1;

      final remainingDuration = duration - position;

      // 1. Déclenchement prioritaire du fondu enchaîné
      if (remainingDuration.inMilliseconds <= (fadeSecs * 1000) &&
          remainingDuration.inMilliseconds > 50 &&
          position.inMilliseconds > 1000) {
        final nextIdx = _getNextIndex();
        if (nextIdx != null) {
          _startCrossfade(nextIdx, fadeSecs);
        }
        return; // CRITIQUE : on quitte immédiatement pour éviter toute collision avec le préchargement
      }

      // 2. Préchargement anticipé de secours (si pas encore fait au démarrage)
      if (remainingDuration.inSeconds <= (fadeSecs + 15) &&
          position.inMilliseconds > 2000 &&
          !_isPreloading &&
          !_isCrossfading) {
        final nextIdx = _getNextIndex();
        if (nextIdx != null && nextIdx != _preloadedIndex) {
          _preloadNextSong(nextIdx);
        }
      }
    }
  }

  void _checkNextPreload() {
    if (!isCrossfadeEnabledNotifier.value) return;
    if (_isCrossfading || _isPreparing) return;
    final nextIdx = _getNextIndex();
    if (nextIdx == null) {
      if (_preloadedIndex != null) {
        _nextPlayer.stop();
        _preloadedIndex = null;
      }
      return;
    }
    if (nextIdx != _preloadedIndex) {
      _preloadNextSong(nextIdx);
    }
  }

  Future<void> _preloadNextSong(int nextIndex) async {
    if (!isCrossfadeEnabledNotifier.value) return;
    if (_isPreloading || _isCrossfading || _isPreparing) return;
    if (nextIndex < 0 || nextIndex >= queue.value.length) return;
    if (_preloadedIndex == nextIndex) return;

    _isPreloading = true;
    _preloadFuture = _doPreload(nextIndex);
    await _preloadFuture;
  }

  Future<void> _doPreload(int nextIndex) async {
    try {
      final nextItem = queue.value[nextIndex];
      final bool isSameSong = (nextIndex == _currentIndex) ||
          (mediaItem.value?.id == nextItem.id);
      final nextSource = _createSource(nextItem, isCrossfadeToSameSong: isSameSong);

      debugPrint("[CROSSFADE] Préchargement anticipé de : ${nextItem.title}");
      await _nextPlayer.stop();
      await _nextPlayer.setVolume(0.0);
      await _nextPlayer.setAudioSource(nextSource);
      await _nextPlayer.seek(Duration.zero);
      await _nextPlayer.pause();

      _preloadedIndex = nextIndex;
      debugPrint("[CROSSFADE] Préchargé avec succès en amont : ${nextItem.title}");
    } catch (e) {
      debugPrint("[CROSSFADE] Échec du préchargement : $e");
      _preloadedIndex = null;
    } finally {
      _isPreloading = false;
    }
  }

  int? _getNextIndex({bool ignoreRepeatOne = false}) {
    if (queue.value.isEmpty) return null;
    if (!ignoreRepeatOne && _loopMode == LoopMode.one) return _currentIndex;

    if (_shuffleModeEnabled && _shuffledIndices.isNotEmpty) {
      final currentPos = _shuffledIndices.indexOf(_currentIndex);
      if (currentPos != -1 && currentPos + 1 < _shuffledIndices.length) {
        return _shuffledIndices[currentPos + 1];
      } else if (_loopMode == LoopMode.all || ignoreRepeatOne) {
        return _shuffledIndices.first;
      }
      return null;
    }

    if (_currentIndex + 1 < queue.value.length) {
      return _currentIndex + 1;
    } else if (_loopMode == LoopMode.all || ignoreRepeatOne) {
      return 0;
    }
    return null;
  }

  int? _getPreviousIndex({bool ignoreRepeatOne = false}) {
    if (queue.value.isEmpty) return null;
    if (!ignoreRepeatOne && _loopMode == LoopMode.one) return _currentIndex;

    if (_shuffleModeEnabled && _shuffledIndices.isNotEmpty) {
      final currentPos = _shuffledIndices.indexOf(_currentIndex);
      if (currentPos > 0) {
        return _shuffledIndices[currentPos - 1];
      } else if (_loopMode == LoopMode.all || ignoreRepeatOne) {
        return _shuffledIndices.last;
      }
      return null;
    }

    if (_currentIndex - 1 >= 0) {
      return _currentIndex - 1;
    } else if (_loopMode == LoopMode.all || ignoreRepeatOne) {
      return queue.value.length - 1;
    }
    return null;
  }

  Future<void> _startCrossfade(int nextIndex, int fadeSecs) async {
    if (_isCrossfading) return;
    _isCrossfading = true;
    _crossfadeTimer?.cancel();

    // Si un préchargement est en cours sur _nextPlayer, on attend sa fin propre
    if (_isPreloading && _preloadFuture != null) {
      debugPrint("[CROSSFADE] Attente de la fin du préchargement en cours pour : ${queue.value[nextIndex].title}");
      try {
        await _preloadFuture;
      } catch (_) {}
    }

    final nextItem = queue.value[nextIndex];
    final bool isSameSong = (nextIndex == _currentIndex) ||
        (mediaItem.value?.id == nextItem.id);

    try {
      if (_preloadedIndex == nextIndex && _nextPlayer.audioSource != null) {
        debugPrint("[CROSSFADE] Lancement instantané (déjà préchargé) : ${nextItem.title}");
        await _nextPlayer.seek(Duration.zero);
        await _nextPlayer.setVolume(0.0);
        _nextPlayer.play();
      } else {
        debugPrint("[CROSSFADE] Chargement direct à chaud : ${nextItem.title}");
        final nextSource = _createSource(nextItem, isCrossfadeToSameSong: isSameSong);
        await _nextPlayer.stop();
        await _nextPlayer.setVolume(0.0);
        await _nextPlayer.setAudioSource(nextSource);
        await _nextPlayer.seek(Duration.zero);
        _nextPlayer.play();
      }
    } catch (e) {
      debugPrint("[CROSSFADE] Erreur lors de la préparation du crossfade : $e");
      _isCrossfading = false;
      _nextPlayer.stop();
      _nextPlayer.setVolume(1.0);
      _activePlayer.setVolume(1.0);
      return;
    } finally {
      _preloadedIndex = null;
    }

    if (!_isCrossfading || _isPreparing) {
      debugPrint("[CROSSFADE] Annulé pendant le chargement (seek/skip), on abandonne.");
      _nextPlayer.stop();
      _nextPlayer.setVolume(1.0);
      _activePlayer.setVolume(1.0);
      return;
    }

    // Juste avant de basculer : validation de l'écoute du morceau sortant
    if (!_hasScoredCurrentSong && mediaItem.value != null) {
      final oldItem = mediaItem.value!;
      final oldDuration = oldItem.duration?.inSeconds ?? 0;
      final effectiveDuration = (oldDuration - fadeSecs).clamp(1, oldDuration);
      if (_currentSongListeningSeconds >= (effectiveDuration * 0.90)) {
        _hasScoredCurrentSong = true;
        final oldArtist = oldItem.artist ?? 'Inconnu';
        updateArtistScore(oldArtist, 1);
        final currentPlayCounts = Map<String, int>.from(
          songPlayCountNotifier.value,
        );
        currentPlayCounts[oldItem.id] =
            (currentPlayCounts[oldItem.id] ?? 0) + 1;
        songPlayCountNotifier.value = currentPlayCounts;
      }
    }

    // Le 2ème son commence : on bascule immédiatement l'UI et les métadonnées sur le 2ème son
    final oldPlayer = _activePlayer;
    _activePlayer = _nextPlayer;
    _nextPlayer = oldPlayer;

    _currentIndex = nextIndex;
    mediaItem.add(nextItem);
    _loadedSongId = nextItem.id;
    saveCurrentPlaybackSession(forceFlush: true);
    _broadcastState();

    final remainingOldMs = (_nextPlayer.duration != null && _nextPlayer.position < _nextPlayer.duration!)
        ? (_nextPlayer.duration! - _nextPlayer.position).inMilliseconds
        : fadeSecs * 1000;
    final totalFadeMs = (remainingOldMs > 500 && remainingOldMs <= fadeSecs * 1000)
        ? remainingOldMs
        : fadeSecs * 1000;
    
    final startTime = DateTime.now();
    const intervalMs = 50;
    int pauseOffsetMs = 0;
    DateTime? lastPauseTime;

    _crossfadeTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      if (!_activePlayer.playing) {
        lastPauseTime ??= DateTime.now();
        return;
      } else if (lastPauseTime != null) {
        pauseOffsetMs += DateTime.now().difference(lastPauseTime!).inMilliseconds;
        lastPauseTime = null;
      }
      
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds - pauseOffsetMs;
      final progress = (elapsedMs / totalFadeMs).clamp(0.0, 1.0);

      // _activePlayer est le nouveau son (fade in: 0.0 -> 1.0)
      // _nextPlayer est l'ancien son en train de se terminer (fade out: 1.0 -> 0.0)
      _activePlayer.setVolume(progress);
      _nextPlayer.setVolume(1.0 - progress);

      if (progress >= 1.0) {
        timer.cancel();
        _completeCrossfade();
      }
    });

    // Watchdog de secours : garantit que même si le Timer est retardé par l'OS en arrière-plan (Doze mode),
    // le volume du morceau actif sera impérativement rétabli à 1.0 et le crossfade finalisé proprement.
    Timer(Duration(milliseconds: totalFadeMs + 500), () {
      if (_isCrossfading) {
        debugPrint("[CROSSFADE] Watchdog fin de fondu déclenché : forçage volume 1.0");
        _completeCrossfade();
      }
    });
  }

  void _completeCrossfade() {
    _crossfadeTimer?.cancel();
    _nextPlayer.stop();
    _nextPlayer.setVolume(1.0);
    _activePlayer.setVolume(1.0);
    _isCrossfading = false;
    _preloadedIndex = null;
    _broadcastState();

    // Une fois le fondu terminé, on précharge le morceau suivant avec un léger délai
    Future.delayed(const Duration(seconds: 2), () {
      if (!_isCrossfading && !_isPreparing && playbackState.value.playing) {
        _checkNextPreload();
      }
    });
  }

  void _cancelCrossfade() {
    _crossfadeTimer?.cancel();
    _isCrossfading = false;
    _preloadedIndex = null;
    _nextPlayer.stop();
    _nextPlayer.setVolume(1.0);
    _activePlayer.setVolume(1.0);
  }

  void _initListeners() {
    void handlePlayerEvent(AudioPlayer player) {
      player.playerStateStream.listen((state) {
        if (player == _activePlayer) {
          if (state.playing) {
            _startListeningTimer();
          } else {
            _stopListeningTimer();
          }
          _broadcastState();

          // Passage au morceau suivant dès que le morceau s'est terminé
          if (state.processingState == ProcessingState.completed &&
              !_isPreparing) {
            if (_isCrossfading) {
              _completeCrossfade();
            }
            _activePlayer.setVolume(1.0);
            manageCacheSize();
            final nextIdx = _getNextIndex();
            if (nextIdx != null) {
              skipToQueueItem(nextIdx);
            } else {
              stop();
            }
          }
        }
      });

      player.durationStream.listen((duration) {
        if (player == _activePlayer && duration != null && duration != Duration.zero) {
          if (_currentIndex >= 0 && _currentIndex < queue.value.length) {
            final currentQueue = List<MediaItem>.from(queue.value);
            final oldItem = currentQueue[_currentIndex];

            if (oldItem.duration != duration) {
              final newItem = oldItem.copyWith(duration: duration);
              currentQueue[_currentIndex] = newItem;
              queue.add(currentQueue);

              if (mediaItem.value?.id == newItem.id) {
                mediaItem.add(newItem);
              }

              final globalIndex = globalPlaylist.indexWhere(
                (e) => e.id == newItem.id,
              );
              if (globalIndex != -1) {
                globalPlaylist[globalIndex] = newItem;
              }
            }
          }
        }
      });

      player.positionStream.listen((_) {
        if (player == _activePlayer) {
          _checkCrossfadeTrigger();
        }
      });
    }

    handlePlayerEvent(_playerA);
    handlePlayerEvent(_playerB);
  }

  void _broadcastState() {
    final playing = _activePlayer.playing;

    AudioServiceRepeatMode systemRepeatMode = AudioServiceRepeatMode.none;
    if (_loopMode == LoopMode.one) {
      systemRepeatMode = AudioServiceRepeatMode.one;
    } else if (_loopMode == LoopMode.all) {
      systemRepeatMode = AudioServiceRepeatMode.all;
    }

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.setRepeatMode,
          MediaAction.setShuffleMode,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_activePlayer.processingState]!,
        playing: playing,
        updatePosition: _isPreparing ? Duration.zero : _activePlayer.position,
        bufferedPosition: _isPreparing ? Duration.zero : _activePlayer.bufferedPosition,
        speed: _activePlayer.speed,
        queueIndex: _currentIndex,
        repeatMode: systemRepeatMode,
        shuffleMode: _shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  DateTime _lastCacheCheckTime = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> manageCacheSize() async {
    if (!isCacheEnabledNotifier.value) return;
    final now = DateTime.now();
    if (now.difference(_lastCacheCheckTime).inMinutes < 5) return;
    _lastCacheCheckTime = now;

    scheduleMicrotask(() async {
      try {
        final cacheDir = Directory('$globalDocumentPath/cache');
        if (!await cacheDir.exists()) return;

        final int limitBytes = cacheLimitNotifier.value * 1024 * 1024;
        final entities = await cacheDir.list().toList();

        // Nettoyage des fichiers temporaires .part obsolètes (> 30 minutes)
        for (final entity in entities.whereType<File>()) {
          if (entity.path.endsWith('.part')) {
            try {
              if (now.difference(entity.lastModifiedSync()).inMinutes > 30) {
                entity.deleteSync();
              }
            } catch (_) {}
          }
        }

        final List<File> cachedFiles = entities
            .whereType<File>()
            .where((f) => !f.path.endsWith('.part'))
            .toList();

        if (cachedFiles.isEmpty) return;

        int totalSize = 0;
        for (final file in cachedFiles) {
          try {
            totalSize += await file.length();
          } catch (_) {}
        }

        if (totalSize <= limitBytes) return;

        // Trie par date de dernier accès/modification croissante : les plus anciens en premier (LRU)
        cachedFiles.sort((a, b) {
          try {
            return a.lastModifiedSync().compareTo(b.lastModifiedSync());
          } catch (_) {
            return 0;
          }
        });

        final currentMediaItem = mediaItem.value;
        final Set<String> protectedNames = {};

        if (currentMediaItem != null) {
          protectedNames.add(getSafeFileName(currentMediaItem.id));
          protectedNames.add(getBaseId(currentMediaItem.id));
          protectedNames.add(currentMediaItem.id.split('/').last.replaceAll(RegExp(r'(-hires)?\.(flac|mp3)$'), ''));
        }

        if (_preloadedIndex != null && _preloadedIndex! < queue.value.length) {
          final preloadedItem = queue.value[_preloadedIndex!];
          protectedNames.add(getSafeFileName(preloadedItem.id));
          protectedNames.add(getBaseId(preloadedItem.id));
        }

        final nextIdx = _getNextIndex();
        if (nextIdx != null && nextIdx < queue.value.length) {
          final nextItem = queue.value[nextIdx];
          protectedNames.add(getSafeFileName(nextItem.id));
          protectedNames.add(getBaseId(nextItem.id));
        }

        protectedNames.removeWhere((name) => name.trim().isEmpty);

        for (final file in cachedFiles) {
          if (totalSize <= limitBytes) break;

          final fileName = file.uri.pathSegments.last.toLowerCase();
          final bool isProtected = protectedNames.any((name) {
            final lowerName = name.toLowerCase();
            return fileName.contains(lowerName) || lowerName.contains(fileName.replaceAll(RegExp(r'(-hires)?\.(flac|mp3)$'), ''));
          });

          // On ne supprime JAMAIS le morceau en cours d'écoute ni le prochain préchargé
          if (isProtected) {
            continue;
          }

          try {
            final fileSize = await file.length();
            await file.delete();
            totalSize -= fileSize;
          } catch (e) {
            debugPrint("Erreur lors de la suppression du cache ($file) : $e");
          }
        }
      } catch (e) {
        debugPrint("Erreur manageCacheSize : $e");
      }
    });
  }

  void _updatePlaylist(MediaItem newItem) {
    final idx = globalPlaylist.indexWhere((e) => e.id == newItem.id);
    if (idx != -1) globalPlaylist[idx] = newItem;

    final qIdx = queue.value.indexWhere((e) => e.id == newItem.id);
    if (qIdx != -1) {
      final currentQueue = List<MediaItem>.from(queue.value);
      currentQueue[qIdx] = newItem;
      queue.add(currentQueue);
    }
  }

  AudioSource _createSource(MediaItem item, {bool isCrossfadeToSameSong = false}) {
    final baseUri = item.id.replaceAll(RegExp(r'(-hires)?\.(flac|mp3)$'), '');
    final safeName = baseUri.split('/').last;
    File manualHiRes = File('$globalDocumentPath/$safeName-hires.flac');
    File manualFlac = File('$globalDocumentPath/$safeName.flac');
    File manualMp3 = File('$globalDocumentPath/$safeName.mp3');

    File cacheHiRes = File('$globalDocumentPath/cache/$safeName-hires.flac');
    File cacheFlac = File('$globalDocumentPath/cache/$safeName.flac');
    File cacheMp3 = File('$globalDocumentPath/cache/$safeName.mp3');

    bool wantFlac = isLosslessNotifier.value;
    bool wantHiRes = isHiResNotifier.value;
    bool hasFlac = item.extras?['hasFlac'] as bool? ?? true;
    bool hasHiRes = item.extras?['hasHiRes'] as bool? ?? false;
    bool useCache = isCacheEnabledNotifier.value;

    // Si on demande du Hi-Res mais que la chanson n'en a pas, on retombe sur le FLAC normal
    if (wantHiRes && !hasHiRes) {
      wantHiRes = false;
    }
    
    // Si on s'apprête à lire du FLAC normal mais qu'il n'y en a pas, on retombe sur MP3
    if (wantFlac && !wantHiRes && !hasFlac) {
      wantFlac = false;
    }

    // Suppression des anciens caches si on lit une qualité supérieure (et que le cache est activé)
    if (useCache) {
      if (wantHiRes) {
        if (cacheFlac.existsSync()) {
          try { cacheFlac.deleteSync(); } catch (_) { /* ignore */ }
        }
        if (cacheMp3.existsSync()) {
          try { cacheMp3.deleteSync(); } catch (_) { /* ignore */ }
        }
      } else if (wantFlac) {
        if (cacheMp3.existsSync()) {
          try { cacheMp3.deleteSync(); } catch (_) { /* ignore */ }
        }
      }
    }

    // Si la musique est téléchargée manuellement, suppression automatique de tout cache inférieur ou redondant
    if (manualHiRes.existsSync()) {
      if (cacheHiRes.existsSync()) { try { cacheHiRes.deleteSync(); } catch (_) {} }
      if (cacheFlac.existsSync()) { try { cacheFlac.deleteSync(); } catch (_) {} }
      if (cacheMp3.existsSync()) { try { cacheMp3.deleteSync(); } catch (_) {} }
    } else if (manualFlac.existsSync()) {
      if (cacheFlac.existsSync()) { try { cacheFlac.deleteSync(); } catch (_) {} }
      if (cacheMp3.existsSync()) { try { cacheMp3.deleteSync(); } catch (_) {} }
    } else if (manualMp3.existsSync()) {
      if (cacheMp3.existsSync()) { try { cacheMp3.deleteSync(); } catch (_) {} }
    }

    bool isValidFile(File f) {
      try {
        return f.existsSync() && f.lengthSync() > 0;
      } catch (_) {
        return false;
      }
    }

    bool isFlac = false;
    bool isHiRes = false;
    String fileOrUrl = "";
    File? targetCacheFile;

    if (wantHiRes) {
      if (isValidFile(manualHiRes)) {
        isFlac = true; isHiRes = true; fileOrUrl = manualHiRes.path;
      } else if (isValidFile(cacheHiRes)) {
        isFlac = true; isHiRes = true; fileOrUrl = cacheHiRes.path;
        try { cacheHiRes.setLastModifiedSync(DateTime.now()); } catch (_) {}
      } else {
        isFlac = true; isHiRes = true; fileOrUrl = '$baseUri-hires.flac';
        if (useCache) targetCacheFile = cacheHiRes;
      }
    } else if (wantFlac) {
      if (isValidFile(manualHiRes)) {
        isFlac = true; isHiRes = true; fileOrUrl = manualHiRes.path;
      } else if (isValidFile(cacheHiRes)) {
        isFlac = true; isHiRes = true; fileOrUrl = cacheHiRes.path;
        try { cacheHiRes.setLastModifiedSync(DateTime.now()); } catch (_) {}
      } else if (isValidFile(manualFlac)) {
        isFlac = true; isHiRes = false; fileOrUrl = manualFlac.path;
      } else if (isValidFile(cacheFlac)) {
        isFlac = true; isHiRes = false; fileOrUrl = cacheFlac.path;
        try { cacheFlac.setLastModifiedSync(DateTime.now()); } catch (_) {}
      } else {
        isFlac = true; isHiRes = false; fileOrUrl = '$baseUri.flac';
        if (useCache) targetCacheFile = cacheFlac;
      }
    } else {
      if (isValidFile(manualHiRes)) {
        isFlac = true; isHiRes = true; fileOrUrl = manualHiRes.path;
      } else if (isValidFile(cacheHiRes)) {
        isFlac = true; isHiRes = true; fileOrUrl = cacheHiRes.path;
        try { cacheHiRes.setLastModifiedSync(DateTime.now()); } catch (_) {}
      } else if (isValidFile(manualFlac)) {
        isFlac = true; isHiRes = false; fileOrUrl = manualFlac.path;
      } else if (isValidFile(cacheFlac)) {
        isFlac = true; isHiRes = false; fileOrUrl = cacheFlac.path;
        try { cacheFlac.setLastModifiedSync(DateTime.now()); } catch (_) {}
      } else if (isValidFile(manualMp3)) {
        isFlac = false; isHiRes = false; fileOrUrl = manualMp3.path;
      } else if (isValidFile(cacheMp3)) {
        isFlac = false; isHiRes = false; fileOrUrl = cacheMp3.path;
        try { cacheMp3.setLastModifiedSync(DateTime.now()); } catch (_) {}
      } else {
        isFlac = false; isHiRes = false; fileOrUrl = '$baseUri.mp3';
        if (useCache) targetCacheFile = cacheMp3;
      }
    }

    final newItem = item.copyWith(
      extras: {'isFlac': isFlac, 'hasFlac': hasFlac, 'isHiRes': isHiRes},
    );
    _updatePlaylist(newItem);
    if (mediaItem.value?.id == newItem.id) {
      mediaItem.add(newItem);
    }

    if (isValidFile(File(fileOrUrl))) {
      return AudioSource.file(fileOrUrl, tag: newItem);
    } else {
      final safeUri = Uri.parse(fileOrUrl.replaceAll('#', '%23'));
      if (targetCacheFile != null && !isCrossfadeToSameSong) {
        manageCacheSize();
        // Téléchargement continu et intégral en tâche de fond à pleine vitesse (sans attendre le curseur)
        _startBackgroundCache(safeUri, targetCacheFile);
      }
      return AudioSource.uri(safeUri, tag: newItem);
    }
  }

  void _cancelBackgroundCache() {
    try {
      _cacheHttpClient?.close(force: true);
      _currentCacheSink?.close();
    } catch (_) {}
    _cacheHttpClient = null;
    _currentCacheSink = null;
    _currentCachingUrl = null;
  }

  void _startBackgroundCache(Uri url, File targetFile) {
    if (!isCacheEnabledNotifier.value) return;
    if (targetFile.existsSync() && targetFile.lengthSync() > 0) return;
    if (_currentCachingUrl == url.toString()) return;

    _cancelBackgroundCache();
    _currentCachingUrl = url.toString();

    final partFile = File('${targetFile.path}.part');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    _cacheHttpClient = client;

    Future<void>(() async {
      try {
        final request = await client.getUrl(url);
        final response = await request.close();

        if (response.statusCode != 200 && response.statusCode != 206) {
          debugPrint("[CACHE] Erreur HTTP ${response.statusCode} lors de la mise en cache de $url");
          return;
        }

        if (partFile.existsSync()) {
          try { partFile.deleteSync(); } catch (_) {}
        }
        final sink = partFile.openWrite();
        _currentCacheSink = sink;

        await response.listen(
          (chunk) {
            sink.add(chunk);
          },
          cancelOnError: true,
        ).asFuture();

        await sink.flush();
        await sink.close();
        _currentCacheSink = null;

        if (await partFile.exists() && await partFile.length() > 5000) {
          if (await targetFile.exists()) {
            try { await targetFile.delete(); } catch (_) {}
          }
          await partFile.rename(targetFile.path);
          debugPrint("[CACHE] Morceau intégralement mis en cache avec succès : ${targetFile.path}");
          manageCacheSize();
          _preloadNextSongToCache();
        }
      } catch (e) {
        if (_currentCachingUrl == url.toString()) {
          debugPrint("[CACHE] Téléchargement continu interrompu : $e");
        }
        if (partFile.existsSync()) {
          try { partFile.deleteSync(); } catch (_) {}
        }
      } finally {
        if (_currentCachingUrl == url.toString()) {
          _currentCachingUrl = null;
          _cacheHttpClient = null;
        }
      }
    });
  }

  void _preloadNextSongToCache() {
    if (!isCacheEnabledNotifier.value) return;
    final nextIdx = _getNextIndex();
    if (nextIdx == null || nextIdx >= queue.value.length) return;
    final nextItem = queue.value[nextIdx];
    final safeName = getSafeFileName(nextItem.id);

    final bool wantFlac = isLosslessNotifier.value;
    final bool wantHiRes = isHiResNotifier.value;
    final bool hasFlac = nextItem.extras?['hasFlac'] as bool? ?? true;
    final bool hasHiRes = nextItem.extras?['hasHiRes'] as bool? ?? false;

    File targetFile;
    String targetUrl;
    final baseUri = nextItem.id.replaceAll(RegExp(r'(-hires)?\.(flac|mp3)$'), '');

    if (wantHiRes && hasHiRes) {
      targetFile = File('$globalDocumentPath/cache/$safeName-hires.flac');
      targetUrl = '$baseUri-hires.flac';
    } else if ((wantHiRes || wantFlac) && hasFlac) {
      targetFile = File('$globalDocumentPath/cache/$safeName.flac');
      targetUrl = '$baseUri.flac';
    } else {
      targetFile = File('$globalDocumentPath/cache/$safeName.mp3');
      targetUrl = '$baseUri.mp3';
    }

    if (targetFile.existsSync() && targetFile.lengthSync() > 0) return;
    _startBackgroundCache(Uri.parse(targetUrl.replaceAll('#', '%23')), targetFile);
  }

  Future<void> playFromList(
    List<MediaItem> newQueue,
    int startIndex, {
    String? contextTag,
    bool? forceShuffle,
  }) async {
    final int currentReqId = ++_loadRequestId;
    _isPreparing = true;
    _cancelCrossfade();
    _preloadedIndex = null;
    _activePlayer.setVolume(1.0);
    currentPlaybackContextNotifier.value = contextTag;

    final effectiveCtx = contextTag ?? 'all_musics';
    if (forceShuffle != null) {
      _shuffleModeEnabled = forceShuffle;
      _contextShuffleStates[effectiveCtx] = forceShuffle;
    } else if (_contextShuffleStates.containsKey(effectiveCtx)) {
      _shuffleModeEnabled = _contextShuffleStates[effectiveCtx]!;
    }
    _shuffleModeController.add(_shuffleModeEnabled);
    _persistShuffleMode();

    // Fast-path : N'émettre sur queue.add QUE si la liste a réellement changé.
    // Évite de re-sérialiser 300+ morceaux via Platform Channel à chaque clic dans AllMusicsView !
    final bool isQueueIdentical = queue.value.length == newQueue.length &&
        (identical(queue.value, newQueue) ||
         (queue.value.isNotEmpty && newQueue.isNotEmpty && queue.value.first.id == newQueue.first.id));

    if (!isQueueIdentical) {
      queue.add(newQueue);
      _generateShuffleIndices(newQueue.length);
    } else if (_shuffledIndices.length != newQueue.length) {
      _generateShuffleIndices(newQueue.length);
    }

    _skipDebounceTimer?.cancel();

    if (startIndex >= 0 && startIndex < newQueue.length) {
      _currentIndex = startIndex;
      final item = newQueue[startIndex];
      mediaItem.add(item);
      _broadcastState();

      _skipDebounceTimer = Timer(const Duration(milliseconds: 100), () async {
        if (currentReqId != _loadRequestId) return;
        try {
          final source = _createSource(item);
          if (currentReqId != _loadRequestId) return;

          await _activePlayer.setAudioSource(source);
          if (currentReqId != _loadRequestId) return;

          _loadedSongId = item.id;
          await _activePlayer.seek(Duration.zero);
          if (currentReqId != _loadRequestId) return;

          _activePlayer.play();
        } catch (e) {
          if (currentReqId == _loadRequestId) {
            debugPrint("Erreur playFromList : $e");
          }
        } finally {
          if (currentReqId == _loadRequestId) {
            _isPreparing = false;
            _isSourceLoaded = true;
            saveCurrentPlaybackSession(forceFlush: true);
            _broadcastState();

            // Préchargement immédiat du prochain morceau 2 secondes après le démarrage
            Future.delayed(const Duration(seconds: 2), () {
              if (currentReqId == _loadRequestId &&
                  !_isCrossfading &&
                  !_isPreparing &&
                  playbackState.value.playing) {
                _checkNextPreload();
              }
            });
          }
        }
      });
    }
  }

  void _generateShuffleIndices(int length) {
    _shuffledIndices = List<int>.generate(length, (i) => i)..shuffle();
  }

  Future<void> reloadAudioSourcesForQuality() async {
    if (!_isSourceLoaded) return;
    if (_currentIndex < 0 || _currentIndex >= queue.value.length) return;

    final currentItem = queue.value[_currentIndex];
    final oldIsFlac = currentItem.extras?['isFlac'] as bool? ?? false;
    final oldIsHiRes = currentItem.extras?['isHiRes'] as bool? ?? false;

    final masterIdx = globalPlaylist.indexWhere((e) => e.id == currentItem.id);
    final baseItem = masterIdx != -1 ? globalPlaylist[masterIdx] : currentItem;

    final bool hasFlac = baseItem.extras?['hasFlac'] as bool? ?? true;
    final bool hasHiRes = baseItem.extras?['hasHiRes'] as bool? ?? false;

    final bool targetHiRes = isHiResNotifier.value && hasHiRes;
    final bool targetFlac = (isLosslessNotifier.value && hasFlac) || targetHiRes;

    final String safeName = baseItem.id.split('/').last.replaceAll(RegExp(r'(-hires)?\.(flac|mp3)$'), '');
    final File manualHiRes = File('$globalDocumentPath/$safeName-hires.flac');
    final File cacheHiRes = File('$globalDocumentPath/cache/$safeName-hires.flac');
    final File manualFlac = File('$globalDocumentPath/$safeName.flac');
    final File cacheFlac = File('$globalDocumentPath/cache/$safeName.flac');

    bool isValidFile(File f) {
      try {
        return f.existsSync() && f.lengthSync() > 0;
      } catch (_) {
        return false;
      }
    }

    bool newIsHiRes = false;
    bool newIsFlac = false;

    if (targetHiRes) {
      newIsHiRes = true;
      newIsFlac = true;
    } else if (targetFlac) {
      if (isValidFile(manualHiRes) || isValidFile(cacheHiRes)) {
        newIsHiRes = true;
        newIsFlac = true;
      } else {
        newIsHiRes = false;
        newIsFlac = true;
      }
    } else {
      if (isValidFile(manualHiRes) || isValidFile(cacheHiRes)) {
        newIsHiRes = true;
        newIsFlac = true;
      } else if (isValidFile(manualFlac) || isValidFile(cacheFlac)) {
        newIsHiRes = false;
        newIsFlac = true;
      } else {
        newIsHiRes = false;
        newIsFlac = false;
      }
    }

    if (oldIsFlac != newIsFlac || oldIsHiRes != newIsHiRes) {
      final currentPos = _activePlayer.position;
      final wasPlaying = _activePlayer.playing;
      final newSource = _createSource(baseItem);

      await _activePlayer.setAudioSource(newSource);
      _loadedSongId = baseItem.id;
      await _activePlayer.seek(currentPos);
      if (wasPlaying) _activePlayer.play();

      final updatedItem = mediaItem.value ?? baseItem;
      final currentQueue = List<MediaItem>.from(queue.value);
      currentQueue[_currentIndex] = updatedItem;
      queue.add(currentQueue);
    }
  }

  Stream<LoopMode> get loopModeStream => _loopModeController.stream;
  Stream<bool> get shuffleModeEnabledStream => _shuffleModeController.stream;

  LoopMode get loopMode => _loopMode;
  bool get shuffleModeEnabled => _shuffleModeEnabled;

  void _persistLoopMode() {
    try {
      final mmkv = MMKV.defaultMMKV();
      mmkv.encodeString('saved_loop_mode', _loopMode.name);
    } catch (_) {}
  }

  void _persistShuffleMode() {
    try {
      final mmkv = MMKV.defaultMMKV();
      mmkv.encodeBool('saved_shuffle_mode', _shuffleModeEnabled);
    } catch (_) {}
  }

  static const String _kLastSongIdKey = 'last_played_song_id';
  static const String _kLastPositionMsKey = 'last_played_position_ms';
  static const String _kLastContextTagKey = 'last_played_context_tag';
  static const String _kLastQueueIdsKey = 'last_played_queue_ids';

  int _lastSavedPositionMs = -1;
  DateTime _lastSaveTime = DateTime.fromMillisecondsSinceEpoch(0);

  void saveCurrentPlaybackSession({bool forceFlush = false}) {
    final currentItem = mediaItem.value;
    if (currentItem == null || currentItem.id.trim().isEmpty) return;

    final now = DateTime.now();
    final currentPosition = _activePlayer.position;
    final currentPosMs = currentPosition.inMilliseconds;

    // Éviter d'écrire en boucle si la position n'a pas bougé d'au moins 1 seconde (sauf forceFlush)
    if (!forceFlush) {
      if (now.difference(_lastSaveTime).inMilliseconds < 2000) return;
      if ((_lastSavedPositionMs - currentPosMs).abs() < 1000) {
        return;
      }
    }

    _lastSaveTime = now;

    try {
      final mmkv = MMKV.defaultMMKV();
      mmkv.encodeString(_kLastSongIdKey, currentItem.id);
      mmkv.encodeInt(_kLastPositionMsKey, currentPosMs);
      _lastSavedPositionMs = currentPosMs;

      final ctx = currentPlaybackContextNotifier.value ?? 'all_musics';
      mmkv.encodeString(_kLastContextTagKey, ctx);

      // Sauvegarder la file actuelle d'écoute (max 200 IDs pour rester ultra léger)
      final queueIds = queue.value.map((m) => m.id).take(200).toList();
      if (queueIds.isNotEmpty) {
        mmkv.encodeString(_kLastQueueIdsKey, jsonEncode(queueIds));
      }
    } catch (e) {
      debugPrint("Erreur sauvegarde session de lecture : $e");
    }
  }

  Future<void> restoreLastSession() async {
    try {
      final mmkv = MMKV.defaultMMKV();
      final lastSongId = mmkv.decodeString(_kLastSongIdKey);
      if (lastSongId == null || lastSongId.trim().isEmpty) return;

      // Si un média est déjà chargé et actif (ex: reprise rapide), ne pas écraser
      if (mediaItem.value != null) return;
      if (globalPlaylist.isEmpty) {
        loadMusiquesFromCache();
      }
      if (globalPlaylist.isEmpty) return;

      // Recherche du MediaItem dans globalPlaylist (par ID exact ou nom de fichier)
      int songIndex = globalPlaylist.indexWhere((m) => m.id == lastSongId);
      if (songIndex == -1) {
        final cleanTarget = lastSongId.split('/').last.replaceAll(RegExp(r'(-hires)?\.(flac|mp3)$'), '');
        songIndex = globalPlaylist.indexWhere((e) {
          final eClean = e.id.split('/').last.replaceAll(RegExp(r'(-hires)?\.(flac|mp3)$'), '');
          return eClean == cleanTarget;
        });
      }
      if (songIndex == -1) return;

      final targetSong = globalPlaylist[songIndex];

      // Restauration de la file d'attente (queue)
      List<MediaItem> restoredQueue = [];
      final queueIdsJson = mmkv.decodeString(_kLastQueueIdsKey);
      if (queueIdsJson != null && queueIdsJson.isNotEmpty) {
        try {
          final List<dynamic> decodedIds = jsonDecode(queueIdsJson);
          final Map<String, MediaItem> songMap = {
            for (var m in globalPlaylist) m.id: m,
          };
          for (final id in decodedIds) {
            final m = songMap[id.toString()];
            if (m != null) restoredQueue.add(m);
          }
        } catch (e) {
          debugPrint("Erreur décodage file restaurée : $e");
        }
      }

      if (restoredQueue.isEmpty) {
        restoredQueue = List<MediaItem>.from(globalPlaylist);
      }

      final savedContextTag = mmkv.decodeString(_kLastContextTagKey);
      currentPlaybackContextNotifier.value = savedContextTag ?? 'all_musics';

      int targetIndex = restoredQueue.indexWhere((m) => m.id == lastSongId);
      if (targetIndex == -1) {
        targetIndex = 0;
      }

      _currentIndex = targetIndex;
      queue.add(restoredQueue);
      mediaItem.add(targetSong);

      if (_shuffleModeEnabled) {
        _generateShuffleIndices(restoredQueue.length);
      }

      final savedPositionMs = mmkv.decodeInt(_kLastPositionMsKey, defaultValue: 0);
      Duration targetPosition = Duration.zero;
      final songDurationMs = targetSong.duration?.inMilliseconds ?? 0;

      // Si le morceau a été sauvegardé alors qu'il était quasi fini (< 3s de la fin), on repart à 0
      if (savedPositionMs > 0) {
        if (songDurationMs > 0 && savedPositionMs >= songDurationMs - 3000) {
          targetPosition = Duration.zero;
        } else {
          targetPosition = Duration(milliseconds: savedPositionMs);
        }
      }

      _isPreparing = true;
      try {
        final source = _createSource(targetSong);
        await _activePlayer.setAudioSource(source);
        _loadedSongId = targetSong.id;
        if (targetPosition > Duration.zero) {
          await _activePlayer.seek(targetPosition);
        }
      } catch (e) {
        debugPrint("Erreur pré-chargement session audio : $e");
      } finally {
        _isPreparing = false;
        _isSourceLoaded = true;
        _broadcastState();
      }

      debugPrint("🎵 [SessionRestore] Restauration réussie : ${targetSong.title} à ${targetPosition.inSeconds}s (pause)");
    } catch (e, st) {
      debugPrint("Erreur lors de la restauration de la session de lecture : $e\n$st");
    }
  }

  Future<void> toggleLoopMode() async {
    if (_loopMode == LoopMode.all) {
      _loopMode = LoopMode.one;
    } else if (_loopMode == LoopMode.one) {
      _loopMode = LoopMode.off;
    } else {
      _loopMode = LoopMode.all;
    }
    _persistLoopMode();
    _loopModeController.add(_loopMode);
    _broadcastState();
    _checkNextPreload();
  }

  Future<void> toggleShuffleMode() async {
    _shuffleModeEnabled = !_shuffleModeEnabled;
    final currentCtx = currentPlaybackContextNotifier.value ?? 'all_musics';
    _contextShuffleStates[currentCtx] = _shuffleModeEnabled;
    if (_shuffleModeEnabled) {
      _generateShuffleIndices(queue.value.length);
    }
    _persistShuffleMode();
    _shuffleModeController.add(_shuffleModeEnabled);
    _broadcastState();
    _checkNextPreload();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        _loopMode = LoopMode.off;
        break;
      case AudioServiceRepeatMode.one:
        _loopMode = LoopMode.one;
        break;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        _loopMode = LoopMode.all;
        break;
    }
    _persistLoopMode();
    _loopModeController.add(_loopMode);
    _broadcastState();
    _checkNextPreload();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _shuffleModeEnabled = (shuffleMode == AudioServiceShuffleMode.all);
    final currentCtx = currentPlaybackContextNotifier.value ?? 'all_musics';
    _contextShuffleStates[currentCtx] = _shuffleModeEnabled;
    if (_shuffleModeEnabled) {
      _generateShuffleIndices(queue.value.length);
    }
    _persistShuffleMode();
    _shuffleModeController.add(_shuffleModeEnabled);
    _broadcastState();
    _checkNextPreload();
  }

  bool getShuffleModeForContext(String contextTag) {
    return _contextShuffleStates[contextTag] ?? false;
  }

  Future<void> updateSourceAt(
    String id,
    AudioSource newSource,
    MediaItem newItem,
  ) async {
    final currentQueue = List<MediaItem>.from(queue.value);
    final index = currentQueue.indexWhere((e) => e.id == id);
    if (index >= 0) {
      currentQueue[index] = newItem;
      queue.add(currentQueue);
      if (_currentIndex == index) {
        mediaItem.add(newItem);
      }
    }
  }

  Future<void> updateSourceForId(String id) async {
    final currentQueue = List<MediaItem>.from(queue.value);
    final index = currentQueue.indexWhere((e) => e.id == id);
    if (index >= 0) {
      final masterIdx = globalPlaylist.indexWhere((e) => e.id == id);
      final newItem = masterIdx != -1 ? globalPlaylist[masterIdx] : currentQueue[index];
      currentQueue[index] = newItem;
      queue.add(currentQueue);
      if (_currentIndex == index) {
        mediaItem.add(newItem);
      }
    }
  }

  @override
  Future<void> play() async {
    final session = await AudioSession.instance;
    if (await session.setActive(true)) {
      _activePlayer.play();
      if (_isCrossfading) {
        _nextPlayer.play();
      }
      _broadcastState();
    }
  }

  @override
  Future<void> pause() async {
    await _activePlayer.pause();
    if (_isCrossfading) {
      await _nextPlayer.pause();
    }
    saveCurrentPlaybackSession(forceFlush: true);
    _broadcastState();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_isCrossfading) {
      _cancelCrossfade();
    }
    // On conserve _preloadedIndex pour permettre un crossfade immédiat même après un seek
    await _activePlayer.seek(position);
    saveCurrentPlaybackSession(forceFlush: true);
    _broadcastState();
  }

  @override
  Future<void> skipToNext() async {
    final nextIdx = _getNextIndex(ignoreRepeatOne: true);
    if (nextIdx != null) {
      _currentIndex = nextIdx;
      _isPreparing = true;
      if (nextIdx < queue.value.length) {
        mediaItem.add(queue.value[nextIdx]);
      }
      _broadcastState();

      _skipDebounceTimer?.cancel();
      _skipDebounceTimer = Timer(const Duration(milliseconds: 200), () {
        skipToQueueItem(_currentIndex);
      });
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_activePlayer.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    final prevIdx = _getPreviousIndex(ignoreRepeatOne: true);
    if (prevIdx != null) {
      _currentIndex = prevIdx;
      _isPreparing = true;
      if (prevIdx < queue.value.length) {
        mediaItem.add(queue.value[prevIdx]);
      }
      _broadcastState();

      _skipDebounceTimer?.cancel();
      _skipDebounceTimer = Timer(const Duration(milliseconds: 200), () {
        skipToQueueItem(_currentIndex);
      });
    }
  }

  @override
  Future<void> stop() async {
    saveCurrentPlaybackSession(forceFlush: true);
    _playInterrupted = false;
    _skipDebounceTimer?.cancel();
    _cancelCrossfade();
    _cancelBackgroundCache();
    _loadedSongId = null;
    await _activePlayer.stop();
    await _nextPlayer.stop();
    _stopListeningTimer();
    final session = await AudioSession.instance;
    await session.setActive(false);
    _broadcastState();
    return super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    saveCurrentPlaybackSession(forceFlush: true);
    await stop();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < queue.value.length) {
      _skipDebounceTimer?.cancel();
      final currentRequestId = ++_loadRequestId;
      _isPreparing = true;
      _cancelCrossfade();
      _preloadedIndex = null;
      _activePlayer.setVolume(1.0);

      try {
        final item = queue.value[index];
        final isSameSong = _isSourceLoaded && _loadedSongId == item.id;

        _currentIndex = index;
        mediaItem.add(item);
        _broadcastState();

        if (isSameSong) {
          try {
            await _activePlayer.seek(Duration.zero);
            if (currentRequestId != _loadRequestId) return;
            _activePlayer.play();
          } catch (e) {
            debugPrint("Erreur lors du replay du même morceau : $e");
            final source = _createSource(item);
            await _activePlayer.setAudioSource(source);
            if (currentRequestId != _loadRequestId) return;
            _loadedSongId = item.id;
            await _activePlayer.seek(Duration.zero);
            if (currentRequestId != _loadRequestId) return;
            _activePlayer.play();
          }
        } else {
          final source = _createSource(item);
          await _activePlayer.setAudioSource(source);
          if (currentRequestId != _loadRequestId) return;
          _loadedSongId = item.id;
          await _activePlayer.seek(Duration.zero);
          if (currentRequestId != _loadRequestId) return;
          _activePlayer.play();
        }
      } catch (e) {
        debugPrint("Erreur skipToQueueItem : $e");
      } finally {
        if (currentRequestId == _loadRequestId) {
          _isPreparing = false;
          _isSourceLoaded = true;
          saveCurrentPlaybackSession(forceFlush: true);
          _broadcastState();

          // Préchargement immédiat du prochain morceau 2 secondes après le changement
          Future.delayed(const Duration(seconds: 2), () {
            if (currentRequestId == _loadRequestId &&
                !_isCrossfading &&
                !_isPreparing &&
                playbackState.value.playing) {
              _checkNextPreload();
            }
          });
        }
      }
    }
  }
}
