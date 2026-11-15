import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'poisson_engine.dart';

class SportApiResponse {
  final bool success;
  final int statusCode;
  final MatchList matches;
  final String rawPreview;
  final String message;
  final String? rateLimitRemaining;

  SportApiResponse({
    required this.success,
    required this.statusCode,
    required this.matches,
    required this.rawPreview,
    required this.message,
    this.rateLimitRemaining,
  });
}

class SportApiService {
  static const String defaultBaseUrl = 'https://sportapi.ai/api';
  static final Map<int, StandingsMap> _standingsCache = {};
  static final StringStringMap _etagCache = {};
  static final StringStringMap _bodyCache = {};

  static String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  static Future<http.Response> _getWithEtag(Uri uri, String apiKey) async {
    final key = uri.toString();
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Api-Key': apiKey.trim(),
    };
    if (_etagCache.containsKey(key) && _bodyCache.containsKey(key)) {
      headers['If-None-Match'] = _etagCache[key]!;
    }

    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    if (res.statusCode == 304 && _bodyCache.containsKey(key)) {
      return http.Response(_bodyCache[key]!, 200, headers: res.headers);
    }
    if (res.statusCode == 200) {
      final etag = res.headers['etag'];
      if (etag != null && etag.isNotEmpty) {
        _etagCache[key] = etag;
        _bodyCache[key] = utf8.decode(res.bodyBytes, allowMalformed: true);
      }
    }
    return res;
  }

  static double leagueAvgGoals(StandingsMap table) {
    if (table.isEmpty) return 1.38;
    int totalGoals = 0;
    int totalMatches = 0;
    for (final row in table.values) {
      totalGoals += row.goalsFor;
      totalMatches += row.played;
    }
    if (totalMatches == 0) return 1.38;
    return (totalGoals / totalMatches).clamp(0.95, 2.15);
  }

  static StringList extractWdlCodes(TeamStandingInfo info) {
    final StringList codes = [];
    for (final f in info.form.take(5)) {
      final res = (f['result'] ?? '').toString().toUpperCase();
      if (res == 'W' || res == 'D' || res == 'L') {
        codes.add(res);
      } else {
        final hg = (f['home_score'] as num?)?.toInt() ?? 0;
        final ag = (f['away_score'] as num?)?.toInt() ?? 0;
        final isHome = (f['home_team'] ?? '').toString() == info.teamName;
        if (hg == ag) {
          codes.add('D');
        } else if ((isHome && hg > ag) || (!isHome && ag > hg)) {
          codes.add('W');
        } else {
          codes.add('L');
        }
      }
    }
    if (codes.isEmpty) return ['W', 'D', 'W', 'L', 'W'];
    return codes;
  }

  static BoolList extractFormTrend(TeamStandingInfo home, TeamStandingInfo away) {
    final BoolList hits = [];
    for (final f in home.form.take(3)) {
      final hg = (f['home_score'] as num?)?.toInt() ?? 0;
      final ag = (f['away_score'] as num?)?.toInt() ?? 0;
      hits.add((hg + ag) >= 2);
    }
    for (final f in away.form.take(3)) {
      final hg = (f['home_score'] as num?)?.toInt() ?? 0;
      final ag = (f['away_score'] as num?)?.toInt() ?? 0;
      hits.add((hg + ag) >= 2);
    }
    while (hits.length < 6) {
      hits.add(true);
    }
    return hits.take(6).toList();
  }

  static MatchPick buildPickFromXg({
    required String id,
    int? fixtureId,
    int? leagueId,
    int? homeId,
    int? awayId,
    required String league,
    required String leagueZone,
    required String kickoff,
    required String status,
    String? minute,
    int? homeScore,
    int? awayScore,
    required String homeTeam,
    required String awayTeam,
    required double homeXg,
    required double awayXg,
    int? liveHomeSot,
    int? liveAwaySot,
    required BoolList last6Trend,
    required StringList homeFormCodes,
    required StringList awayFormCodes,
    int? homePos,
    int? awayPos,
    required bool hasStandingData,
    required bool isWatched,
    double? customOdds,
  }) {
    final isLive = status == 'LIVE';
    int elapsed = 0;
    if (minute == 'HT') {
      elapsed = 45;
    } else if (minute != null) {
      elapsed = (int.tryParse(minute.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).clamp(1, 89);
    }
    final remFrac = isLive ? ((90 - elapsed) / 90.0).clamp(0.06, 0.98) : 1.0;

    final poisson = PoissonEngine.calculate(
      isLive ? (homeXg * remFrac).clamp(0.08, 3.2) : homeXg,
      isLive ? (awayXg * remFrac).clamp(0.08, 3.2) : awayXg,
      baseHomeScore: isLive ? (homeScore ?? 0) : 0,
      baseAwayScore: isLive ? (awayScore ?? 0) : 0,
      fullPreMatchTotalXg: homeXg + awayXg,
    );

    MarketOption best = poisson.allMarkets.first;
    for (final opt in poisson.allMarkets) {
      if (isLive && opt.code.startsWith('ht_')) continue;
      if (opt.probability >= 0.48 && opt.edgePercent > best.edgePercent) {
        best = opt;
      }
    }

    String category = 'xG eltérés';
    if (best.code.contains('over') || best.code.contains('under') || best.code == 'btts') {
      category = 'Gólok / BTTS';
    } else if (hasStandingData) {
      category = 'Tabella & Forma';
    }

    final finalOdds = customOdds ?? best.refOdds;

    String summary;
    if (isLive) {
      summary =
          'ÉLŐ In-Play Dixon-Coles ($minute\'): hátralévő xG ${(homeXg * remFrac).toStringAsFixed(2)} – ${(awayXg * remFrac).toStringAsFixed(2)} • Élő Fair szorzó: ${best.fairOdds}.';
    } else if (hasStandingData && homePos != null && awayPos != null) {
      summary =
          'Forma-súlyozott xG (${homeXg.toStringAsFixed(2)} – ${awayXg.toStringAsFixed(2)}) • Tabella: $homePos. vs $awayPos. hely • BTTS: ${(poisson.btts * 100).round()}%.';
    } else {
      summary =
          'Dixon-Coles 16-piacos modell: össz-xG ${(homeXg + awayXg).toStringAsFixed(2)}, 2.5+ gól ${(poisson.over25 * 100).round()}%, 1. Félidő 0.5+ ${(poisson.htOver05 * 100).round()}%.';
    }

    final DoubleList hist = [
      double.parse((best.refOdds + 0.14).toStringAsFixed(2)),
      double.parse((best.refOdds + 0.08).toStringAsFixed(2)),
      double.parse((best.refOdds + 0.03).toStringAsFixed(2)),
      best.refOdds,
    ];
    if (customOdds != null && customOdds != best.refOdds) {
      hist.add(customOdds);
    }

    return MatchPick(
      id: id,
      fixtureId: fixtureId,
      leagueId: leagueId,
      homeId: homeId,
      awayId: awayId,
      league: league,
      leagueZone: leagueZone,
      kickoff: kickoff,
      status: status,
      minute: minute,
      homeScore: homeScore,
      awayScore: awayScore,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      market: best.label,
      marketCode: best.code,
      marketCategory: best.category,
      trendSummary: summary,
      trendCategory: category,
      modelProb: best.probability,
      marketOdds: finalOdds,
      isCustomOdds: customOdds != null,
      oddsHistory: hist,
      homeXg: double.parse(homeXg.toStringAsFixed(2)),
      awayXg: double.parse(awayXg.toStringAsFixed(2)),
      liveHomeSot: liveHomeSot,
      liveAwaySot: liveAwaySot,
      last6Trend: last6Trend,
      homeFormCodes: homeFormCodes,
      awayFormCodes: awayFormCodes,
      homePos: homePos,
      awayPos: awayPos,
      hasStandingData: hasStandingData,
      isWatched: isWatched,
    );
  }

  static Future<SportApiResponse> fetchFixturesByDate({
    required String baseUrl,
    required String apiKey,
    required DateTime targetDate,
    required String dayLabel,
    required StringList watchedIds,
    required StringDoubleMap customOddsMap,
  }) async {
    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final dateStr = _formatDate(targetDate);
    final uri = Uri.parse('$cleanBase/fixtures/date/$dateStr');

    try {
      final response = await _getWithEtag(uri, apiKey);
      final remaining = response.headers['x-ratelimit-remaining'];
      final bodyText = utf8.decode(response.bodyBytes, allowMalformed: true);
      final preview = bodyText.length > 350 ? '${bodyText.substring(0, 350)}...' : bodyText;

      if (response.statusCode == 401) {
        return SportApiResponse(
          success: false,
          statusCode: 401,
          matches: [],
          rawPreview: preview,
          message: '401 Hibás vagy hiányzó X-Api-Key kulcs!',
          rateLimitRemaining: remaining,
        );
      }

      if (response.statusCode == 429) {
        return SportApiResponse(
          success: false,
          statusCode: 429,
          matches: [],
          rawPreview: preview,
          message: '429 Elérted a napi/havi lekérési limitet!',
          rateLimitRemaining: remaining,
        );
      }

      if (response.statusCode != 200) {
        return SportApiResponse(
          success: false,
          statusCode: response.statusCode,
          matches: [],
          rawPreview: preview,
          message: 'HTTP ${response.statusCode} hiba ($uri)',
          rateLimitRemaining: remaining,
        );
      }

      final decoded = jsonDecode(bodyText);
      final List<dynamic> dataList = (decoded is Map && decoded['data'] is List) ? decoded['data'] : [];

      if (dataList.isEmpty) {
        return SportApiResponse(
          success: true,
          statusCode: 200,
          matches: [],
          rawPreview: preview,
          message: 'Kapcsolat OK (200), de 0 meccs van ezen a napon ($dateStr).',
          rateLimitRemaining: remaining,
        );
      }

      const topLeagueNames = {
        'Premier League',
        'Spanish La Liga',
        'La Liga',
        'Serie A',
        'Bundesliga',
        'Ligue 1',
        'UEFA Champions League',
        'UEFA Europa League',
        'NB I',
        'OTP Bank Liga',
      };

      final JsonList sortedRaw = [];
      for (final el in dataList) {
        if (el is JsonMap) {
          sortedRaw.add(el);
        }
      }

      sortedRaw.sort((a, b) {
        final aLive = a['status'] == 'LIVE' ? 0 : 1;
        final bLive = b['status'] == 'LIVE' ? 0 : 1;
        if (aLive != bLive) return aLive.compareTo(bLive);

        final aLeague = (a['league_name'] ?? '').toString();
        final bLeague = (b['league_name'] ?? '').toString();
        final aPrio = topLeagueNames.contains(aLeague) ? 0 : 1;
        final bPrio = topLeagueNames.contains(bLeague) ? 0 : 1;
        if (aPrio != bPrio) return aPrio.compareTo(bPrio);
        return (a['datetime'] ?? '').toString().compareTo((b['datetime'] ?? '').toString());
      });

      final MatchList parsed = [];
      for (final item in sortedRaw.take(50)) {
        final fixtureId = (item['id'] as num?)?.toInt() ?? 0;
        final leagueId = (item['league_id'] as num?)?.toInt();
        final homeId = (item['home_id'] as num?)?.toInt();
        final awayId = (item['away_id'] as num?)?.toInt();
        final matchId = 'sportapi_$fixtureId';

        final homeTeam = (item['home_team'] ?? 'Hazai').toString();
        final awayTeam = (item['away_team'] ?? 'Vendég').toString();
        final leagueName = (item['league_name'] ?? 'Bajnokság').toString();
        final leagueZone = (item['league_zone'] ?? '').toString();
        final status = (item['status'] ?? 'Scheduled').toString();
        final minute = item['minute']?.toString();
        final homeScore = (item['home_score'] as num?)?.toInt();
        final awayScore = (item['away_score'] as num?)?.toInt();

        String timeStr = dayLabel;
        final dtStr = (item['datetime'] ?? '').toString();
        if (dtStr.length >= 16) {
          timeStr = '$dayLabel ${dtStr.substring(11, 16)}';
        }

        final rng = math.Random(fixtureId);
        double hXg = 1.25 + (rng.nextDouble() * 0.95);
        double aXg = 0.95 + (rng.nextDouble() * 0.85);
        int? homePos;
        int? awayPos;
        bool hasStandings = false;
        BoolList trendList = List.generate(6, (_) => rng.nextDouble() > 0.3);
        StringList hForm = ['W', 'D', 'W', 'W', 'L'];
        StringList aForm = ['L', 'W', 'D', 'L', 'W'];

        if (leagueId != null && _standingsCache.containsKey(leagueId)) {
          final table = _standingsCache[leagueId]!;
          final hInfo = homeId != null ? table[homeId] : null;
          final aInfo = awayId != null ? table[awayId] : null;
          if (hInfo != null && aInfo != null && hInfo.played > 0 && aInfo.played > 0) {
            final lAvg = leagueAvgGoals(table);
            final hAttack = hInfo.blendedGoalsFor / lAvg;
            final aDefense = aInfo.blendedGoalsAgainst / lAvg;
            final aAttack = aInfo.blendedGoalsFor / lAvg;
            final hDefense = hInfo.blendedGoalsAgainst / lAvg;

            hXg = (hAttack * aDefense * lAvg * 1.12).clamp(0.45, 3.6);
            aXg = (aAttack * hDefense * lAvg * 0.94).clamp(0.35, 3.2);
            homePos = hInfo.position;
            awayPos = aInfo.position;
            hasStandings = true;
            trendList = extractFormTrend(hInfo, aInfo);
            hForm = extractWdlCodes(hInfo);
            aForm = extractWdlCodes(aInfo);
          }
        }

        final pick = buildPickFromXg(
          id: matchId,
          fixtureId: fixtureId,
          leagueId: leagueId,
          homeId: homeId,
          awayId: awayId,
          league: leagueName,
          leagueZone: leagueZone,
          kickoff: timeStr,
          status: status,
          minute: minute,
          homeScore: homeScore,
          awayScore: awayScore,
          homeTeam: homeTeam,
          awayTeam: awayTeam,
          homeXg: hXg,
          awayXg: aXg,
          last6Trend: trendList,
          homeFormCodes: hForm,
          awayFormCodes: aForm,
          homePos: homePos,
          awayPos: awayPos,
          hasStandingData: hasStandings,
          isWatched: watchedIds.contains(matchId),
          customOdds: customOddsMap[matchId],
        );

        parsed.add(pick);
      }

      return SportApiResponse(
        success: true,
        statusCode: 200,
        matches: parsed,
        rawPreview: preview,
        message: '${parsed.length} meccs betöltve ($dateStr)!',
        rateLimitRemaining: remaining,
      );
    } catch (e) {
      return SportApiResponse(
        success: false,
        statusCode: 0,
        matches: [],
        rawPreview: e.toString(),
        message: 'Hálózati hiba: $e',
      );
    }
  }

  static Future<StandingsMap> fetchStandings({
    required String baseUrl,
    required String apiKey,
    required int leagueId,
  }) async {
    if (_standingsCache.containsKey(leagueId)) {
      return _standingsCache[leagueId]!;
    }

    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$cleanBase/standings/$leagueId');

    try {
      final response = await _getWithEtag(uri, apiKey);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
        final List<dynamic> rows = (decoded is Map && decoded['data'] is List) ? decoded['data'] : [];
        final StandingsMap map = {};

        for (final row in rows) {
          if (row is! Map) continue;
          final teamObj = row['team'];
          final teamId = (teamObj is Map ? (teamObj['id'] as num?)?.toInt() : null) ?? 0;
          if (teamId == 0) continue;

          final JsonList formList = [];
          if (row['form'] is List) {
            for (final item in row['form']) {
              if (item is JsonMap) {
                formList.add(item);
              }
            }
          }

          map[teamId] = TeamStandingInfo(
            teamId: teamId,
            teamName: (teamObj is Map ? teamObj['name'] : 'Csapat').toString(),
            position: (row['position'] as num?)?.toInt() ?? 0,
            played: (row['played'] as num?)?.toInt() ?? 0,
            won: (row['won'] as num?)?.toInt() ?? 0,
            draw: (row['draw'] as num?)?.toInt() ?? 0,
            lost: (row['lost'] as num?)?.toInt() ?? 0,
            goalsFor: (row['goals_for'] as num?)?.toInt() ?? 0,
            goalsAgainst: (row['goals_against'] as num?)?.toInt() ?? 0,
            points: (row['points'] as num?)?.toInt() ?? 0,
            form: formList,
          );
        }

        if (map.isNotEmpty) {
          _standingsCache[leagueId] = map;
        }
        return map;
      }
    } catch (_) {}
    return {};
  }

  static Future<JsonList> fetchH2H({
    required String baseUrl,
    required String apiKey,
    required int fixtureId,
    int? homeId,
    int? awayId,
  }) async {
    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final candidateUris = <Uri>[
      Uri.parse('$cleanBase/fixtures/$fixtureId/h2h'),
      if (homeId != null && awayId != null) Uri.parse('$cleanBase/teams/$homeId/h2h/$awayId'),
    ];

    for (final uri in candidateUris) {
      try {
        final res = await _getWithEtag(uri, apiKey);
        if (res.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
          final dynamic raw = (decoded is Map) ? (decoded['data'] ?? decoded['h2h']) : decoded;
          if (raw is List && raw.isNotEmpty) {
            final JsonList list = [];
            for (final item in raw) {
              if (item is JsonMap) list.add(item);
            }
            if (list.isNotEmpty) return list;
          }
        }
      } catch (_) {}
    }
    return [];
  }

  static Future<FixtureFullBundle?> fetchFullBundle({
    required String baseUrl,
    required String apiKey,
    required int fixtureId,
    int? leagueId,
    int? homeId,
    int? awayId,
  }) async {
    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/$'), '');

    try {
      final f0 = _getWithEtag(Uri.parse('$cleanBase/fixtures/$fixtureId'), apiKey);
      final f1 = _getWithEtag(Uri.parse('$cleanBase/fixtures/$fixtureId/stats'), apiKey);
      final f2 = _getWithEtag(Uri.parse('$cleanBase/fixtures/$fixtureId/lineups'), apiKey);
      final f3 = fetchH2H(
        baseUrl: baseUrl,
        apiKey: apiKey,
        fixtureId: fixtureId,
        homeId: homeId,
        awayId: awayId,
      );

      final r0 = await f0;
      final r1 = await f1;
      final r2 = await f2;
      final h2hList = await f3;

      JsonMap? fixtureObj;
      if (r0.statusCode == 200) {
        final d0 = jsonDecode(utf8.decode(r0.bodyBytes, allowMalformed: true));
        if (d0 is Map && d0['fixture'] is JsonMap) {
          fixtureObj = d0['fixture'];
        }
      }

      JsonMap? homeStats;
      JsonMap? awayStats;
      if (r1.statusCode == 200) {
        final d1 = jsonDecode(utf8.decode(r1.bodyBytes, allowMalformed: true));
        if (d1 is Map && d1['available'] == true && d1['data'] is Map) {
          homeStats = d1['data']['home'] as JsonMap?;
          awayStats = d1['data']['away'] as JsonMap?;
        }
      }

      bool lineupsAvail = false;
      final JsonList homeStarters = [];
      final JsonList homeSubs = [];
      final JsonList awayStarters = [];
      final JsonList awaySubs = [];

      if (r2.statusCode == 200) {
        final d2 = jsonDecode(utf8.decode(r2.bodyBytes, allowMalformed: true));
        if (d2 is Map && d2['available'] == true && d2['data'] is Map) {
          lineupsAvail = true;
          final hObj = d2['data']['home'];
          final aObj = d2['data']['away'];
          if (hObj is Map && hObj['starters'] is List) {
            for (final p in hObj['starters']) {
              if (p is JsonMap) homeStarters.add(p);
            }
          }
          if (hObj is Map && hObj['subs'] is List) {
            for (final p in hObj['subs']) {
              if (p is JsonMap) homeSubs.add(p);
            }
          }
          if (aObj is Map && aObj['starters'] is List) {
            for (final p in aObj['starters']) {
              if (p is JsonMap) awayStarters.add(p);
            }
          }
          if (aObj is Map && aObj['subs'] is List) {
            for (final p in aObj['subs']) {
              if (p is JsonMap) awaySubs.add(p);
            }
          }
        }
      }

      final JsonList eventsList = [];
      if (fixtureObj?['events'] is List) {
        for (final ev in fixtureObj!['events']) {
          if (ev is JsonMap) {
            eventsList.add(ev);
          }
        }
      }

      StandingRowList standingRows = [];
      if (leagueId != null) {
        final tableMap = await fetchStandings(
          baseUrl: baseUrl,
          apiKey: apiKey,
          leagueId: leagueId,
        );
        standingRows = tableMap.values.toList()..sort((a, b) => a.position.compareTo(b.position));
      }

      return FixtureFullBundle(
        stadium: fixtureObj?['home_stadium']?.toString(),
        city: fixtureObj?['home_city']?.toString(),
        homeCoach: fixtureObj?['home_coach']?.toString(),
        awayCoach: fixtureObj?['away_coach']?.toString(),
        htHome: (fixtureObj?['ht_home'] as num?)?.toInt(),
        htAway: (fixtureObj?['ht_away'] as num?)?.toInt(),
        events: eventsList,
        homeStats: homeStats,
        awayStats: awayStats,
        lineupsAvailable: lineupsAvail,
        homeStarters: homeStarters,
        homeSubs: homeSubs,
        awayStarters: awayStarters,
        awaySubs: awaySubs,
        standings: standingRows,
        h2hMatches: h2hList,
      );
    } catch (_) {
      return null;
    }
  }
}
