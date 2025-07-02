import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../service/op25_api_service.dart';
import 'package:intl/intl.dart';

class SiteDetailsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final apiService = context.watch<Op25ApiService>();
    final op25Data = apiService.data;
    final error = apiService.error;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: (op25Data == null && error.isEmpty)
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      "Waiting for data...",
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              )
            : (error.isNotEmpty && op25Data == null)
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            "API Error",
                            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            error,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (op25Data?.trunkInfo != null)
                          _buildTrunkInfoCard(op25Data!.trunkInfo!),
                        const SizedBox(height: 16),
                        if (op25Data?.channelInfo?.channels.isNotEmpty ?? false)
                          _buildChannelInfoCard(op25Data!.channelInfo!),
                        const SizedBox(height: 16),
                        if (op25Data?.trunkInfo?.frequencyData.isNotEmpty ?? false)
                          _buildFrequenciesCard(op25Data!.trunkInfo!),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildTrunkInfoCard(TrunkUpdate info) {
    return _InfoCard(
      title: "System Details: ${info.systemName}",
      icon: Icons.cell_tower,
      children: [
        _buildDetailRow("Type", info.systemType),
        _buildDetailRow("NAC", info.nac),
        _buildDetailRow("System ID", info.sysid),
        _buildDetailRow("WACN", info.wacn),
        _buildDetailRow("RFSS", info.rfid),
        _buildDetailRow("Site ID", info.stid),
      ],
    );
  }

  Widget _buildChannelInfoCard(ChannelUpdate info) {
    // For now, just show the first active channel's details
    final firstChannel = info.channels.values.first;
    return _InfoCard(
      title: "Channel: ${firstChannel.name}",
      icon: Icons.volume_up,
      children: [
        _buildDetailRow("Frequency", "${(firstChannel.freq / 1000000).toStringAsFixed(6)} MHz"),
        _buildDetailRow("Talkgroup", "${firstChannel.tag} (${firstChannel.tgid})"),
        _buildDetailRow("Source", "${firstChannel.srctag} (${firstChannel.srcaddr})"),
        _buildDetailRow("Mode", firstChannel.tdma),
        _buildDetailRow(
          "Status",
          firstChannel.emergency == 1
              ? "EMERGENCY"
              : (firstChannel.encrypted == 1 ? "Encrypted" : "Clear"),
          color: firstChannel.emergency == 1
              ? Colors.redAccent
              : (firstChannel.encrypted == 1 ? Colors.orangeAccent : Colors.greenAccent),
        ),
      ],
    );
  }

  Widget _buildFrequenciesCard(TrunkUpdate info) {
    return _InfoCard(
      title: "Frequency List",
      icon: Icons.bar_chart,
      children: [
        Table(
          border: TableBorder(horizontalInside: BorderSide(color: Colors.white24, width: 0.5)),
          columnWidths: const {
            0: FlexColumnWidth(3),
            1: FlexColumnWidth(3),
            2: FlexColumnWidth(2),
            3: IntrinsicColumnWidth(),
          },
          children: [
            const TableRow(
              children: [
                _HeaderCell('Frequency'),
                _HeaderCell('Active Talkgroup'),
                _HeaderCell('Last Seen'),
                _HeaderCell('Count'),
              ],
            ),
            ...info.frequencyData.entries.map((entry) {
              final freq = (double.tryParse(entry.key) ?? 0.0) / 1000000;
              final data = entry.value;
              final tgid = data.tags.isNotEmpty
                  ? data.tags[0]
                  : (data.tgids.isNotEmpty ? data.tgids[0].toString() : "-");
              final int lastActivityInt = _toInt(data.lastActivity);
              return TableRow(
                children: [
                  _DataCell(freq.toStringAsFixed(6), isMono: true),
                  _DataCell(tgid ?? '-'),
                  _DataCell(DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(lastActivityInt * 1000))),
                  _DataCell(NumberFormat.compact().format(data.counter), alignment: TextAlign.right),
                ],
              );
            }),
          ],
        )
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 16)),
          Text(value, style: TextStyle(color: color ?? Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

// Helper widgets for styling cards and tables
class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _InfoCard({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.cyanAccent, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 24),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(text, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  final bool isMono;
  final TextAlign alignment;
  const _DataCell(this.text, {this.isMono = false, this.alignment = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        text,
        textAlign: alignment,
        style: TextStyle(
          color: Colors.white,
          fontFamily: isMono ? 'monospace' : null,
        ),
      ),
    );
  }
}