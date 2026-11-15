import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../../services/poisson_engine.dart';
import '../../widgets/charts.dart';

class TrendRadarTab extends StatefulWidget {
  final MatchList matches;
  final String baseUrl;
  final String apiKey;
  final void Function(MatchPick) onSelectMatch;

  const TrendRadarTab({
    super.key,
    required this.matches,
    required this.baseUrl,
    required this.apiKey,
    required this.onSelectMatch,
  });

  @override
  State<TrendRadarTab> createState() => _TrendRadarTabState();
}

class _TrendRadarTabState extends State<TrendRadarTab> {
  String _selectedCategory = 'Összes';

  @override
  Widget build(BuildContext context) {
    final categories = ['Összes', 'Gólok / BTTS', 'Tabella & Forma', 'xG eltérés'];
    final list = _selectedCategory == 'Összes'
        ? widget.matches
        : widget.matches.where((m) => m.trendCategory == _selectedCategory).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Statisztikai Trend Radar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: categories.map((cat) {
              final selected = cat == _selectedCategory;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: selected,
                  selectedColor: const Color(0xFF3B82F6),
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        ...list.map((m) {
          final hitCount = m.last6Trend.where((e) => e).length;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              onTap: () => widget.onSelectMatch(m),
              contentPadding: const EdgeInsets.all(14),
              leading: TeamLogoBadge(
                teamId: m.homeId,
                teamName: m.homeTeam,
                baseUrl: widget.baseUrl,
                apiKey: widget.apiKey,
                size: 32,
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('${m.homeTeam} – ${m.awayTeam}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  Text('$hitCount / 6 találat',
                      style: const TextStyle(
                          color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(m.trendSummary, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 10),
                  Row(
                    children: m.last6Trend.map((hit) {
                      return Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: hit
                              ? const Color.fromRGBO(16, 185, 129, 0.2)
                              : const Color.fromRGBO(239, 68, 68, 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: hit ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                        ),
                        child: Icon(
                          hit ? Icons.check : Icons.close,
                          size: 14,
                          color: hit ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
