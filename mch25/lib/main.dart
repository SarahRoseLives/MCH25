import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import 'config.dart';
import 'service/mdns_scanner_service.dart';
import 'screens/radio_scanner_screen.dart';
import 'wizard/onboarding_wizard.dart';
import 'audio/udp_audio_player_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final appConfig = AppConfig();
  final mDNScanner = mDNScannerService();
  final audioService = AudioStreamPlayerService();

  // Start discovery
  mDNScanner.startDiscovery(appConfig);

  // Set up periodic rediscovery
  Timer.periodic(Duration(seconds: 30), (_) {
    mDNScanner.restartDiscovery(appConfig);
  });

  // Start audio service immediately so it listens for IP changes
  audioService.start(appConfig);

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appConfig),
          ChangeNotifierProvider.value(value: mDNScanner),
          Provider.value(value: audioService),
        ],
        child: MobileRadioScannerApp(),
      ),
    );
  });
}

class MobileRadioScannerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Control Head 25',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Color(0xFF181818),
        textTheme: ThemeData.dark().textTheme.copyWith(
          bodyLarge: TextStyle(fontFamily: 'Segment7'),
          bodyMedium: TextStyle(fontFamily: 'Segment7'),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _showWizard = false;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showWizard = !(prefs.getBool('wizardCompleted') ?? false);
      _prefsLoaded = true;
    });
  }

  void _completeWizard() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wizardCompleted', true);
    setState(() {
      _showWizard = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefsLoaded) {
      return MaterialApp(home: Container(color: Colors.black));
    }
    return _showWizard
        ? OnboardingWizard(onSkip: _completeWizard, onDone: _completeWizard)
        : RadioScannerScreen();
  }
}