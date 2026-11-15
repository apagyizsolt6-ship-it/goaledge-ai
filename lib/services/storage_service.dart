import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../core/constants.dart';

class StorageService {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<String> getApiKey() async => (await _prefs).getString('api_key') ?? '';
  Future<void> setApiKey(String v) async => (await _prefs).setString('api_key', v);

  Future<String> getBaseUrl() async =>
      (await _prefs).getString('base_url') ?? 'https://sportapi.ai/api';
  Future<void> setBaseUrl(String v) async => (await _prefs).setString('base_url', v);

  Future<double> getBankroll() async =>
      (await _prefs).getDouble('bankroll') ?? AppConstants.defaultBankroll;
  Future<void> setBankroll(double v) async => (await _prefs).setDouble('bankroll', v);

  Future<bool> getAutoBankroll() async => (await _prefs).getBool('auto_bankroll') ?? true;
  Future<void> setAutoBankroll(bool v) async => (await _prefs).setBool('auto_bankroll', v);

  Future<String> getStakeProfile() async =>
      (await _prefs).getString('stake_profile') ?? 'half_kelly';
  Future<void> setStakeProfile(String v) async => (await _prefs).setString('stake_profile', v);

  Future<Set<String>> getFavoriteLeagues() async {
    final list = (await _prefs).getStringList('favorite_leagues');
    if (list == null || list.isEmpty) return Set.from(AppConstants.defaultFavoriteLeagues);
    return list.toSet();
  }

  Future<void> setFavoriteLeagues(Set<String> v) async =>
      (await _prefs).setStringList('favorite_leagues', v.toList());

  Future<List<BetRecord>> getBets() async {
    final raw = (await _prefs).getString('bets_json');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => BetRecord.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> setBets(List<BetRecord> bets) async {
    final encoded = jsonEncode(bets.map((b) => b.toJson()).toList());
    await (await _prefs).setString('bets_json', encoded);
  }

  Future<List<MatchPick>> getCachedMatches() async {
    final raw = (await _prefs).getString('matches_json');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => MatchPick.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> setCachedMatches(List<MatchPick> matches) async {
    final encoded = jsonEncode(matches.map((m) => m.toJson()).toList());
    await (await _prefs).setString('matches_json', encoded);
  }
}
