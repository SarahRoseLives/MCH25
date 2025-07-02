import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../config.dart';

class LogScreen extends StatefulWidget {
  @override
  _LogScreenState createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final List<String> _logLines = [];
  static const int _maxLines = 2000;
  StreamSubscription<String>? _streamSub;
  final ScrollController _scrollController = ScrollController();
  bool _atBottom = true;
  int _retryDelay = 1;
  bool _connected = false;
  http.Client? _client;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen for config changes and trigger a reconnect
    Provider.of<AppConfig>(context).addListener(_handleConfigChange);
    // Initial connection attempt
    _handleConfigChange();
  }

  void _handleConfigChange() {
    // Debounce reconnect attempts
    if (_isConnecting) return;
    _isConnecting = true;
    _connectToLogStream();
    Future.delayed(Duration(seconds: 1), () => _isConnecting = false);
  }

  @override
  void dispose() {
    Provider.of<AppConfig>(context, listen: false).removeListener(_handleConfigChange);
    _streamSub?.cancel();
    _client?.close();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_scrollController.hasClients) {
      _atBottom = _scrollController.offset >=
          _scrollController.position.maxScrollExtent - 30;
    }
  }

  TextStyle _getLogStyle(String log) {
    Color color;
    FontWeight fontWeight = FontWeight.normal;

    final lowerCaseLog = log.toLowerCase();

    if (lowerCaseLog.contains('error') ||
        lowerCaseLog.contains('errs 10') ||
        lowerCaseLog.contains('errs 15')) {
      color = Colors.redAccent;
      fontWeight = FontWeight.bold;
    } else if (lowerCaseLog.contains('timeout') ||
        lowerCaseLog.contains('err_rate') ||
        lowerCaseLog.contains('errs')) {
      color = Colors.orange;
    } else if (lowerCaseLog.contains('success') ||
        lowerCaseLog.contains('loaded') ||
        lowerCaseLog.contains('started')) {
      color = Colors.lightGreenAccent;
    } else if (lowerCaseLog.contains('freq') ||
        lowerCaseLog.contains('nac') ||
        lowerCaseLog.contains('tgid')) {
      color = Colors.cyan;
    } else if (lowerCaseLog.contains('[system]')) {
      color = Colors.blueGrey;
    } else if (lowerCaseLog.contains('http') ||
        lowerCaseLog.contains('audio.wav')) {
      color = Colors.purpleAccent;
    } else if (lowerCaseLog.contains('ambe') || lowerCaseLog.contains('imbe')) {
      color = const Color.fromARGB(255, 187, 187, 187);
    } else {
      color = Colors.white;
    }

    return TextStyle(
      color: color,
      fontFamily: 'monospace',
      fontSize: 12,
      fontWeight: fontWeight,
    );
  }

  void _connectToLogStream() async {
    // Close any existing connection before starting a new one
    _streamSub?.cancel();
    _client?.close();

    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final uri = Uri.parse(appConfig.logStreamUrl);
    _client = http.Client();

    try {
      final request = http.Request('GET', uri);
      final response = await _client!.send(request);

      if (mounted) {
        setState(() {
          _retryDelay = 1;
          _connected = true;
        });
      }

      _streamSub = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.startsWith('data: ')) {
            final logLine = line.substring(6);
            if (mounted) {
              setState(() {
                _logLines.add(logLine);
                if (_logLines.length > _maxLines) {
                  _logLines.removeRange(0, _logLines.length - _maxLines);
                }
              });

              if (_atBottom && _scrollController.hasClients) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollController
                      .jumpTo(_scrollController.position.maxScrollExtent);
                });
              }
            }
          }
        },
        onDone: () => _retryLogStream(aggressive: true),
        onError: (e) => _retryLogStream(aggressive: true),
      );
    } catch (e) {
      _retryLogStream(aggressive: true);
    }
  }

  void _retryLogStream({bool aggressive = false}) {
    _streamSub?.cancel();
    _client?.close();

    if (mounted) {
      setState(() {
        _connected = false;
      });
    }

    int delay = aggressive ? 1 : _retryDelay;
    Future.delayed(Duration(seconds: delay), () {
      if (mounted) {
        if (!aggressive) {
          setState(() {
            _retryDelay = (_retryDelay * 2).clamp(1, 5);
          });
        }
        _connectToLogStream();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            if (!_connected)
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.orange,
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      "Reconnecting in $_retryDelay seconds...",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _logLines.isEmpty
                  ? Center(
                      child: Text(
                        _connected ? "Waiting for logs..." : "Connecting...",
                        style:
                            const TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _logLines.length,
                      itemBuilder: (context, index) {
                        final log = _logLines[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Text(
                            log,
                            style: _getLogStyle(log),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}