import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import '../core/constants.dart';

class AppUpdateInfo {
  final int remoteBuild;
  final String remoteVersion;
  final String apkUrl;
  final String releaseName;
  final String? releaseNotes;

  const AppUpdateInfo({
    required this.remoteBuild,
    required this.remoteVersion,
    required this.apkUrl,
    required this.releaseName,
    this.releaseNotes,
  });
}

class AppUpdateService {
  /// Optional: personal access token if the repo is private (read-only public_repo / contents).
  /// Prefer making the repo public for updates, or leave null.
  static String? githubToken;

  static Future<AppUpdateInfo?> checkForUpdate() async {
    if (kIsWeb) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final localBuild = int.tryParse(info.buildNumber) ?? 0;

      final headers = <String, String>{
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };
      if (githubToken != null && githubToken!.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer ${githubToken!.trim()}';
      }

      final res = await http
          .get(Uri.parse(AppConstants.githubReleasesApi), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        debugPrint('Update check failed: HTTP ${res.statusCode}');
        return null;
      }

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (json['tag_name'] ?? '').toString(); // e.g. build-45
      final name = (json['name'] ?? tag).toString();
      final body = json['body']?.toString();

      // tag formats: build-45 | v7.1.2+45 | 45
      final buildMatch = RegExp(r'(\d+)$').firstMatch(tag.replaceAll('+', '-'));
      final remoteBuild = int.tryParse(buildMatch?.group(1) ?? '') ?? 0;
      if (remoteBuild <= localBuild) return null;

      final assets = (json['assets'] as List?) ?? [];
      String? apkUrl;
      for (final a in assets) {
        final map = Map<String, dynamic>.from(a as Map);
        final n = (map['name'] ?? '').toString().toLowerCase();
        final url = (map['browser_download_url'] ?? '').toString();
        if (n.endsWith('.apk') && url.isNotEmpty) {
          apkUrl = url;
          break;
        }
      }
      if (apkUrl == null || apkUrl.isEmpty) return null;

      return AppUpdateInfo(
        remoteBuild: remoteBuild,
        remoteVersion: tag,
        apkUrl: apkUrl,
        releaseName: name,
        releaseNotes: body,
      );
    } catch (e, st) {
      debugPrint('Update check error: $e\n$st');
      return null;
    }
  }

  static Future<File?> downloadApk(
    AppUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/octet-stream',
    };
    if (githubToken != null && githubToken!.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${githubToken!.trim()}';
    }

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(update.apkUrl));
      req.headers.addAll(headers);
      final streamed = await client.send(req).timeout(const Duration(minutes: 5));
      if (streamed.statusCode != 200 && streamed.statusCode != 302) {
        debugPrint('APK download failed: ${streamed.statusCode}');
        return null;
      }

      final total = streamed.contentLength ?? 0;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/goaledge-update-${update.remoteBuild}.apk');
      final sink = file.openWrite();
      var received = 0;

      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await sink.close();
      return file;
    } finally {
      client.close();
    }
  }
}
