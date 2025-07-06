import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

//region Data Models
// Main container for all data received from the API
class Op25Data {
  TrunkUpdate? trunkInfo;
  ChannelUpdate? channelInfo;
  List<CallLogEntry> callLog;

  Op25Data({this.trunkInfo, this.channelInfo, this.callLog = const []});
}

class TrunkUpdate {
  final String nac;
  final String systemName;
  final String systemType;
  final String wacn;
  final String sysid;
  final String rfid;
  final String stid;
  final Map<String, FrequencyInfo> frequencyData;
  final Map<String, dynamic> adjacentSites;
  final Map<String, dynamic> patches;

  TrunkUpdate({
    required this.nac,
    required this.systemName,
    required this.systemType,
    required this.wacn,
    required this.sysid,
    required this.rfid,
    required this.stid,
    required this.frequencyData,
    required this.adjacentSites,
    required this.patches,
  });

  factory TrunkUpdate.fromJson(String nac, Map<String, dynamic> json) {
    Map<String, FrequencyInfo> freqs = {};
    if (json['frequency_data'] is Map) {
      (json['frequency_data'] as Map).forEach((key, value) {
        freqs[key] = FrequencyInfo.fromJson(value);
      });
    }

    return TrunkUpdate(
      nac: nac,
      systemName: json['system'] ?? 'N/A',
      systemType: json['type'] ?? 'N/A',
      wacn: json['wacn']?.toString() ?? '-',
      sysid: json['sysid']?.toRadixString(16).toUpperCase() ?? '-',
      rfid: json['rfid']?.toString() ?? '-',
      stid: json['stid']?.toString() ?? '-',
      frequencyData: freqs,
      adjacentSites: json['adjacent_data'] ?? {},
      patches: json['patch_data'] ?? {},
    );
  }
}

class FrequencyInfo {
  final String type;
  final String lastActivity; // <-- CHANGED FROM int TO String
  final String mode;
  final int counter;
  final List<int?> tgids;
  final List<String?> tags;
  final List<int?> srcaddrs;
  final List<String?> srctags;

  FrequencyInfo({
    required this.type,
    required this.lastActivity,
    required this.mode,
    required this.counter,
    required this.tgids,
    required this.tags,
    required this.srcaddrs,
    required this.srctags,
  });

  factory FrequencyInfo.fromJson(Map<String, dynamic> json) {
    return FrequencyInfo(
      type: json['type'] ?? 'voice',
      lastActivity: json['last_activity']?.toString() ?? '0', // Ensure string conversion
      mode: json['mode']?.toString() ?? '-', // Ensure string conversion
      counter: json['counter'] ?? 0,
      tgids: List<int?>.from(json['tgids'] ?? []),
      tags: List<String?>.from(json['tags'] ?? []),
      srcaddrs: List<int?>.from(json['srcaddrs'] ?? []),
      srctags: List<String?>.from(json['srctags'] ?? []),
    );
  }
}

class ChannelUpdate {
  final List<String> channelIds;
  final Map<String, ChannelInfo> channels;

  ChannelUpdate({required this.channelIds, required this.channels});

  factory ChannelUpdate.fromJson(Map<String, dynamic> json) {
    Map<String, ChannelInfo> channelMap = {};
    List<String> idList = List<String>.from(json['channels']?.map((c) => c.toString()) ?? []);

    for (var id in idList) {
      if (json[id] is Map) {
        channelMap[id] = ChannelInfo.fromJson(json[id]);
      }
    }

    return ChannelUpdate(channelIds: idList, channels: channelMap);
  }
}

class ChannelInfo {
  final String name;
  final String system;
  final double freq;
  final int tgid;
  final String tag;
  final int srcaddr;
  final String srctag;
  final int encrypted;
  final int emergency;
  final String tdma;

  ChannelInfo({
    required this.name,
    required this.system,
    required this.freq,
    required this.tgid,
    required this.tag,
    required this.srcaddr,
    required this.srctag,
    required this.encrypted,
    required this.emergency,
    required this.tdma,
  });

  factory ChannelInfo.fromJson(Map<String, dynamic> json) {
    return ChannelInfo(
      name: json['name'] ?? '',
      system: json['system'] ?? 'N/A',
      freq: (json['freq'] ?? 0.0).toDouble(),
      tgid: json['tgid'] ?? 0,
      tag: json['tag'] ?? 'Talkgroup ${json['tgid'] ?? 0}',
      srcaddr: json['srcaddr'] ?? 0,
      srctag: json['srctag'] ?? 'ID: ${json['srcaddr'] ?? 0}',
      encrypted: json['encrypted'] ?? 0,
      emergency: json['emergency'] ?? 0,
      tdma: json['tdma']?.toString() ?? '-',
    );
  }
}

class CallLogEntry {
  final int time;
  final String sysid;
  final int tgid;
  final String tgtag;
  final int rid;
  final String rtag;
  final double freq;
  final int slot;

  CallLogEntry({
    required this.time,
    required this.sysid,
    required this.tgid,
    required this.tgtag,
    required this.rid,
    required this.rtag,
    required this.freq,
    required this.slot,
  });

  factory CallLogEntry.fromJson(Map<String, dynamic> json) {
    return CallLogEntry(
      time: json['time'] ?? 0,
      sysid: json['sysid']?.toRadixString(16).toUpperCase() ?? '-',
      tgid: json['tgid'] ?? 0,
      tgtag: json['tgtag'] ?? '',
      rid: json['rid'] ?? 0,
      rtag: json['rtag'] ?? '',
      freq: (json['freq'] ?? 0.0).toDouble(),
      slot: json['slot'] ?? 0,
    );
  }
}
//endregion

class Op25ApiService extends ChangeNotifier {
  AppConfig? _appConfig;
  Timer? _timer;
  final http.Client _client = http.Client();

  Op25Data? _data;
  Op25Data? get data => _data;

  String _error = '';
  String get error => _error;

  bool _isFetching = false;

  void start(AppConfig appConfig) {
    _appConfig = appConfig;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _fetchData());
    debugPrint("OP25 API Service Started");
  }

  void stop() {
    _timer?.cancel();
    debugPrint("OP25 API Service Stopped");
  }

  Future<void> _fetchData() async {
    if (_isFetching || _appConfig == null || _appConfig!.serverIp.isEmpty) return;
    _isFetching = true;

    final url = Uri.parse(_appConfig!.op25ApiUrl);
    final requestBody = json.encode([
      {"command": "update", "arg1": 0, "arg2": 0}
    ]);

    // This logging is very helpful, so we'll leave it for now.
    // debugPrint("OP25 API DEBUG: Fetching data from $url");

    try {
      final response = await _client.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: requestBody,
      ).timeout(const Duration(seconds: 2));

      // debugPrint("OP25 API DEBUG: Response Status: ${response.statusCode}");

      if (response.statusCode == 200) {
        if (response.body.isNotEmpty) {
            // debugPrint("OP25 API DEBUG: Response Body: ${response.body}");
            final List<dynamic> responseData = json.decode(response.body);
            _parseResponse(responseData);
            _error = '';
        } else {
             // debugPrint("OP25 API DEBUG: Received empty response body.");
            _error = "Received empty response from server.";
        }
      } else {
        _error = "Server Error: ${response.statusCode}";
        // debugPrint("OP25 API DEBUG: $_error");
      }
    } catch (e) {
      _error = "Connection Error: ${e.toString()}";
       // debugPrint("OP25 API DEBUG: $_error");
    }

    // Debug: print trunkInfo and frequencyData if present
    if (_data?.trunkInfo != null) {
      debugPrint('Trunk Info: ${_data!.trunkInfo!.toString()}');
      debugPrint('Frequency Data: ${_data!.trunkInfo!.frequencyData.toString()}');
    }

    _isFetching = false;
    notifyListeners();
  }

  void _parseResponse(List<dynamic> responseList) {
    _data ??= Op25Data();

    for (var item in responseList) {
      if (item is Map<String, dynamic> && item.containsKey('json_type')) {
        final String jsonType = item['json_type'];
        // debugPrint("OP25 API DEBUG: Parsing json_type: $jsonType");

        switch (jsonType) {
          case 'trunk_update':
            item.forEach((key, value) {
              if (key != 'json_type' && value is Map<String, dynamic>) {
                _data!.trunkInfo = TrunkUpdate.fromJson(key, value);
              }
            });
            break;
          case 'channel_update':
            _data!.channelInfo = ChannelUpdate.fromJson(item);
            break;
          case 'call_log':
            if (item['log'] is List) {
              _data!.callLog = (item['log'] as List)
                  .map((logItem) => CallLogEntry.fromJson(logItem))
                  .toList();
            }
            break;
        }
      }
    }
  }

  @override
  void dispose() {
    stop();
    _client.close();
    super.dispose();
  }
}