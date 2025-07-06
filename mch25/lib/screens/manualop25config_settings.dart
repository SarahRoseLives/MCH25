import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../service/op25_control_service.dart';

class ManualOP25ConfigSettingsScreen extends StatefulWidget {
  @override
  _ManualOP25ConfigSettingsScreenState createState() =>
      _ManualOP25ConfigSettingsScreenState();
}

class _ManualOP25ConfigSettingsScreenState
    extends State<ManualOP25ConfigSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;

  // Controllers for text fields
  final _systemNameController = TextEditingController();
  final _controlChannelsController = TextEditingController();
  final _deviceArgsController = TextEditingController();

  // SDR Options
  final List<String> _devices = ['rtl', 'rtl_tcp', 'hackrf'];
  final Map<String, List<int>> _sampleRates = {
    'rtl': [1400000, 2048000, 2880000],
    'rtl_tcp': [1400000, 2048000, 2880000],
    'hackrf': [8000000, 10000000, 20000000],
  };
  final Map<String, List<String>> _gains = {
    'rtl': ['47', 'auto', '0', '10', '20', '30', '40', '49.6'],
    'rtl_tcp': ['47', 'auto', '0', '10', '20', '30', '40', '49.6'],
    'hackrf': ['auto', '0', '8', '16', '24', '32', '40'],
  };

  // SDR Selection state
  String _selectedDevice = 'rtl';
  int? _selectedSampleRate;
  String? _selectedGain;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    // Dispose controllers to free up resources
    _systemNameController.dispose();
    _controlChannelsController.dispose();
    _deviceArgsController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() { _isLoading = true; });

    // Load saved SDR settings from SharedPreferences
    await _loadSdrSettings();

    // Fetch current trunk config from the server
    await _fetchTrunkConfig();

    setState(() { _isLoading = false; });
  }

  Future<void> _loadSdrSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedDevice = prefs.getString('op25_device') ?? 'rtl';
      if (!_devices.contains(_selectedDevice)) {
        _selectedDevice = 'rtl';
      }
      _selectedSampleRate = prefs.getInt('op25_samplerate') ?? _sampleRates[_selectedDevice]![0];
      _selectedGain = prefs.getString('op25_gain') ?? _gains[_selectedDevice]![0];
    });
  }

  Future<void> _fetchTrunkConfig() async {
    final controlService = Provider.of<Op25ControlService>(context, listen: false);
    final trunkConfig = await controlService.readTrunkConfig();

    if (mounted && trunkConfig != null) {
      setState(() {
        _systemNameController.text = trunkConfig['sysname'] ?? '';
        _controlChannelsController.text = trunkConfig['control_channel'] ?? '';
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load trunk config: ${controlService.error ?? "Unknown error"}'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _onDeviceChanged(String? device) {
    if (device != null && device != _selectedDevice) {
      setState(() {
        _selectedDevice = device;
        _selectedSampleRate = _sampleRates[device]![0];
        _selectedGain = _gains[device]![0];
      });
    }
  }

  void _saveAndStart() async {
    if (!_formKey.currentState!.validate()) {
      return; // Validation failed
    }
    _formKey.currentState!.save();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saving configuration...')),
    );

    // 1. Send the updated trunk configuration first
    final controlService = Provider.of<Op25ControlService>(context, listen: false);
    final trunkUpdated = await controlService.writeTrunkConfig(
      _systemNameController.text,
      _controlChannelsController.text,
    );

    if (!trunkUpdated) {
      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save trunk config: ${controlService.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return; // Stop if trunk config fails to save
    }

    // 2. Save SDR settings to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('op25_device', _selectedDevice);
    await prefs.setInt('op25_samplerate', _selectedSampleRate!);
    await prefs.setString('op25_gain', _selectedGain!);

    if(mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration saved. Starting OP25...')),
      );
    }

    // 3. Build flags and start OP25
    final flags = Op25ControlService.buildFlagsFromPrefs(prefs);
    if (flags != null) {
      final success = await controlService.startOp25WithFlags(flags);
      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('OP25 started successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to start OP25: ${controlService.error}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
       if (mounted) {
         ScaffoldMessenger.of(context).removeCurrentSnackBar();
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Could not build flags from settings.'), backgroundColor: Colors.red),
         );
       }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Manual OP25 Config'),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  // --- TRUNK CONFIGURATION ---
                  Text(
                    'P25 System',
                    style: TextStyle(color: Colors.cyanAccent, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildSectionLabel('System Name'),
                  TextFormField(
                    controller: _systemNameController,
                    decoration: _inputDecoration(hintText: 'e.g. My Public Safety System'),
                    style: const TextStyle(color: Colors.white),
                    validator: (val) => (val == null || val.isEmpty) ? 'System name cannot be empty' : null,
                  ),
                  const SizedBox(height: 18),
                  _buildSectionLabel('Control Channel Frequencies'),
                  TextFormField(
                    controller: _controlChannelsController,
                    decoration: _inputDecoration(hintText: 'Comma separated, e.g. 853.0125,852.2375'),
                    style: const TextStyle(color: Colors.white),
                     validator: (val) => (val == null || val.isEmpty) ? 'At least one control channel is required' : null,
                  ),
                  const Divider(color: Colors.white24, height: 48),

                  // --- SDR DEVICE CONFIGURATION ---
                  Text(
                    'SDR Device',
                    style: TextStyle(color: Colors.cyanAccent, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildSectionLabel('SDR Device Type'),
                  DropdownButtonFormField<String>(
                    value: _selectedDevice,
                    dropdownColor: Colors.grey[900],
                    decoration: _inputDecoration(),
                    items: _devices.map((device) => DropdownMenuItem(
                      value: device,
                      child: Text(device, style: const TextStyle(color: Colors.white)),
                    )).toList(),
                    onChanged: _onDeviceChanged,
                  ),
                  const SizedBox(height: 18),
                  _buildSectionLabel('Optional Device Arguments'),
                  TextFormField(
                    controller: _deviceArgsController,
                    decoration: _inputDecoration(hintText: 'e.g. rtl=0 or rtl_tcp=192.168.1.100'),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 18),
                  _buildSectionLabel('Sample Rate'),
                  DropdownButtonFormField<int>(
                    value: _selectedSampleRate,
                    dropdownColor: Colors.grey[900],
                    decoration: _inputDecoration(),
                    items: (_sampleRates[_selectedDevice] ?? []).map((rate) => DropdownMenuItem(
                      value: rate,
                      child: Text('${rate / 1000000} MSPS', style: const TextStyle(color: Colors.white)),
                    )).toList(),
                    onChanged: (val) => setState(() => _selectedSampleRate = val),
                    validator: (val) => val == null ? 'Please select a sample rate' : null,
                  ),
                  const SizedBox(height: 18),
                  _buildSectionLabel('Gain'),
                  DropdownButtonFormField<String>(
                    value: _selectedGain,
                    dropdownColor: Colors.grey[900],
                    decoration: _inputDecoration(),
                    items: (_gains[_selectedDevice] ?? []).map((gain) => DropdownMenuItem(
                      value: gain,
                      child: Text(gain, style: const TextStyle(color: Colors.white)),
                    )).toList(),
                    onChanged: (val) => setState(() => _selectedGain = val),
                    validator: (val) => val == null ? 'Please select a gain' : null,
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('Save and Start OP25'),
                    onPressed: _saveAndStart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
      ),
    );
  }

  InputDecoration _inputDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: Colors.grey[850],
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.cyanAccent.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.cyanAccent, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
       errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    );
  }
}