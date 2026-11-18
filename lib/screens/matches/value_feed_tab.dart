import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../../services/poisson_engine.dart';
import '../../widgets/charts.dart';

class ValueFeedTab extends StatefulWidget {
  final MatchList matches;
  final String baseUrl;
  final String apiKey;
  final int dayOffset;
  final double bankroll;
  final String stakeProfile;
  final SlipItemList slipItems;
  final Set<String> favoriteLeagues;
  final void Function(String) onToggleFavoriteLeague;
  final void Function({required bool conservative}) onGenerateAiSlip;
  final void Function(int) onDayChanged;
  final Future<void> Function() onRefresh;
  final void Function(MatchPick) onSelectMatch;
  final void Function(String) onToggleWatch;
  final void Function(MatchPick) onToggleSlip;
  final void Function(MatchPick) onEditOdds;
  final void Function(MatchPick) onLogBet;

  const ValueFeedTab({
    super.key,
    required this.matches,
    required this.baseUrl,
    required this.apiKey,
    required this.dayOffset,
    required this.bankroll,
    required this.stakeProfile,
    required this.slipItems,
    required this.favoriteLeagues,
    required this.onToggleFavoriteLeague,
    required this.onGenerateAiSlip,
    required this.onDayChanged,
    required this.onRefresh,
    required this.onSelectMatch,
    required this.onToggleWatch,
    required this.onToggleSlip,
    required this.onEditOdds,
    required this.onLogBet,
  });

  @override
  State<ValueFeedTab> createState() => _ValueFeedTabState();
}

class _ValueFeedTabState extends State<ValueFeedTab> {
  String _selectedLeague = 'Összes';
  String _smartFilter = 'all';
  double _minEvThreshold = 0.0;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leagueSet = <String>{'Összes', ...widget.favoriteLeagues};
    for (final m in widget.matches) {
      leagueSet.add(m.league);
    }
    final leagues = leagueSet.toList();
    if (!leagues.contains(_selectedLeague)) {
      _selectedLeague = 'Összes';
    }

    final liveCount = widget.matches.where((m) => m.isLive).length;
    final pressureCount = widget.matches.where((m) => m.isHighPressure).length;
    final steamCount = widget.matches.where((m) => m.isSteamMove).length;

    final filtered = widget.matches.where((m) {
      if (_selectedLeague != 'Összes' && m.league != _selectedLeague) return false;
      if (_smartFilter == 'favorites' && !widget.favoriteLeagues.contains(m.league)) return false;
      if (_smartFilter == 'live' && !m.isLive) return false;
      if (_smartFilter == 'pressure' && !m.isHighPressure) return false;
      if (_smartFilter == 'steam' && !m.isSteamMove) return false;
      if (_smartFilter == 'standings' && !m.hasStandingData) return false;
      if (m.edgePercent < _minEvThreshold) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchText = '${m.homeTeam} ${m.awayTeam} ${m.league} ${m.market}'.toLowerCase();
        if (!matchText.contains(q)) return false;
      }
      return true;
    }).toList();

    final topVault = widget.matches.where((m) => !m.isFinished && m.edgePercent > 0).toList()
      ..sort((a, b) {
        final aScore = a.edgePercent + (widget.favoriteLeagues.contains(a.league) ? 1.5 : 0.0);
        final bScore = b.edgePercent + (widget.favoriteLeagues.contains(b.league) ? 1.5 : 0.0);
        return bScore.compareTo(aScore);
      });

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      color: const Color(0xFF10B981),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 84),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: -1, label: Text('Tegnap')),
              ButtonSegment(value: 0, label: Text('Ma')),
              ButtonSegment(value: 1, label: Text('Holnap')),
            ],
            selected: {widget.dayOffset},
            onSelectionChanged: (s) => widget.onDayChanged(s.first),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onGenerateAiSlip(conservative: true),
                  icon: const Icon(Icons.shield_outlined, size: 15, color: Color(0xFF10B981)),
                  label: const Text('AI Duplázó (~2.0x)', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1F2937)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onGenerateAiSlip(conservative: false),
                  icon: const Icon(Icons.bolt, size: 15, color: Color(0xFF3B82F6)),
                  label: const Text('AI Value Tripla', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1F2937)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Keresés csapatra, ligára vagy piacra...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF131A29),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF1F2937)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _SmartChip(
                  label: 'Mind (${widget.matches.length})',
                  selected: _smartFilter == 'all',
                  onTap: () => setState(() => _smartFilter = 'all'),
                ),
                const SizedBox(width: 6),
                _SmartChip(
                  label: '★ Kedvenc ligák',
                  selected: _smartFilter == 'favorites',
                  color: const Color(0xFFF59E0B),
                  onTap: () => setState(() => _smartFilter = 'favorites'),
                ),
                const SizedBox(width: 6),
                _SmartChip(
                  label: '🔴 Élő ($liveCount)',
                  selected: _smartFilter == 'live',
                  color: const Color(0xFFEF4444),
                  onTap: () => setState(() => _smartFilter = 'live'),
                ),
                const SizedBox(width: 6),
                _SmartChip(
                  label: '🔥 Gólnyomás ($pressureCount)',
                  selected: _smartFilter == 'pressure',
                  color: const Color(0xFFF59E0B),
                  onTap: () => setState(() => _smartFilter = 'pressure'),
                ),
                const SizedBox(width: 6),
                _SmartChip(
                  label: '📉 Steam Move ($steamCount)',
                  selected: _smartFilter == 'steam',
                  color: const Color(0xFF3B82F6),
                  onTap: () => setState(() => _smartFilter = 'steam'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Állítható Min. EV% küszöb szűrő
          Row(
            children: [
              const Text('Min. EV:', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              const SizedBox(width: 8),
              ...[0.0, 2.0, 5.0, 8.0].map((thr) {
                final sel = _minEvThreshold == thr;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(thr == 0.0 ? 'Mind' : '+${thr.toInt()}%',
                        style: const TextStyle(fontSize: 10)),
                    selected: sel,
                    selectedColor: const Color(0xFF10B981),
                    onSelected: (_) => setState(() => _minEvThreshold = thr),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 8),
          if (topVault.isNotEmpty && _searchQuery.isEmpty && _smartFilter == 'all' && _minEvThreshold == 0.0) ...[
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF10B981)),
                const SizedBox(width: 6),
                const Text(
                  'Napi 3 tipp',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                ),
                const Spacer(),
                Text(
                  'Ma · Top edge',
                  style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...List.generate(topVault.take(3).length, (idx) {
              final top = topVault[idx];
              final edge = top.edgePercent;
              final stake = top.recommendedStake(widget.bankroll, widget.stakeProfile);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: const Color(0xFF131A29),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => widget.onSelectMatch(top),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color.fromRGBO(16, 185, 129, 0.35)),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF0F241F), Color(0xFF131A29)],
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(16, 185, 129, 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${idx + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF10B981),
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${top.homeTeam} – ${top.awayTeam}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  top.market,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFFD1D5DB)),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${top.league} · @ ${top.marketOdds} · ${stake} Ft',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(16, 185, 129, 0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '+${edge.toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                    color: Color(0xFF10B981),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                const Text(
                                  'EV',
                                  style: TextStyle(fontSize: 10, color: Color(0xFF6EE7B7)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            const Padding(
              padding: EdgeInsets.only(bottom: 6, top: 2),
              child: Text(
                'Összes meccs',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF)),
              ),
            ),
          ],
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: leagues.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final league = leagues[index];
                final isSelected = league == _selectedLeague;
                final isFav = widget.favoriteLeagues.contains(league);
                return GestureDetector(
                  onLongPress: () => widget.onToggleFavoriteLeague(league),
                  child: FilterChip(
                    label: Text(
                      league == 'Összes' ? league : '${isFav ? "★ " : ""}$league',
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? Colors.black : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: const Color(0xFF10B981),
                    backgroundColor: const Color(0xFF131A29),
                    onSelected: (_) => setState(() => _selectedLeague = league),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          if (widget.matches.isEmpty) ...[
            const SizedBox(height: 8),
            ...List.generate(4, (i) => const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: const _MatchCardSkeleton(),
                )),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 8, 8, 24),
              child: Text(
                'Meccsek betöltése… Húzd le a frissítéshez, vagy állítsd be az API kulcsot a Beállításokban.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              ),
            ),
          ] else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(Icons.filter_alt_off, size: 40, color: Color(0xFF374151)),
                  SizedBox(height: 12),
                  Text(
                    'Nincs a szűrőnek megfelelő mérkőzés',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFD1D5DB)),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Állítsd „Mind”-re az EV küszöböt, vagy válassz másik napot / ligát.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            )
          else
            ...filtered.map(
              (match) {
                final inSlip = widget.slipItems.any((s) => s.matchId == match.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: MatchValueCard(
                    match: match,
                    baseUrl: widget.baseUrl,
                    apiKey: widget.apiKey,
                    bankroll: widget.bankroll,
                    stakeProfile: widget.stakeProfile,
                    isInSlip: inSlip,
                    isFavLeague: widget.favoriteLeagues.contains(match.league),
                    onToggleFavLeague: () => widget.onToggleFavoriteLeague(match.league),
                    onTap: () => widget.onSelectMatch(match),
                    onToggleWatch: () => widget.onToggleWatch(match.id),
                    onToggleSlip: () => widget.onToggleSlip(match),
                    onEditOdds: () => widget.onEditOdds(match),
                    onLogBet: () => widget.onLogBet(match),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SmartChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _SmartChip({
    required this.label,
    required this.selected,
    this.color = const Color(0xFF10B981),
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : const Color(0xFF131A29),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : const Color(0xFF1F2937)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.black : const Color(0xFFD1D5DB),
          ),
        ),
      ),
    );
  }
}


class _MatchCardSkeleton extends StatelessWidget {
  const _MatchCardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar({double? width, required double height}) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131A29),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              bar(width: 90, height: 10),
              const Spacer(),
              bar(width: 48, height: 18),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              bar(width: 28, height: 28),
              const SizedBox(width: 8),
              Expanded(child: bar(height: 14)),
              const SizedBox(width: 8),
              bar(width: 40, height: 20),
              const SizedBox(width: 8),
              Expanded(child: bar(height: 14)),
              const SizedBox(width: 8),
              bar(width: 28, height: 28),
            ],
          ),
          const SizedBox(height: 14),
          bar(height: 44),
        ],
      ),
    );
  }
}

class MatchValueCard extends StatelessWidget {
  final MatchPick match;
  final String baseUrl;
  final String apiKey;
  final double bankroll;
  final String stakeProfile;
  final bool isInSlip;
  final bool isFavLeague;
  final VoidCallback onToggleFavLeague;
  final VoidCallback onTap;
  final VoidCallback onToggleWatch;
  final VoidCallback onToggleSlip;
  final VoidCallback onEditOdds;
  final VoidCallback onLogBet;

  const MatchValueCard({
    super.key,
    required this.match,
    required this.baseUrl,
    required this.apiKey,
    required this.bankroll,
    required this.stakeProfile,
    required this.isInSlip,
    required this.isFavLeague,
    required this.onToggleFavLeague,
    required this.onTap,
    required this.onToggleWatch,
    required this.onToggleSlip,
    required this.onEditOdds,
    required this.onLogBet,
  });

  Color _edgeColor(double edge) {
    if (edge >= 8) return const Color(0xFF10B981);
    if (edge >= 3) return const Color(0xFF34D399);
    if (edge > 0) return const Color(0xFF6EE7B7);
    return const Color(0xFF6B7280);
  }

  @override
  Widget build(BuildContext context) {
    final edge = match.edgePercent;
    final recStake = match.recommendedStake(bankroll, stakeProfile);
    final dropPct = match.oddsDropPercent;
    final edgeColor = _edgeColor(edge);
    final hasScore = match.homeScore != null && match.awayScore != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // —— 1. Meta row: liga · idő | LIVE | edge ——
              Row(
                children: [
                  GestureDetector(
                    onTap: onToggleFavLeague,
                    child: Icon(
                      isFavLeague ? Icons.star : Icons.star_border,
                      size: 15,
                      color: isFavLeague ? const Color(0xFFF59E0B) : const Color(0xFF4B5563),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (match.isLive)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'ÉLŐ ${match.minute ?? ""}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      '${match.league} · ${match.kickoff}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: edgeColor.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      edge >= 0 ? '+${edge.toStringAsFixed(1)}%' : '${edge.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: edgeColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onToggleWatch,
                    child: Icon(
                      match.isWatched ? Icons.bookmark : Icons.bookmark_border,
                      size: 18,
                      color: match.isWatched ? const Color(0xFFF59E0B) : const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // —— 2. Teams + score (hero) ——
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        TeamLogoBadge(
                          teamId: match.homeId,
                          teamName: match.homeTeam,
                          baseUrl: baseUrl,
                          apiKey: apiKey,
                          size: 26,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            match.homeTeam,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0E17),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: match.isLive
                            ? const Color.fromRGBO(239, 68, 68, 0.5)
                            : const Color(0xFF1F2937),
                      ),
                    ),
                    child: Text(
                      hasScore ? '${match.homeScore} – ${match.awayScore}' : 'vs',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: hasScore ? 15 : 12,
                        color: hasScore ? Colors.white : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            match.awayTeam,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TeamLogoBadge(
                          teamId: match.awayId,
                          teamName: match.awayTeam,
                          baseUrl: baseUrl,
                          apiKey: apiKey,
                          size: 26,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (match.isHighPressure || match.isSteamMove) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    if (match.isHighPressure)
                      _miniTag('🔥 Nyomás', const Color(0xFFF59E0B)),
                    if (match.isSteamMove)
                      _miniTag('Steam −${dropPct.toStringAsFixed(0)}%', const Color(0xFF60A5FA)),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              // —— 3. Market row (primary tip) ——
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0E17),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1F2937)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PIAC',
                            style: TextStyle(fontSize: 9, color: Color(0xFF6B7280), letterSpacing: 0.6),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            match.market,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'ODDS',
                          style: TextStyle(fontSize: 9, color: Color(0xFF6B7280), letterSpacing: 0.6),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          match.marketOdds.toStringAsFixed(2),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFE5E7EB),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'TÉT',
                          style: TextStyle(fontSize: 9, color: Color(0xFF6B7280), letterSpacing: 0.6),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$recStake Ft',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // —— 4. Actions ——
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onToggleSlip,
                      icon: Icon(isInSlip ? Icons.check : Icons.add, size: 16),
                      label: Text(isInSlip ? 'Szelvényben' : 'Szelvény', style: const TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isInSlip ? const Color(0xFF10B981) : const Color(0xFFD1D5DB),
                        side: BorderSide(color: isInSlip ? const Color(0xFF10B981) : const Color(0xFF374151)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onLogBet,
                      icon: const Icon(Icons.edit_note, size: 16),
                      label: const Text('Napló', style: TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onEditOdds,
                    tooltip: 'Odds szerkesztése',
                    icon: const Icon(Icons.tune, size: 18, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _miniTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
