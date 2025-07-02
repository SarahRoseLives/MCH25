import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../service/mdns_scanner_service.dart';
import '../service/op25_api_service.dart';
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
      duration: const Duration(milliseconds: 300),
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
    // Use MediaQuery to get bottom padding for devices with gesture navigation
    final bottomPadding = MediaQuery.of(context).padding.bottom;
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
        color: const Color(0xFF202020),
        padding: EdgeInsets.only(
          top: 8,
          bottom: bottomPadding > 0 ? bottomPadding : 8,
        ),
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
        const SizedBox(height: 2),
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

    // Watch the API service for live data updates
    final apiService = context.watch<Op25ApiService>();
    final op25Data = apiService.data;

    // Safely extract data with fallbacks for when data is not yet available
    final channelInfo = op25Data?.channelInfo?.channels.values.firstOrNull;
    final trunkInfo = op25Data?.trunkInfo;

    // Use the frequency in Hz directly from the source for the key to avoid float errors
    final currentFreqHz = channelInfo?.freq ?? 0.0;
    // Calculate the MHz value for display purposes
    final currentFreq = currentFreqHz / 1000000;
    final talkgroup = channelInfo?.tag ?? 'Scanning...';

    final currentFreqKey = currentFreqHz.toInt().toString();
    final currentFreqData = trunkInfo?.frequencyData[currentFreqKey];

    final FrequencyInfo emptyFreqInfo = FrequencyInfo(
      type: '',
      lastActivity: '',
      mode: '',
      counter: 0,
      tgids: [],
      tags: [],
      srcaddrs: [],
      srctags: []
    );

    // Find the control channel entry, or use the lowest frequency as fallback
    MapEntry<String, FrequencyInfo>? controlChannelEntry;
    if (trunkInfo?.frequencyData != null && trunkInfo!.frequencyData.isNotEmpty) {
      var controlCandidates = trunkInfo!.frequencyData.entries
          .where((e) => e.value.type == 'control')
          .toList();
      if (controlCandidates.isNotEmpty) {
        controlChannelEntry = controlCandidates.first;
      } else {
        // fallback: lowest frequency
        controlChannelEntry = trunkInfo!.frequencyData.entries.reduce(
          (a, b) => int.parse(a.key) < int.parse(b.key) ? a : b,
        );
      }
    }
    final controlChannelFreq = controlChannelEntry?.key ?? '0.0';
    final controlChannelMhz = (double.tryParse(controlChannelFreq) ?? 0.0) / 1000000;
    final FrequencyInfo controlChannelData = controlChannelEntry?.value ?? emptyFreqInfo;

    // New fallback logic for mode and lastActivity
    final mode = currentFreqData?.mode?.isNotEmpty == true
        ? currentFreqData!.mode
        : (controlChannelData.mode?.isNotEmpty == true ? controlChannelData.mode : '-');

    final lastActivity = currentFreqData?.lastActivity?.isNotEmpty == true
        ? currentFreqData!.lastActivity.trim()
        : (controlChannelData.lastActivity?.isNotEmpty == true ? controlChannelData.lastActivity.trim() : '-');

    // Debug statements to help diagnose
    debugPrint('Trunk FreqData Keys: ${trunkInfo?.frequencyData.keys}');
    trunkInfo?.frequencyData.forEach((k, v) {
      debugPrint('Key: $k, type: ${v.type}, lastActivity: ${v.lastActivity}, mode: ${v.mode}');
    });
    debugPrint('CurrentFreqHz: $currentFreqHz, CurrentFreqKey: $currentFreqKey');
    debugPrint('ControlChannelFreq: $controlChannelFreq, ControlChannelMhz: $controlChannelMhz');

    double freqFontSize = size.width * 0.11;
    double ccFontSize = size.width * 0.04;
    double talkgroupFontSize = 28;
    if (size.height < 410) {
      freqFontSize = size.width * 0.09;
      ccFontSize = size.width * 0.032;
      talkgroupFontSize = 22;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top bar: Title, Status + Time
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.radar, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    "MCH-25 SCANNER",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  TimeDisplayLandscape(fontSize: 18),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 36, top: 2),
                child: Text(
                  _getStatusText(mDNSStatus, serverIp),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Flexible(
            fit: FlexFit.tight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool veryTight = constraints.maxHeight < 330;
                final double freqSz = veryTight ? freqFontSize * 0.85 : freqFontSize;
                final double ccSz = veryTight ? ccFontSize * 0.85 : ccFontSize;
                final double tgSz = veryTight ? talkgroupFontSize * 0.85 : talkgroupFontSize;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Main Frequency
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentFreq == 0.0 ? "0.000000" : currentFreq.toStringAsFixed(6),
                          style: TextStyle(
                            fontFamily: 'Segment7',
                            fontSize: freqSz,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Control Channel Frequency
                        Text(
                          "CC: ${controlChannelMhz.toStringAsFixed(6)}",
                          style: TextStyle(
                            fontFamily: 'Segment7',
                            fontSize: ccSz,
                            color: Colors.cyanAccent.withOpacity(0.8),
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    // Talkgroup
                    Text(
                      talkgroup,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: tgSz,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    // System and Status Details
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2.0),
                      child: Wrap(
                        spacing: 10.0,
                        runSpacing: 4.0,
                        children: [
                          _buildInfoChip("System", trunkInfo?.systemName ?? "-"),
                          _buildInfoChip("Type", trunkInfo?.systemType ?? "-"),
                          _buildInfoChip("SysID", trunkInfo?.sysid ?? "-"),
                          _buildInfoChip("WACN", trunkInfo?.wacn ?? "-"),
                          _buildInfoChip("Mode", mode),
                          _buildInfoChip("Last Seen", lastActivity),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "$label: ",
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
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
      await Future.delayed(const Duration(seconds: 1));
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