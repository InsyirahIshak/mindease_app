import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class NotificationService {
  static const String _appId = '5e7af0b4-b070-4407-9277-5c38afa7738d';
  static const String _apiKey =
      'os_v2_app_lz5pbnfqobcapetxlq4k7j3trx4wm4ed2siuthvr3lxw6cz2q5l3kclxja5hg6ghkoxa4l3dzqnzi7pzm2e5plw66jocn3nblh2y3bq';

  // ── Global navigator key so we can navigate from anywhere, even when
  // the app was opened FROM a notification tap (cold start) ──
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // ── Initialize OneSignal ──
  static Future<void> initialize() async {
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize(_appId);
    await OneSignal.Notifications.requestPermission(true);

    // ── Show notifications even when app is in foreground ──
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      event.notification.display();
    });

    await savePlayerIdToFirestore();
    _setupClickListener();
  }

  // ── Listen for notification taps and route accordingly ──
  static void _setupClickListener() {
    OneSignal.Notifications.addClickListener((event) {
      final data = event.notification.additionalData;
      print("Notification clicked with data: $data");
      _handleNotificationClick(data);
    });
  }

  // ── Route to the correct page based on notification type ──
  static void _handleNotificationClick(Map<String, dynamic>? data) {
    if (data == null) return;

    final type = data['type'] as String?;
    final context = navigatorKey.currentContext;
    if (context == null) return;

    // Small delay ensures the navigator is ready, especially on cold start
    Future.delayed(const Duration(milliseconds: 300), () {
      switch (type) {
        case 'new_referral': // PA referred student -> counsellor
          Navigator.of(context).pushNamed('/counsellors_dashboard');
          break;
        case 'referral_accepted':
        case 'referral_declined':
        case 'referral_done': // counsellor responded -> notify PA
          Navigator.of(context).pushNamed('/personalAdvisor');
          break;
        case 'student_request': // student requested counsellor directly
          Navigator.of(context).pushNamed('/counsellors_dashboard');
          break;
        case 'request_accepted':
        case 'request_unavailable':
        case 'session_done': // counsellor responded -> notify student
          Navigator.of(context).pushNamed('/dashboard');
          break;
        case 'session_scheduled':
          // Go to student dashboard where session card is visible
          Navigator.of(context).pushNamed('/dashboard');
          break;
        case 'counsellor_message':
          // Go to counsellors tab so student can see contact info to reply
          Navigator.of(context).pushNamed('/counsellors');
          break;
        case 'session_acknowledged':
          Navigator.of(context).pushNamed('/counsellors_dashboard');
          break;
        case 'student_unreachable':
          Navigator.of(context).pushNamed('/personalAdvisor');
          break;
        case 'mood_reminder':
          Navigator.of(context).pushNamed('/moodLogging');
          break;
        case 'pa_missing_mood_alert':
          Navigator.of(context).pushNamed('/personalAdvisor');
          break;
        case 'dass21_reminder':
          Navigator.of(context).pushNamed('/stressAssessment');
          break;
        default:
          // Fallback: just open the notification inbox
          Navigator.of(context).pushNamed('/notifications');
      }
    });
  }

  // ── Save OneSignal Player ID to Firestore ──
  static Future<void> savePlayerIdToFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final playerId = OneSignal.User.pushSubscription.id;
      if (playerId == null) return;

      final collections = ['students', 'personalAdvisor', 'counsellors', 'admins'];

      for (String collection in collections) {
        final query = await FirebaseFirestore.instance
            .collection(collection)
            .where('uid', isEqualTo: user.uid)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection(collection)
              .doc(query.docs.first.id)
              .update({'playerId': playerId});
          print("Player ID saved for $collection: $playerId");
          break;
        }
      }
    } catch (e) {
      print("Error saving player ID: $e");
    }
  }

  // ── Send push notification via OneSignal REST API ──
  // Now accepts a `type` and optional extra `data` so the click listener
  // knows where to navigate, and saves a copy to Firestore for the inbox.
  static Future<void> sendPushNotification({
    required List<String> playerIds,
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic>? data,
    String? recipientUitmId, // who should see this in their inbox
  }) async {
    try {
      final validIds = playerIds.where((id) => id.isNotEmpty).toList();
      if (validIds.isEmpty) return;

      final payload = {
        'type': type,
        ...?data,
      };

      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic $_apiKey',
        },
        body: jsonEncode({
          'app_id': _appId,
          'include_player_ids': validIds,
          'headings': {'en': title},
          'contents': {'en': body},
          'data': payload,
          // Android small icon — white silhouette resource (see setup notes)
          'small_icon': 'ic_stat_mindease',
          // Android accent colour for the notification (ARGB hex, no #)
          'android_accent_color': 'FF4DB6AC',
        }),
      );

      print("OneSignal response: ${response.statusCode} ${response.body}");

      // ── Save a copy to Firestore for the in-app inbox ──
      if (recipientUitmId != null) {
        await FirebaseFirestore.instance.collection('notificationInbox').add({
          'recipient_id': recipientUitmId,
          'title': title,
          'body': body,
          'type': type,
          'data': payload,
          'read': false,
          'created_at': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print("Error sending notification: $e");
    }
  }

  // ── Check and schedule 5PM reminder ──
  static Future<void> checkAndScheduleMoodReminder() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final studentQuery = await FirebaseFirestore.instance
          .collection('students')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (studentQuery.docs.isEmpty) return;

      final studId = studentQuery.docs.first.id;
      final today = DateTime.now().toIso8601String().substring(0, 10);

      final moodQuery = await FirebaseFirestore.instance
          .collection('moodLogs')
          .where('stud_id', isEqualTo: studId)
          .where('log_date', isEqualTo: today)
          .limit(1)
          .get();

      if (moodQuery.docs.isNotEmpty) {
        print("Mood already logged today — no reminder needed");
        return;
      }

      final now = DateTime.now();
      final fivePM = DateTime(now.year, now.month, now.day, 17, 0, 0);

      if (now.isAfter(fivePM)) {
        final playerId = OneSignal.User.pushSubscription.id;
        if (playerId != null) {
          await sendPushNotification(
            playerIds: [playerId],
            title: "MindEase 💙",
            body: "Reflect on your day — how are you feeling today?",
            type: 'mood_reminder',
            recipientUitmId: studId,
          );
        }
      }
    } catch (e) {
      print("Error in mood reminder: $e");
    }
  }

  // ── Send PA alert (student missing 3+ days) ──
  static Future<void> sendPAMissingMoodAlert({
    required String paPlayerId,
    required String paUitmId,
    required String studentName,
    required int daysMissing,
  }) async {
    await sendPushNotification(
      playerIds: [paPlayerId],
      title: "Student Alert ⚠️",
      body: "$studentName has not logged their mood for $daysMissing days.",
      type: 'pa_missing_mood_alert',
      recipientUitmId: paUitmId,
    );
  }
}