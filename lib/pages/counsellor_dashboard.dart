import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mindease_app/theme/app_theme.dart';
import 'package:mindease_app/services/notification_service.dart';

class CounsellorDashboard extends StatefulWidget {
  const CounsellorDashboard({super.key});

  @override
  State<CounsellorDashboard> createState() => _CounsellorDashboardState();
}

class _CounsellorDashboardState extends State<CounsellorDashboard> {
  Map<String, dynamic>? counsellorData;
  String? counsellorId;
  bool isLoading = true;
  int _currentIndex = 0;

  List<Map<String, dynamic>> pendingRequests = [];   // PA-referred
  List<Map<String, dynamic>> studentRequests = [];   // Student direct
  List<Map<String, dynamic>> myStudents = [];         // Accepted students

  final List<Map<String, dynamic>> moodMeta = [
    {'value': 1, 'emoji': '😞', 'label': 'Very Unpleasant', 'color': Color(0xFFE57373)},
    {'value': 2, 'emoji': '😕', 'label': 'Unpleasant', 'color': Color(0xFFFFB74D)},
    {'value': 3, 'emoji': '😐', 'label': 'Neutral', 'color': Color(0xFFFFD54F)},
    {'value': 4, 'emoji': '😊', 'label': 'Pleasant', 'color': Color(0xFF81C784)},
    {'value': 5, 'emoji': '😄', 'label': 'Very Pleasant', 'color': Color(0xFF4DB6AC)},
  ];

  @override
  void initState() {
    super.initState();
    loadCounsellorData();
  }

  Future<void> loadCounsellorData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final query = await FirebaseFirestore.instance
          .collection('counsellors')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return;

      counsellorId = query.docs.first.id;
      setState(() => counsellorData = query.docs.first.data());

      await _loadPendingRequests();
      await _loadStudentRequests();
      await _loadMyStudents();

    } catch (e) {
      print("Error loading counsellor data: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ── Load PA-referred pending requests ──
  Future<void> _loadPendingRequests() async {
    try {
      final referralQuery = await FirebaseFirestore.instance
          .collection('referrals')
          .where('counsellor_id', isEqualTo: counsellorId)
          .where('status', isEqualTo: 'pending')
          .orderBy('referral_date', descending: true)
          .get();

      List<Map<String, dynamic>> requests = [];

      for (var doc in referralQuery.docs) {
        final referralData = doc.data();
        final studId = referralData['stud_id'] as String;
        final paId = referralData['pa_id'] as String? ?? '';

        final studentDoc = await FirebaseFirestore.instance
            .collection('students').doc(studId).get();
        if (!studentDoc.exists) continue;
        final studentData = studentDoc.data()!;

        String paName = '-';
        if (paId.isNotEmpty) {
          final paDoc = await FirebaseFirestore.instance
              .collection('personalAdvisor').doc(paId).get();
          if (paDoc.exists) paName = paDoc.data()?['fullName'] ?? '-';
        }

        String threshold = await _getThreshold(studId);

        requests.add({
          'referral_id': doc.id,
          'stud_id': studId,
          'pa_id': paId,
          'pa_name': paName,
          'name': studentData['fullName'] ?? '-',
          'phone': studentData['phone'] ?? '-',
          'email': studentData['email'] ?? '-',
          'gender': studentData['stud_gender'] ?? studentData['gender'] ?? '-',
          'semester': studentData['stud_semester'] ?? studentData['semester'] ?? '-',
          'threshold': threshold,
          'referral_date': referralData['referral_date'] ?? '-',
          'source': 'pa',
        });
      }

      setState(() => pendingRequests = requests);
    } catch (e) {
      print("Error loading pending requests: $e");
    }
  }

  // ── Load student direct requests ──
  Future<void> _loadStudentRequests() async {
    try {
      final requestQuery = await FirebaseFirestore.instance
          .collection('counsellorRequests')
          .where('counsellor_id', isEqualTo: counsellorId)
          .where('status', isEqualTo: 'pending')
          .orderBy('request_date', descending: true)
          .get();

      List<Map<String, dynamic>> requests = [];

      for (var doc in requestQuery.docs) {
        final requestData = doc.data();
        final studId = requestData['stud_id'] as String;

        final studentDoc = await FirebaseFirestore.instance
            .collection('students').doc(studId).get();
        if (!studentDoc.exists) continue;
        final studentData = studentDoc.data()!;

        String threshold = await _getThreshold(studId);

        requests.add({
          'request_id': doc.id,
          'stud_id': studId,
          'name': studentData['fullName'] ?? '-',
          'phone': studentData['phone'] ?? '-',
          'email': studentData['email'] ?? '-',
          'gender': studentData['stud_gender'] ?? studentData['gender'] ?? '-',
          'semester': studentData['stud_semester'] ?? studentData['semester'] ?? '-',
          'threshold': threshold,
          'request_date': requestData['request_date'] ?? '-',
          'source': 'student',
        });
      }

      setState(() => studentRequests = requests);
    } catch (e) {
      print("Error loading student requests: $e");
    }
  }

  // ── Load accepted students (from both sources) ──
  Future<void> _loadMyStudents() async {
    try {
      List<Map<String, dynamic>> students = [];

      // From PA referrals
      final referralQuery = await FirebaseFirestore.instance
          .collection('referrals')
          .where('counsellor_id', isEqualTo: counsellorId)
          .where('status', isEqualTo: 'accepted')
          .orderBy('referral_date', descending: true)
          .get();

      for (var doc in referralQuery.docs) {
        final referralData = doc.data();
        if (referralData['done'] == true) continue;
        final studId = referralData['stud_id'] as String;
        final studentMap = await _buildStudentMap(studId, doc.id, 'pa');
        if (studentMap != null) students.add(studentMap);
      }

      // From student direct requests
      final requestQuery = await FirebaseFirestore.instance
          .collection('counsellorRequests')
          .where('counsellor_id', isEqualTo: counsellorId)
          .where('status', isEqualTo: 'accepted')
          .orderBy('request_date', descending: true)
          .get();

      for (var doc in requestQuery.docs) {
        final requestData = doc.data();
        if (requestData['done'] == true) continue;
        final studId = requestData['stud_id'] as String;
        final studentMap = await _buildStudentMap(studId, doc.id, 'student');
        if (studentMap != null) students.add(studentMap);
      }

      // Sort: critical first
      const order = {'critical': 0, 'moderate': 1, 'normal': 2};
      students.sort((a, b) {
        final aO = order[a['threshold']] ?? 3;
        final bO = order[b['threshold']] ?? 3;
        return aO.compareTo(bO);
      });

      setState(() => myStudents = students);
    } catch (e) {
      print("Error loading my students: $e");
    }
  }

  // ── Helper: get threshold ──
  Future<String> _getThreshold(String studId) async {
    try {
      final analysisQuery = await FirebaseFirestore.instance
          .collection('moodAnalysis')
          .where('stud_id', isEqualTo: studId)
          .where('type', isEqualTo: 'weekly')
          .orderBy('analysis_date', descending: true)
          .limit(1)
          .get();
      if (analysisQuery.docs.isNotEmpty) {
        return analysisQuery.docs.first.data()['risk_level']
                ?.toString().toLowerCase() ?? 'none';
      }
    } catch (e) {
      print("Threshold query error: $e");
    }
    return 'none';
  }

  // ── Helper: build student map ──
  Future<Map<String, dynamic>?> _buildStudentMap(
      String studId, String docId, String source) async {
    final studentDoc = await FirebaseFirestore.instance
        .collection('students').doc(studId).get();
    if (!studentDoc.exists) return null;
    final studentData = studentDoc.data()!;

    bool hasMoodHistory = false;
    String lastLogged = 'No logs yet';
    final moodQuery = await FirebaseFirestore.instance
        .collection('moodLogs')
        .where('stud_id', isEqualTo: studId)
        .orderBy('log_date', descending: true)
        .limit(1)
        .get();
    if (moodQuery.docs.isNotEmpty) {
      hasMoodHistory = true;
      lastLogged = moodQuery.docs.first.data()['log_date'] ?? '-';
    }

    String threshold = await _getThreshold(studId);

    return {
      'doc_id': docId,
      'source': source,
      'uitm_id': studId,
      'name': studentData['fullName'] ?? '-',
      'phone': studentData['phone'] ?? '-',
      'email': studentData['email'] ?? '-',
      'gender': studentData['stud_gender'] ?? studentData['gender'] ?? '-',
      'semester': studentData['stud_semester'] ?? studentData['semester'] ?? '-',
      'threshold': threshold,
      'hasMoodHistory': hasMoodHistory,
      'lastLogged': lastLogged,
      'referralStatus': 'accepted',
      'studentName': studentData['fullName'] ?? '-',
    };
  }

  // ── Accept PA referral ──
  Future<void> _acceptRequest(Map<String, dynamic> request) async {
    try {
      final referralId = request['referral_id'] as String;
      final today = DateTime.now().toIso8601String().substring(0, 10);

      await FirebaseFirestore.instance
          .collection('referrals').doc(referralId)
          .update({'status': 'accepted', 'accepted_date': today});

      final paId = request['pa_id'] as String;
      if (paId.isNotEmpty) {
        final paDoc = await FirebaseFirestore.instance
            .collection('personalAdvisor').doc(paId).get();
        final paPlayerId = paDoc.data()?['playerId'];
        final counsellorName = counsellorData?['fullName'] ?? 'Counsellor';
        if (paPlayerId != null) {
          await NotificationService.sendPushNotification(
            playerIds: [paPlayerId],
            title: 'Referral Accepted ✅',
            body: '${request['name']} is now under $counsellorName',
            type: 'referral_accepted',
            recipientUitmId: paId,
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Accepted ${request['name']}"),
        backgroundColor: AppTheme.secondary,
      ));

      await _loadPendingRequests();
      await _loadMyStudents();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // ── Decline PA referral ──
  Future<void> _declineRequest(Map<String, dynamic> request) async {
    try {
      final referralId = request['referral_id'] as String;

      await FirebaseFirestore.instance
          .collection('referrals').doc(referralId)
          .update({'status': 'declined'});

      final paId = request['pa_id'] as String;
      if (paId.isNotEmpty) {
        final paDoc = await FirebaseFirestore.instance
            .collection('personalAdvisor').doc(paId).get();
        final paPlayerId = paDoc.data()?['playerId'];
        final counsellorName = counsellorData?['fullName'] ?? 'Counsellor';
        if (paPlayerId != null) {
          await NotificationService.sendPushNotification(
            playerIds: [paPlayerId],
            title: 'Referral Declined',
            body: '${request['name']} referral was declined by $counsellorName',
            type: 'referral_declined',
            recipientUitmId: paId,
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Referral declined")));

      await _loadPendingRequests();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // ── Accept student direct request ──
  Future<void> _acceptStudentRequest(Map<String, dynamic> request) async {
    try {
      final requestId = request['request_id'] as String;
      final studId = request['stud_id'] as String;
      final today = DateTime.now().toIso8601String().substring(0, 10);

      await FirebaseFirestore.instance
          .collection('counsellorRequests').doc(requestId)
          .update({'status': 'accepted', 'accepted_date': today});

      final studentDoc = await FirebaseFirestore.instance
          .collection('students').doc(studId).get();
      final studentPlayerId = studentDoc.data()?['playerId'];
      final counsellorName = counsellorData?['fullName'] ?? 'Counsellor';

      if (studentPlayerId != null) {
        await NotificationService.sendPushNotification(
          playerIds: [studentPlayerId],
          title: 'Request Accepted ✅',
          body: '$counsellorName has accepted your request',
          type: 'request_accepted',
          recipientUitmId: studId,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Accepted ${request['name']}"),
        backgroundColor: AppTheme.secondary,
      ));

      await _loadStudentRequests();
      await _loadMyStudents();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // ── Mark student request as unavailable ──
  Future<void> _markUnavailable(Map<String, dynamic> request) async {
    try {
      final requestId = request['request_id'] as String;
      final studId = request['stud_id'] as String;

      await FirebaseFirestore.instance
          .collection('counsellorRequests').doc(requestId)
          .update({'status': 'unavailable'});

      final studentDoc = await FirebaseFirestore.instance
          .collection('students').doc(studId).get();
      final studentPlayerId = studentDoc.data()?['playerId'];
      final counsellorName = counsellorData?['fullName'] ?? 'Counsellor';

      if (studentPlayerId != null) {
        await NotificationService.sendPushNotification(
          playerIds: [studentPlayerId],
          title: 'Currently Unavailable',
          body: '$counsellorName is currently unavailable. Please try again later.',
          type: 'request_unavailable',
          recipientUitmId: studId,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Marked as unavailable")));

      await _loadStudentRequests();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // ── Mark student as Done ──
  Future<void> _markAsDone(Map<String, dynamic> student, String comment) async {
    try {
      final docId = student['doc_id'] as String;
      final source = student['source'] as String;
      final studId = student['uitm_id'] as String;
      final collection = source == 'pa' ? 'referrals' : 'counsellorRequests';
      final today = DateTime.now().toIso8601String().substring(0, 10);

      // ── Save comment permanently on the referral/request record ──
      await FirebaseFirestore.instance
          .collection(collection).doc(docId)
          .update({
        'done': true,
        'status': 'done',
        'counsellor_comment': comment,
        'done_date': today,
      });

      final counsellorName = counsellorData?['fullName'] ?? 'Counsellor';

      // ── Notify student — generic message, NO comment included ──
      final studentDoc = await FirebaseFirestore.instance
          .collection('students').doc(studId).get();
      final studentPlayerId = studentDoc.data()?['playerId'];
      if (studentPlayerId != null) {
        await NotificationService.sendPushNotification(
          playerIds: [studentPlayerId],
          title: 'Session Completed ✅',
          body: 'Your session with $counsellorName has been completed.',
          type: 'session_done',
          recipientUitmId: studId,
        );
      }

      // ── Notify PA — includes the counsellor's comment ──
      if (source == 'pa') {
        final referralDoc = await FirebaseFirestore.instance
            .collection('referrals').doc(docId).get();
        final paId = referralDoc.data()?['pa_id'] as String? ?? '';
        if (paId.isNotEmpty) {
          final paDoc = await FirebaseFirestore.instance
              .collection('personalAdvisor').doc(paId).get();
          final paPlayerId = paDoc.data()?['playerId'];
          if (paPlayerId != null) {
            await NotificationService.sendPushNotification(
              playerIds: [paPlayerId],
              title: 'Session Completed ✅',
              body: '${student['name']}\'s session with $counsellorName is complete. Note: $comment',
              type: 'referral_done',
              recipientUitmId: paId,
              data: {'comment': comment, 'student_name': student['name']},
            );
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("${student['name']} marked as done"),
        backgroundColor: AppTheme.primary,
      ));

      await _loadMyStudents();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // ── Schedule a session with the student ──
  Future<void> _scheduleSession(Map<String, dynamic> student, DateTime dateTime) async {
    try {
      final studId = student['uitm_id'] as String;
      final docId = student['doc_id'] as String;
      final counsellorName = counsellorData?['fullName'] ?? 'Counsellor';
      final dateStr = "${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}";
      final timeStr = "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";

      await FirebaseFirestore.instance.collection('sessionSchedules').add({
        'stud_id': studId,
        'counsellor_id': counsellorId,
        'referral_doc_id': docId,
        'source': student['source'],
        'session_date': dateStr,
        'session_time': timeStr,
        'scheduled_at': FieldValue.serverTimestamp(),
        'acknowledged': false,
        'status': 'scheduled', // scheduled, acknowledged, unreachable, completed
      });

      final studentDoc = await FirebaseFirestore.instance.collection('students').doc(studId).get();
      final studentPlayerId = studentDoc.data()?['playerId'];
      if (studentPlayerId != null) {
        await NotificationService.sendPushNotification(
          playerIds: [studentPlayerId],
          title: 'Session Scheduled 📅',
          body: '$counsellorName has scheduled a session with you on $dateStr at $timeStr.',
          type: 'session_scheduled',
          recipientUitmId: studId,
          data: {'session_date': dateStr, 'session_time': timeStr},
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Session scheduled with ${student['name']}"),
        backgroundColor: AppTheme.secondary,
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _showScheduleDialog(Map<String, dynamic> student) {
    DateTime? selectedDate;
    TimeOfDay? selectedTime;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("Schedule Session"),
            contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Pick a date and time for the session with ${student['name']}.",
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now().add(const Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 90)),
                      );
                      if (picked != null) setDialogState(() => selectedDate = picked);
                    },
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(selectedDate == null
                        ? "Choose Date"
                        : "${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}"),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                      if (picked != null) setDialogState(() => selectedTime = picked);
                    },
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(selectedTime == null ? "Choose Time" : selectedTime!.format(ctx)),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text("Cancel", style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppTheme.buttonGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          if (selectedDate == null || selectedTime == null) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text("Please select both date and time")),
                            );
                            return;
                          }
                          final dt = DateTime(selectedDate!.year, selectedDate!.month, selectedDate!.day,
                              selectedTime!.hour, selectedTime!.minute);
                          Navigator.pop(ctx);
                          _scheduleSession(student, dt);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text("Schedule", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Report student unreachable to PA ──
  Future<void> _reportUnreachable(Map<String, dynamic> student, String note) async {
    try {
      final source = student['source'] as String;
      final studId = student['uitm_id'] as String;
      final docId = student['doc_id'] as String;
      final counsellorName = counsellorData?['fullName'] ?? 'Counsellor';

      // Log the report regardless of source, for record-keeping
      await FirebaseFirestore.instance.collection('unreachableReports').add({
        'stud_id': studId,
        'counsellor_id': counsellorId,
        'referral_doc_id': docId,
        'note': note,
        'reported_at': FieldValue.serverTimestamp(),
      });

      if (source == 'pa') {
        final referralDoc = await FirebaseFirestore.instance.collection('referrals').doc(docId).get();
        final paId = referralDoc.data()?['pa_id'] as String? ?? '';
        if (paId.isNotEmpty) {
          final paDoc = await FirebaseFirestore.instance.collection('personalAdvisor').doc(paId).get();
          final paPlayerId = paDoc.data()?['playerId'];
          if (paPlayerId != null) {
            await NotificationService.sendPushNotification(
              playerIds: [paPlayerId],
              title: 'Student Unreachable ⚠️',
              body: '$counsellorName could not reach ${student['name']} for their session. Note: $note',
              type: 'student_unreachable',
              recipientUitmId: paId,
              data: {'note': note, 'student_name': student['name']},
            );
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(student['source'] == 'pa'
            ? "PA has been notified that ${student['name']} is unreachable"
            : "Report logged for ${student['name']}"),
        backgroundColor: const Color(0xFFFFB74D),
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _showUnreachableDialog(Map<String, dynamic> student) {
    final noteController = TextEditingController();
    final source = student['source'] as String;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.phone_missed, color: Color(0xFFFFB74D), size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text("Report Unreachable",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  source == 'pa'
                      ? "Describe what happened. PA will be notified."
                      : "Describe what happened. Logged for your records only.",
                  style: TextStyle(fontSize: 11, color: AppTheme.textGrey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: "e.g. Called 3 times, no answer...",
                    hintStyle: TextStyle(fontSize: 11, color: AppTheme.textGrey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFFFB74D)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFFFB74D)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFFFB74D), width: 2),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        child: const Text("Cancel", style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final note = noteController.text.trim();
                          if (note.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text("Please describe the situation")),
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          _reportUnreachable(student, note);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFB74D),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text("Send Report", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    );
  }

  // ── Send a free-form message to the student ──
  Future<void> _sendMessageToStudent(Map<String, dynamic> student, String message) async {
    try {
      final studId = student['uitm_id'] as String;
      final counsellorName = counsellorData?['fullName'] ?? 'Counsellor';

      final studentDoc = await FirebaseFirestore.instance.collection('students').doc(studId).get();
      final studentPlayerId = studentDoc.data()?['playerId'];

      if (studentPlayerId != null) {
        await NotificationService.sendPushNotification(
          playerIds: [studentPlayerId],
          title: 'Reminder from $counsellorName 🔔',
          body: message,
          type: 'counsellor_message',
          recipientUitmId: studId,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Message sent to ${student['name']}"),
        backgroundColor: AppTheme.secondary,
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _showSendMessageDialog(Map<String, dynamic> student) {
    final reminders = [
      "Your session is coming up soon — please be ready! 📅",
      "Please complete your DASS-21 stress assessment this week. 📋",
      "Remember to log your mood daily this week. 💙",
      "Please acknowledge your scheduled session in the MindEase app. ✅",
      "Just checking in — please log your mood today if you haven't yet. 🌟",
    ];

    String? selectedReminder = reminders[0];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("Send Reminder to ${student['name']}"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Select a reminder to send to the student.",
                  style: TextStyle(fontSize: 12, color: AppTheme.textGrey),
                ),
                const SizedBox(height: 12),
                ...reminders.map((r) => GestureDetector(
                  onTap: () => setDialogState(() => selectedReminder = r),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selectedReminder == r
                          ? AppTheme.primarySoft
                          : const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selectedReminder == r
                            ? AppTheme.primary
                            : const Color(0xFFE2E8F0),
                        width: selectedReminder == r ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedReminder == r
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: selectedReminder == r
                              ? AppTheme.primary
                              : Colors.grey,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(r,
                              style: TextStyle(
                                fontSize: 12,
                                color: selectedReminder == r
                                    ? AppTheme.primary
                                    : AppTheme.textDark,
                                fontWeight: selectedReminder == r
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              )),
                        ),
                      ],
                    ),
                  ),
                )),
              ],
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text("Cancel", style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppTheme.buttonGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        if (selectedReminder == null) return;
                        Navigator.pop(ctx);
                        _sendMessageToStudent(student, selectedReminder!);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text("Send", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmMarkAsDone(Map<String, dynamic> student) {
    final commentController = TextEditingController();
    final source = student['source'] as String;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primarySoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.check_circle_outline, color: AppTheme.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Text("Mark as Done",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  "Mark ${student['name']}'s session as done.",
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 6),
                if (source == 'pa') ...[
                  Text(
                    "Leave a note for the PA.",
                    style: TextStyle(fontSize: 11, color: AppTheme.textGrey, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: commentController,
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: "e.g. Student showed improvement...",
                      hintStyle: TextStyle(fontSize: 11, color: AppTheme.textGrey),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.primary),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.primary.withOpacity(0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ] else
                  Text(
                    "No PA note needed for student-initiated request.",
                    style: TextStyle(fontSize: 11, color: AppTheme.textGrey, fontStyle: FontStyle.italic),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: const Text("Cancel", style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppTheme.buttonGradient,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            final comment = commentController.text.trim();
                            if (source == 'pa' && comment.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text("Please leave a note for the PA before confirming")),
                              );
                              return;
                            }
                            Navigator.pop(ctx);
                            _markAsDone(student, comment);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text("Confirm", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    );
  }

  // ── Write Progress Report to PA ──
  void _showProgressReportDialog(Map<String, dynamic> student) {
    final reportController = TextEditingController();
    final source = student['source'] as String;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E5F5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.edit_note, color: Color(0xFF7B1FA2), size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text("Write Progress Report",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "Write an observation for ${student['name']}. "
                  "${source == 'pa' ? 'PA will be notified.' : 'Logged for your records.'}",
                  style: TextStyle(fontSize: 11, color: AppTheme.textGrey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reportController,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: "e.g. Student showed progress...",
                    hintStyle: TextStyle(fontSize: 11, color: AppTheme.textGrey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF7B1FA2)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: const Color(0xFF7B1FA2).withOpacity(0.5)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF7B1FA2), width: 2),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        child: const Text("Cancel", style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final report = reportController.text.trim();
                          if (report.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text("Please write a progress report before submitting")),
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          _saveProgressReport(student, report);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7B1FA2),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text("Submit", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    );
  }

  Future<void> _saveProgressReport(Map<String, dynamic> student, String report) async {
    try {
      final studId = student['uitm_id'] as String;
      final source = student['source'] as String;
      final counsellorName = counsellorData?['fullName'] ?? 'Counsellor';
      final today = DateTime.now().toIso8601String().substring(0, 10);

      // Save progress report to Firestore
      await FirebaseFirestore.instance.collection('progressReports').add({
        'stud_id': studId,
        'counsellor_id': FirebaseAuth.instance.currentUser?.uid ?? '',
        'counsellor_name': counsellorName,
        'report': report,
        'report_date': today,
        'source': source,
        'created_at': FieldValue.serverTimestamp(),
      });

      // Notify PA if this was a PA referral
      if (source == 'pa') {
        final studentDoc = await FirebaseFirestore.instance.collection('students').doc(studId).get();
        final paName = studentDoc.data()?['paName'] as String?;

        if (paName != null) {
          final paQuery = await FirebaseFirestore.instance
              .collection('personalAdvisor')
              .where('fullName', isEqualTo: paName)
              .limit(1)
              .get();

          if (paQuery.docs.isNotEmpty) {
            final paPlayerId = paQuery.docs.first.data()['playerId'];
            final paUitmId = paQuery.docs.first.id;

            if (paPlayerId != null) {
              await NotificationService.sendPushNotification(
                playerIds: [paPlayerId],
                title: 'Progress Report from $counsellorName 📋',
                body: '${student['name']}: $report',
                type: 'progress_report',
                recipientUitmId: paUitmId,
              );
            }
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Progress report submitted for ${student['name']}"),
        backgroundColor: const Color(0xFF7B1FA2),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/',
      (route) => false, // clears the entire navigation stack
    );
  }

  void _onTabTapped(int index) {
    if (index == 0) return;
    setState(() => _currentIndex = index);
    final routes = {1: '/counsellorProfile'};
    if (routes.containsKey(index)) {
      Navigator.pushNamed(context, routes[index]!).then((_) {
        setState(() => _currentIndex = 0);
        loadCounsellorData();
      });
    }
  }

  Map<String, dynamic> thresholdStyle(String threshold) {
    switch (threshold) {
      case 'normal':
        return {'bg': const Color(0xFFE0F7F6), 'border': const Color(0xFF4DB6AC), 'dot': const Color(0xFF4DB6AC), 'label': 'Normal'};
      case 'moderate':
        return {'bg': const Color(0xFFFFF3E0), 'border': const Color(0xFFFFB74D), 'dot': const Color(0xFFFFB74D), 'label': 'Moderate'};
      case 'critical':
        return {'bg': const Color(0xFFFFEBEE), 'border': const Color(0xFFE57373), 'dot': const Color(0xFFE57373), 'label': 'Critical'};
      default:
        return {'bg': Colors.white, 'border': const Color(0xFFE2E8F0), 'dot': Colors.grey, 'label': 'New'};
    }
  }

  int get totalPending => pendingRequests.length + studentRequests.length;

  String get displayName {
    final fullName = counsellorData?['fullName'] ?? 'Counsellor';
    final parts = fullName.split(' ');
    for (int i = 0; i < parts.length; i++) {
      if (parts[i].toLowerCase() == 'bin' ||
          parts[i].toLowerCase() == 'binti' ||
          parts[i].toLowerCase() == 'bt' ||
          parts[i].toLowerCase() == 'bt.' ||
          parts[i].toLowerCase() == 'bin/binti') {
        return parts.sublist(0, i).join(' ');
      }
    }
    return parts.first;
  }

  Widget _notificationBellIcon() {
    if (counsellorId == null) {
      return IconButton(
        onPressed: () => Navigator.pushNamed(context, '/notifications'),
        icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 22),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notificationInbox')
          .where('recipient_id', isEqualTo: counsellorId)
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data?.docs.length ?? 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () => Navigator.pushNamed(context, '/notifications'),
              icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 22),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            if (unreadCount > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE57373),
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<bool> _onWillPop() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Log Out", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to log out?"),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text("Cancel", style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppTheme.buttonGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text("Log Out", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (result == true) {
      await logout();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final name = displayName;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onWillPop();
      },
      child: Scaffold(
      backgroundColor: AppTheme.background,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: Colors.grey,
        selectedFontSize: 11,
        unselectedFontSize: 10,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.people), label: "Students"),
          BottomNavigationBarItem(icon: Icon(Icons.manage_accounts), label: "Profile"),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Header ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Hello,", style: TextStyle(color: Colors.white70, fontSize: 14)),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "$name 👋",
                                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _notificationBellIcon(),
                              IconButton(
                                onPressed: () => _onWillPop(),
                                icon: const Icon(Icons.logout, color: Colors.white, size: 22),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _statCard(Icons.people, myStudents.length.toString(), "My Students"),
                        const SizedBox(width: 10),
                        _statCard(Icons.pending_actions, totalPending.toString(), "Pending"),
                        const SizedBox(width: 10),
                        _statCard(Icons.warning_amber_rounded,
                            myStudents.where((s) => s['threshold'] == 'critical').length.toString(), "Critical"),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── PA Referral Pending Requests ──
                    if (pendingRequests.isNotEmpty) ...[
                      _sectionHeader("REFERRED BY PA", pendingRequests.length),
                      const SizedBox(height: 12),
                      ...pendingRequests.map((r) => _buildPendingCard(r)),
                      const SizedBox(height: 20),
                    ],

                    // ── Student Direct Requests ──
                    if (studentRequests.isNotEmpty) ...[
                      _sectionHeader("STUDENT REQUESTS", studentRequests.length),
                      const SizedBox(height: 12),
                      ...studentRequests.map((r) => _buildStudentRequestCard(r)),
                      const SizedBox(height: 20),
                    ],

                    // ── My Students ──
                    Text("MY STUDENTS",
                        style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),

                    if (myStudents.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          children: [
                            Icon(Icons.people_outline, color: AppTheme.textGrey, size: 36),
                            const SizedBox(height: 8),
                            Text("No accepted students yet", style: TextStyle(color: AppTheme.textGrey)),
                          ],
                        ),
                      ),

                    ...myStudents.map((s) => _buildStudentCard(s)),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ],
          ),
        ),
      ), 
      )// Scaffold
    ); // PopScope
  }

  Widget _sectionHeader(String title, int count) {
    return Row(
      children: [
        Text(title, style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(10)),
          child: Text("$count", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFE57373))),
        ),
      ],
    );
  }

  // ── PA Referral Pending Card ──
  Widget _buildPendingCard(Map<String, dynamic> r) {
    final style = thresholdStyle(r['threshold'] as String);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.primarySoft,
                child: Text(r['name'].toString().split(' ').map((w) => w[0]).take(2).join(),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primary)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
                    Text("Referred by: ${r['pa_name']}", style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                    Text("Date: ${r['referral_date']}", style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                  ],
                ),
              ),
              if (r['threshold'] != 'none')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: style['dot'], borderRadius: BorderRadius.circular(8)),
                  child: Text(style['label'], style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: AppTheme.buttonGradient, borderRadius: BorderRadius.circular(10)),
                  child: ElevatedButton(
                    onPressed: () => _acceptRequest(r),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                        minimumSize: const Size(double.infinity, 40), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text("Accept", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _declineRequest(r),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40),
                      side: const BorderSide(color: Color(0xFFE57373)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text("Decline", style: TextStyle(color: Color(0xFFE57373), fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Student Direct Request Card ──
  Widget _buildStudentRequestCard(Map<String, dynamic> r) {
    final style = thresholdStyle(r['threshold'] as String);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.secondary.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.secondarySoft,
                child: Text(r['name'].toString().split(' ').map((w) => w[0]).take(2).join(),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.secondary)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
                    Text("Student request", style: TextStyle(fontSize: 11, color: AppTheme.secondary, fontWeight: FontWeight.w500)),
                    Text("Date: ${r['request_date']}", style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                  ],
                ),
              ),
              if (r['threshold'] != 'none')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: style['dot'], borderRadius: BorderRadius.circular(8)),
                  child: Text(style['label'], style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: AppTheme.buttonGradient, borderRadius: BorderRadius.circular(10)),
                  child: ElevatedButton(
                    onPressed: () => _acceptStudentRequest(r),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                        minimumSize: const Size(double.infinity, 40), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text("Accept", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _markUnavailable(r),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text("Unavailable",
                        style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold, fontSize: 13),
                        maxLines: 1),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Accepted Student Card with Mark as Done ──
  Widget _buildStudentCard(Map<String, dynamic> s) {
    final hasMood = s['hasMoodHistory'] as bool;
    final style = hasMood ? thresholdStyle(s['threshold']) : thresholdStyle('new');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: style['bg'],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (style['border'] as Color).withOpacity(0.4)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/counsellorStudentDetail',
                arguments: {...s, 'isFromCounsellor': true}),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.white,
                        child: Text(
                          s['name'].toString().split(' ').map((w) => w[0]).take(2).join(),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: style['dot']),
                        ),
                      ),
                      if (hasMood)
                        Positioned(
                          bottom: 0, right: 0,
                          child: Container(
                            width: 12, height: 12,
                            decoration: BoxDecoration(color: style['dot'], shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
                        const SizedBox(height: 2),
                        Text(hasMood ? "Last logged: ${s['lastLogged']}" : "No mood logs yet",
                            style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                        Text(
                          s['source'] == 'student' ? "🙋 Student request" : "📋 PA referral",
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.secondary),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (s['threshold'] != 'none') ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: style['dot'], borderRadius: BorderRadius.circular(8)),
                          child: Text(style['label'], style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 4),
                      ],
                      const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Schedule, Message, Unreachable buttons ──
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 14, bottom: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showScheduleDialog(s),
                        icon: const Icon(Icons.calendar_today, size: 14, color: AppTheme.secondary),
                        label: const Text("Schedule",
                            style: TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.w600, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppTheme.secondary.withOpacity(0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showSendMessageDialog(s),
                        icon: const Icon(Icons.notifications_outlined, size: 14, color: AppTheme.primary),
                        label: const Text("Remind",
                            style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppTheme.primary.withOpacity(0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (s['source'] == 'pa')
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showUnreachableDialog(s),
                    icon: const Icon(Icons.phone_missed, size: 14, color: Color(0xFFFFB74D)),
                    label: const Text("Report Unreachable",
                        style: TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.w600, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFFB74D)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (s['source'] == 'pa')
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showProgressReportDialog(s),
                    icon: const Icon(Icons.edit_note, size: 14, color: Color(0xFF7B1FA2)),
                    label: const Text("Write Progress Report",
                        style: TextStyle(color: Color(0xFF7B1FA2), fontWeight: FontWeight.w600, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF7B1FA2)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Mark as Done button ──
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 14, bottom: 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmMarkAsDone(s),
                icon: const Icon(Icons.check_circle_outline, size: 16, color: AppTheme.primary),
                label: const Text("Mark as Done",
                    style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppTheme.primary.withOpacity(0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            Text(label.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 9, letterSpacing: 0.8)),
          ],
        ),
      ),
    );
  }
}