// lib/config.dart

import 'package:flutter/foundation.dart';

class AppConfig extends ChangeNotifier {
  String _serverIp = "127.0.0.1";
  static const int serverPort = 9000;
  static const int op25ApiPort = 8080; // <-- New API Port

  String get serverIp => _serverIp;

  void updateServerIp(String newIp) {
    if (_serverIp != newIp) {
      _serverIp = newIp;
      notifyListeners();
    }
  }

  String get audioUrl => "http://$_serverIp:$serverPort/audio.wav";
  String get logStreamUrl => "http://$_serverIp:$serverPort/stream";
  String get op25ApiUrl => "http://$_serverIp:$op25ApiPort/"; // <-- New API URL
}