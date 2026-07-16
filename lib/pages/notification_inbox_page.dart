import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mindease_app/theme/app_theme.dart';

class NotificationInboxPage extends StatefulWidget {
  const NotificationInboxPage({super.key});

  @override
  State<NotificationInboxPage> createState() => _NotificationInboxPageState();
}

class _NotificationInboxPageState extends State<NotificationInboxPage> {
  String? _myUitmId;
  bool _isLoading = true;

  final List<String> _collections = ['students', 'personalAdvisor', 'counsellors', 'admins'];

  @override
  void initState() {
    super.initState();
    _resolveMyId();
  }

  Future<void> _resolveMyId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    for (final collection in _collections) {
      final query = await FirebaseFirestore.instance
          .collection(collection)
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        setState(() {
          _myUitmId = query.docs.first.id;
          _isLoading = false;
        });
        return;
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _markAsRead(String docId) async {
    await FirebaseFirestore.instance
        .collection('notificationInbox')
        .doc(docId)
        .update({'read': true});
  }

  void _handleTap(Map<String, dynamic> notif, String docId) {
    if (notif['read'] != true) _markAsRead(docId);

    final type = notif['type'] as String? ?? '';
    String? route;

    switch (type) {
      case 'new_referral':
      case 'student_request':
        route = '/counsellors_dashboard';
        break;
      case 'referral_accepted':
      case 'referral_declined':
      case 'referral_done':
      case 'pa_missing_mood_alert':
        route = '/personalAdvisor';
        break;
      case 'request_accepted':
      case 'request_unavailable':
      case 'session_done':
      case 'session_scheduled':
      case 'counsellor_message':
        route = '/dashboard';
        break;
      case 'session_acknowledged':
        route = '/counsellors_dashboard';
        break;
      case 'student_unreachable':
        route = '/personalAdvisor';
        break;
      case 'mood_reminder':
        route = '/moodLogging';
        break;
      case 'dass21_reminder':
        route = '/stressAssessment';
        break;
    }

    if (route != null) {
      Navigator.pushNamed(context, route);
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'new_referral':
        return Icons.assignment_ind;
      case 'referral_accepted':
      case 'request_accepted':
        return Icons.check_circle;
      case 'referral_declined':
      case 'request_unavailable':
        return Icons.cancel;
      case 'referral_done':
      case 'session_done':
        return Icons.task_alt;
      case 'session_scheduled':
        return Icons.event_available;
      case 'session_acknowledged':
        return Icons.thumb_up;
      case 'counsellor_message':
        return Icons.chat_bubble;
      case 'student_unreachable':
        return Icons.phone_missed;
      case 'student_request':
        return Icons.front_hand;
      case 'mood_reminder':
        return Icons.sentiment_satisfied_alt;
      case 'pa_missing_mood_alert':
        return Icons.warning_amber_rounded;
      case 'dass21_reminder':
        return Icons.psychology_alt;
      default:
        return Icons.notifications;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'referral_accepted':
      case 'request_accepted':
      case 'referral_done':
      case 'session_done':
        return AppTheme.secondary;
      case 'referral_declined':
      case 'request_unavailable':
      case 'student_unreachable':
        return const Color(0xFFE57373);
      case 'pa_missing_mood_alert':
        return const Color(0xFFFFB74D);
      case 'session_scheduled':
        return AppTheme.secondary;
      default:
        return AppTheme.primary;
    }
  }

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              decoration: const BoxDecoration(
                gradient: AppTheme.headerGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Row(
                      children: [
                        Icon(Icons.arrow_back_ios, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text("Back", style: TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Notifications",
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Stay updated on your activity",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),

            // ── Notification list (live) ──
            Expanded(
              child: _isLoading || _myUitmId == null
                  ? const Center(child: CircularProgressIndicator())
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('notificationInbox')
                          .where('recipient_id', isEqualTo: _myUitmId)
                          .orderBy('created_at', descending: true)
                          .limit(50)
                          .snapshots(),
                      builder: (context, snapshot) {
                        // ── Keep showing spinner until we have confirmed data ──
                        if (snapshot.connectionState == ConnectionState.waiting ||
                            !snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        // ── Catch Firestore index errors ──
                        if (snapshot.hasError) {
                          print("Notification inbox error: ${snapshot.error}");
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline, color: AppTheme.textGrey, size: 48),
                                const SizedBox(height: 12),
                                Text("Could not load notifications",
                                    style: TextStyle(color: AppTheme.textGrey)),
                                const SizedBox(height: 6),
                                Text("Check your internet connection and try again",
                                    style: TextStyle(color: AppTheme.textGrey, fontSize: 11),
                                    textAlign: TextAlign.center),
                              ],
                            ),
                          );
                        }

                        if (snapshot.data!.docs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.notifications_none, color: AppTheme.textGrey, size: 48),
                                const SizedBox(height: 12),
                                Text("No notifications yet", style: TextStyle(color: AppTheme.textGrey)),
                              ],
                            ),
                          );
                        }

                        final docs = snapshot.data!.docs;

                        return ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final type = data['type'] as String? ?? 'general';
                            final isRead = data['read'] == true;

                            return GestureDetector(
                              onTap: () => _handleTap(data, doc.id),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isRead ? Colors.white : AppTheme.primarySoft,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: _colorFor(type).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(_iconFor(type), color: _colorFor(type), size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            data['title'] ?? '-',
                                            style: TextStyle(
                                              fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                                              fontSize: 14,
                                              color: AppTheme.textDark,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            data['body'] ?? '-',
                                            style: TextStyle(fontSize: 12, color: AppTheme.textGrey, height: 1.4),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _timeAgo(data['created_at'] as Timestamp?),
                                            style: TextStyle(fontSize: 10, color: AppTheme.textGrey),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!isRead)
                                      Container(
                                        width: 8,
                                        height: 8,
                                        margin: const EdgeInsets.only(top: 4),
                                        decoration: const BoxDecoration(
                                          color: AppTheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}