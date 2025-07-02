import 'package:flutter/material.dart';

class SiteDetailsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cell_tower, size: 60, color: Colors.white),
          SizedBox(height: 16),
          Text(
            "Site Details Screen (Placeholder)",
            style: TextStyle(color: Colors.white, fontSize: 24),
          ),
        ],
      ),
    );
  }
}