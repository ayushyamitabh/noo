import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LoginFlowInit {
  final Uri loginUrl;
  final Uri pollEndpoint;
  final String pollToken;

  const LoginFlowInit({
    required this.loginUrl,
    required this.pollEndpoint,
    required this.pollToken,
  });
}

class LoginFlowResult {
  final String serverUrl;
  final String loginName;
  final String appPassword;

  const LoginFlowResult({
    required this.serverUrl,
    required this.loginName,
    required this.appPassword,
  });
}

/// Implements Nextcloud's "Login Flow v2": the app never sees the user's
/// real password. It asks the server for a one-time login URL, the user
/// authorizes in their browser, and the app polls until the server hands
/// back a scoped app password.
/// https://docs.nextcloud.com/server/latest/developer_manual/client_apis/LoginFlow/index.html#login-flow-v2
class LoginFlowService {
  static const _userAgent = 'Nextcloud-Flutter-Client/1.0';

  static String normalizeServerUrl(String input) {
    var url = input.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  static Future<LoginFlowInit> initiate(String serverUrl) async {
    final cleanUrl = normalizeServerUrl(serverUrl);
    final endpoint = Uri.parse('$cleanUrl/index.php/login/v2');
    debugPrint('[LoginFlow] Initiating login flow at $endpoint');

    final response = await http.post(
      endpoint,
      headers: {'User-Agent': _userAgent, 'OCS-APIRequest': 'true'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Could not start login flow (HTTP ${response.statusCode}). '
        'Check the server address and that it is a reachable Nextcloud instance.',
      );
    }

    final data = jsonDecode(response.body);
    final loginUrl = data['login'] as String?;
    final poll = data['poll'] as Map?;
    final pollToken = poll?['token'] as String?;
    final pollEndpoint = poll?['endpoint'] as String?;

    if (loginUrl == null || pollToken == null || pollEndpoint == null) {
      throw Exception('Server response did not include login flow details.');
    }

    return LoginFlowInit(
      loginUrl: Uri.parse(loginUrl),
      pollEndpoint: Uri.parse(pollEndpoint),
      pollToken: pollToken,
    );
  }

  /// Performs a single poll attempt. Returns null while the user has not
  /// finished authorizing yet (server responds 404 during that window).
  static Future<LoginFlowResult?> poll(Uri pollEndpoint, String token) async {
    final response = await http.post(
      pollEndpoint,
      headers: {
        'User-Agent': _userAgent,
        'OCS-APIRequest': 'true',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'token': token},
    );

    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw Exception('Login poll failed (HTTP ${response.statusCode}).');
    }

    final data = jsonDecode(response.body);
    final server = data['server'] as String?;
    final loginName = data['loginName'] as String?;
    final appPassword = data['appPassword'] as String?;

    if (server == null || loginName == null || appPassword == null) {
      throw Exception('Server response did not include app credentials.');
    }

    return LoginFlowResult(
      serverUrl: server,
      loginName: loginName,
      appPassword: appPassword,
    );
  }
}
