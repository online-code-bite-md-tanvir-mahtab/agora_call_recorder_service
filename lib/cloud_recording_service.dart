// TODO Implement this library.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CloudRecordingService {
  final String baseUrl = "https://agora-backend-recording.vercel.app";

  // Add these state variables
  String? _dialInNumber;
  String? _dialInPin;
  bool _isDialInReady = false;

  // These are critical to stop the recording later
  String? _resourceId;
  String? _sid;

  bool get isRecording => _sid != null;

  Future<bool> makeOutboundPstnCall({
    required String channel,
    required String phoneNumber, // e.g. "+8801708740388"
    required String token, // RTC token if needed
    required int uid,
  }) async {
    String baseUrl = 'https://sipcm.agora.io/v1/api/pstn';
    String authHeader = 'Basic kV7mZp3xBw1QrT9nYj6Lf2HcUo8EgS4dAiX5tR';
    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Authorization': authHeader,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "action": "outbound",
          "appid": "730cfea947ff4fc9bf3effe2dbde59e6",
          "token":
              token, // Pass the RTC token if your backend requires it for auth
          "uid": "0",
          "channel": "test_channel",
          "region": "AREA_CODE_NA",
          "prompt": "false",
          "to": phoneNumber, // e.g. "+8801708740388"
          "from": "+15078703438",
          "timeout": "3600",
          "sip": "agora736.pstn.ashburn.twilio.com",
          "webhook_url":
              "https://agora-backend-recording.vercel.app/webhook/call-events",
          // Try adding this if API accepts it (check docs or test)
          "greeting": "Hello, this is a test call. Please stay on the line.",
          "early_media": "true", // Some gateways support this
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("Outbound call initiated: $data");
        return true;
      } else {
        debugPrint("Outbound failed: ${response.body}");
        return false;
      }
    } catch (e) {
      debugPrint("Error initiating outbound: $e");
      return false;
    }
  }

  // 1. START RECORDING FLOW
  Future<bool> startRecording({
    required String channel,
    required String uid,
    required String agora_token,
  }) async {
    try {
      // Step A: Acquire Resource ID
      Map<String, dynamic> acquireData = await _acquire(channel, uid);
      debugPrint("Acquire Data: $acquireData");
      _resourceId = acquireData["resourceId"];
      channel = acquireData["cname"];
      debugPrint("Resource ID: $_resourceId");

      if (_resourceId == null) {
        throw Exception("Failed to get Resource ID");
      }
      debugPrint("found resource id");

      // Step B: Start Recording
      final startData = await _start(_resourceId!, channel, "0", agora_token);
      debugPrint("start data");
      _sid = startData['sid'];
      debugPrint("SID: $_sid");
      if (_sid == null) {
        throw Exception("Failed to get SID");
      }

      debugPrint("✅ Cloud Recording Started. SID: $_sid");
      return true;
    } catch (e) {
      debugPrint("❌ Cloud Recording Start Error: $e");
      return false;
    }
  }

  // 2. STOP RECORDING FLOW
  Future<Map<String, dynamic>> stopRecording({
    required String channel,
    required String uid,
  }) async {
    if (_resourceId == null || _sid == null) {
      debugPrint("⚠️ No active recording session to stop");
      return {"success": false, "error": "No active recording session"};
    }

    try {
      final stopData = await _stop(_resourceId!, _sid!, channel, uid);
      debugPrint(
        "stopData : resourceId: $_resourceId, sid: $_sid, channel: $channel, uid: $uid",
      );

      debugPrint("✅ Cloud Recording Stopped: $stopData");

      return {"success": true, "data": stopData};
    } catch (e) {
      debugPrint("❌ Cloud Recording Stop Error: $e");

      return {"success": false, "error": e.toString()};
    }
  }

  Future<void> waitForUpload() async {
    if (_resourceId == null || _sid == null) return;

    while (true) {
      debugPrint(
        "Checking upload status for Resource ID: $_resourceId, SID: $_sid",
      );
      final res = await queryRecording(_resourceId!, _sid!);
      debugPrint("Query Result: $res");
      final status = res["serverResponse"]?["uploadingStatus"];
      debugPrint("Upload status: $status");

      if (status == "uploaded") {
        debugPrint("🎉 File is in GCS!");

        // NOW you can clear
        _resourceId = null;
        _sid = null;
        break;
      }

      await Future.delayed(const Duration(seconds: 15));
    }
  }

  // Private helper methods for API calls
  Future<Map<String, dynamic>> _acquire(String channel, String uid) async {
    final response = await http.post(
      Uri.parse("$baseUrl/acquire"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"channel": channel, "uid": 0}),
    );
    debugPrint("Acquire Response: ${response.body}");
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> _start(
    String resourceId,
    String channel,
    String uid,
    String agora_token,
  ) async {
    debugPrint(
      "Starting recording with Resource ID: $resourceId, Channel: $channel, UID: $uid",
    );
    final response = await http.post(
      Uri.parse("$baseUrl/start"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "resourceId": resourceId,
        "channel": channel,
        "uid": "0",
        "agora_token":
            agora_token, // Pass the RTC token if your backend requires it
      }),
    );
    debugPrint("Start Response: ${response.body}");
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> _stop(
    String resourceId,
    String sid,
    String channel,
    String uid,
  ) async {
    debugPrint(
      "Stopping recording with Resource ID: $resourceId, SID: $sid, Channel: $channel, UID: $uid",
    );
    final response = await http.post(
      Uri.parse("$baseUrl/stop"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "resourceId": resourceId,
        "sid": sid,
        "channel": channel,
        "uid": "0",
      }),
    );
    debugPrint("Stop Response: ${response.body}");
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> queryRecording(
    String resourceId,
    String sid,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/query"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"resourceId": resourceId, "sid": sid}),
    );

    debugPrint("Query Response: ${response.body}");
    return jsonDecode(response.body);
  }

  Future<bool> makeCall({
    required String channel,
    required String phone,
    required String token,
    required int uid,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/make-call"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "channel": channel,
          "phone": phone,
          "token": token,
          "uid": uid,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        debugPrint("Call failed: ${response.body}");
        return false;
      }
    } catch (e) {
      debugPrint("HTTP error: $e");
      return false;
    }
  }

  // New method to fetch / generate inbound details
  Future<void> fetchInboundDetails() async {
    try {
      // Option A: Call your own Vercel backend that calls Agora API
      final response = await http.post(
        Uri.parse(
          'https://agora-backend-recording.vercel.app/generate-inbound',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'channel': "test_channel", 'uid': '0'}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("Inbound details: $data");
        _isDialInReady = true;
      } else {
        debugPrint("Failed to get dial-in details");
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  String? _currentToken;

  Future<String> getFreshToken(String channelName, int uid) async {
    if (_currentToken != null) return _currentToken!;

    try {
      final res = await http.post(
        Uri.parse('https://agora-backend-recording.vercel.app/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'channel': channelName,
          'uid': uid,
          'role': 1, // 1 = Subscriber, 2 = Publisher (adjust as needed)
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          _currentToken = data['token'];
          return _currentToken!;
        } else {
          throw Exception(data['error'] ?? "Token generation failed");
        }
      } else {
        throw Exception("Server error: ${res.statusCode}");
      }
    } catch (e) {
      debugPrint("Token fetch error: $e");
      rethrow;
    }
  }

  Future<void> sendFcmTokenToBackend(String token) async {
    try {
      final res = await http.post(
        Uri.parse('https://agora-backend-recording.vercel.app/save-fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'userId': 'user123', // ← replace with real user ID (from auth/login)
          'phoneNumber':
              '+15078703438', // optional - if you want to use phone as key
          'deviceInfo': Platform.isAndroid ? 'Android' : 'iOS',
        }),
      );

      if (res.statusCode == 200) {
        debugPrint("FCM token sent to backend successfully");
      } else {
        debugPrint("Failed to send FCM token: ${res.body}");
      }
    } catch (e) {
      debugPrint("Error sending FCM token: $e");
    }
  }

  Future<Map<String, dynamic>?> getAgoraToken({
    String? userId,
    String? phoneNumber,
    String? channel,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/get-agora-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId, // optional
          'phoneNumber': phoneNumber, // optional
          'channel': channel, // optional
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          debugPrint(
            "Agora token retrieved: ${data['token']?.substring(0, 20)}...",
          );
          return data;
        } else {
          debugPrint("Backend error: ${data['error']}");
          return null;
        }
      } else {
        debugPrint("Server error: ${response.statusCode} - ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("Exception fetching Agora token: $e");
      return null;
    }
  }
}
