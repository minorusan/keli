import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Result of an update check against the backend's `/version.json`.
class UpdateInfo {
  final String version;
  final int build;
  final String apkUrl; // absolute
  final bool hasApk;
  final int currentBuild;

  const UpdateInfo({
    required this.version,
    required this.build,
    required this.apkUrl,
    required this.hasApk,
    required this.currentBuild,
  });

  bool get available => hasApk && build > currentBuild;
}

/// Pure: turn a parsed version.json + the running build into [UpdateInfo].
UpdateInfo parseUpdate(Map<String, dynamic> json, {required int currentBuild, required String baseUrl}) {
  final apkPath = (json['apkUrl'] as String?) ?? '/keli.apk';
  return UpdateInfo(
    version: (json['version'] as String?) ?? '0.0.0',
    build: (json['build'] as num?)?.toInt() ?? 0,
    apkUrl: apkPath.startsWith('http') ? apkPath : '$baseUrl$apkPath',
    hasApk: (json['hasApk'] as bool?) ?? true,
    currentBuild: currentBuild,
  );
}

class UpdateService {
  final String baseUrl;
  final int currentBuild;
  final http.Client _client;

  UpdateService({this.baseUrl = kKeliUrl, this.currentBuild = kAppBuild, http.Client? client})
      : _client = client ?? http.Client();

  Future<UpdateInfo> check() async {
    final res = await _client.get(Uri.parse('$baseUrl/version.json')).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw Exception('version host returned ${res.statusCode}');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return parseUpdate(json, currentBuild: currentBuild, baseUrl: baseUrl);
  }
}
