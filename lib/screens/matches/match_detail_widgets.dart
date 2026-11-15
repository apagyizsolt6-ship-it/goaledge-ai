import 'package:flutter/material.dart';
import '../../models/models.dart';

class PlayerLineupTile extends StatelessWidget {
  final JsonMap player;

  const PlayerLineupTile({required this.player});

  @override
  Widget build(BuildContext context) {
    final shirt = player['shirt'] ?? '-';
    final name = player['name'] ?? '';
    final pos = player['position'] ?? '';
    final isCap = player['is_captain'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text('$shirt', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$name${isCap ? " (C)" : ""}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(pos.toString(), style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }
}

class StatCompareRow extends StatelessWidget {
  final String label;
  final String homeVal;
  final String awayVal;

  const StatCompareRow({
    required this.label,
    required this.homeVal,
    required this.awayVal,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(homeVal, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(label, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
          Text(awayVal, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

