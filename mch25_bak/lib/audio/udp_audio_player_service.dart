import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../config.dart';

class AudioStreamPlayerService {
  static final AudioStreamPlayerService _instance = AudioStreamPlayerService._internal();
  factory AudioStreamPlayerService() => _instance;
  AudioStreamPlayerService._internal();

  final _player = AudioPlayer();
  bool _playing = false;
  bool get isPlaying => _playing;
  StreamSubscription<PlayerState>? _playerSub;
  VoidCallback? _configListener;
  String? _lastIp;
  AppConfig? _appConfig; // <<<< Store AppConfig reference

  int _reconnectDelayMs = 1000;

  void start(AppConfig appConfig) {
    if (_playing) return;
    _playing = true;
    _appConfig = appConfig; // <<<< Store it
    _listenConfig(appConfig);
    _startAggressiveReconnect(appConfig);
  }

  void stop() {
    _playing = false;
    _playerSub?.cancel();
    _player.stop();
    if (_configListener != null && _appConfig != null) {
      _appConfig!.removeListener(_configListener!); // <<<< Use stored reference
      _configListener = null;
    }
  }

  void _listenConfig(AppConfig appConfig) {
    if (_configListener != null) return;
    _lastIp = appConfig.serverIp;
    _configListener = () {
      if (_lastIp != appConfig.serverIp) {
        _lastIp = appConfig.serverIp;
        if (_playing) {
          // Restart audio with new IP
          _startAggressiveReconnect(appConfig);
        }
      }
    };
    appConfig.addListener(_configListener!);
  }

  void _startAggressiveReconnect(AppConfig appConfig) async {
    _playerSub?.cancel();

    while (_playing) {
      try {
        await _player.setUrl(appConfig.audioUrl);
        await _player.play();
        _reconnectDelayMs = 1000;

        _playerSub?.cancel();
        _playerSub = _player.playerStateStream.listen((state) async {
          if (!_playing) return;
          if (state.processingState == ProcessingState.completed ||
              state.processingState == ProcessingState.idle ||
              (state.processingState == ProcessingState.ready && !_player.playing)) {
            await _forceReconnect(appConfig);
          }
        });

        await _player.playingStream.firstWhere((playing) => !playing && _playing);

        if (_playing) await _forceReconnect(appConfig);
      } catch (e) {
        debugPrint('Audio Player Error: $e');
        await Future.delayed(Duration(milliseconds: _reconnectDelayMs));
        _reconnectDelayMs = (_reconnectDelayMs * 2).clamp(1000, 8000);
      }
    }
  }

  Future<void> _forceReconnect(AppConfig appConfig) async {
    try {
      await _player.stop();
    } catch (_) {}
    if (_playing) {
      await Future.delayed(Duration(milliseconds: 250));
      await _player.setUrl(appConfig.audioUrl);
      await _player.play();
    }
  }
}