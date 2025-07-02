import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../service/mdns_scanner_service.dart';
import 'log_screen.dart';
import 'scan_grid_screen.dart';
import 'settings_screen.dart';
import 'site_details_screen.dart';

class RadioScannerScreen extends StatefulWidget {
  @override
  State<RadioScannerScreen> createState() => _RadioScannerScreenState();
}

class _RadioScannerScreenState extends State<RadioScannerScreen> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();

  static final List<Widget> _screens = [
    ScannerScreen(),
    ScanGridScreen(),
    SiteDetailsScreen(),
    LogScreen(),
    SettingsScreen(),
  ];

  static final List<_NavItemData> _navItems = [
    _NavItemData(icon: Icons.radio, label: "Scanner"),
    _NavItemData(icon: Icons.grid_view, label: "ScanGrid"),
    _NavItemData(icon: Icons.cell_tower, label: "Site Details"),
    _NavItemData(icon: Icons.list_alt, label: "Log"),
    _NavItemData(icon: Icons.settings, label: "Settings"),
  ];

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: Duration(milliseconds: 300),
      curve: Curves.ease,
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const BouncingScrollPhysics(),
          onPageChanged: _onPageChanged,
          children: _screens,
        ),
      ),
      bottomNavigationBar: Container(
        color: Color(0xFF202020),
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(_navItems.length, (index) {
            final item = _navItems[index];
            final selected = _selectedIndex == index;
            return GestureDetector(
              onTap: () => _onNavTap(index),
              child: _NavItem(
                icon: item.icon,
                label: item.label,
                selected: selected,
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final String label;
  const _NavItemData({required this.icon, required this.label});
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  const _NavItem(
      {required this.icon, required this.label, this.selected = false});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: selected ? Colors.white : Colors.white54, size: 28),
        SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white54,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}

// The main Scanner screen (your original layout)
class ScannerScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final mDNSStatus = context.watch<mDNScannerService>().status;
    final serverIp = context.watch<AppConfig>().serverIp;

    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top bar: Back + Title + Time
              Row(
                children: [
                  Icon(Icons.arrow_back_ios, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Text(
                    "MOBILE RADIO SCANNER",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.white,
                    ),
                  ),
                  Spacer(),
                  TimeDisplayLandscape(fontSize: 18),
                ],
              ),
              SizedBox(height: size.height * 0.04),
              // Main Frequency
              Text(
                "154.7850",
                style: TextStyle(
                  fontFamily: 'Segment7',
                  fontSize: size.width * 0.11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 8),
              // Location/Channel
              Text(
                "ASHTABULA",
                style: TextStyle(
                  fontFamily: 'Segment7',
                  fontSize: size.width * 0.06,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 8),
              // Status
              Text(
                "NO SIGNAL",
                style: TextStyle(
                  fontSize: size.width * 0.035,
                  fontWeight: FontWeight.w400,
                  color: Colors.white70,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
        // Volume slider and icon
        Positioned(
          top: size.height * 0.16,
          right: 40,
          child: Column(
            children: [
              RotatedBox(
                quarterTurns: 1,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    thumbColor: Colors.white,
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    trackHeight: 5,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
                  ),
                  child: SizedBox(
                    width: 110,
                    child: Slider(
                      value: 0.7,
                      onChanged: (_) {},
                    ),
                  ),
                ),
              ),
              SizedBox(height: 8),
              Icon(Icons.volume_up, color: Colors.white, size: 30),
            ],
          ),
        ),
        // Add a status indicator at the bottom
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              _getStatusText(mDNSStatus, serverIp),
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  String _getStatusText(ServerStatus status, String ip) {
    switch (status) {
      case ServerStatus.searching:
        return 'Searching for server...';
      case ServerStatus.found:
        return 'Connected to $ip';
      case ServerStatus.notFound:
        return 'Server not found. Retrying...';
      case ServerStatus.stopped:
        return 'Discovery stopped.';
    }
  }
}

class TimeDisplayLandscape extends StatefulWidget {
  final double fontSize;
  const TimeDisplayLandscape({Key? key, required this.fontSize})
      : super(key: key);

  @override
  State<TimeDisplayLandscape> createState() => _TimeDisplayLandscapeState();
}

class _TimeDisplayLandscapeState extends State<TimeDisplayLandscape> {
  late String _time;

  @override
  void initState() {
    super.initState();
    _updateTime();
    Future.doWhile(() async {
      await Future.delayed(Duration(seconds: 1));
      if (!mounted) return false;
      _updateTime();
      return true;
    });
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _time =
          "${(now.hour % 12 == 0 ? 12 : now.hour % 12).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour < 12 ? "AM" : "PM"}";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _time,
      style: TextStyle(
        fontSize: widget.fontSize,
        fontWeight: FontWeight.w400,
        color: Colors.white,
        letterSpacing: 1.2,
      ),
    );
  }
}