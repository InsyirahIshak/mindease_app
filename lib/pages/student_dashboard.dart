import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mindease_app/theme/app_theme.dart';
import 'package:mindease_app/services/notification_service.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  Map<String, dynamic>? studentData;
  String? _studId;
  Map<String, dynamic>? paData;
  Map<String, dynamic>? todayMood;
  Map<String, dynamic>? latestStress;
  Map<String, dynamic>? counsellorData;
  List<Map<String, dynamic>> moodHistory = [];
  bool isLoading = true;
  int _currentIndex = 0;

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
    loadDashboardData();
  }

  Future<void> loadDashboardData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await NotificationService.checkAndScheduleMoodReminder();

      final studentQuery = await FirebaseFirestore.instance
          .collection('students')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (studentQuery.docs.isEmpty) return;

      final studDoc = studentQuery.docs.first;
      final studId = studDoc.id;
      _studId = studId;
      final data = studDoc.data();
      setState(() => studentData = data);

      final paName = data['paName'];
      if (paName != null && paName.toString().isNotEmpty) {
        final paQuery = await FirebaseFirestore.instance
            .collection('personalAdvisor')
            .where('fullName', isEqualTo: paName)
            .limit(1)
            .get();
        if (paQuery.docs.isNotEmpty) {
          setState(() => paData = paQuery.docs.first.data());
        }
      }

      final today = DateTime.now().toIso8601String().substring(0, 10);
      final moodQuery = await FirebaseFirestore.instance
          .collection('moodLogs')
          .where('stud_id', isEqualTo: studId)
          .where('log_date', isEqualTo: today)
          .limit(1)
          .get();

      if (moodQuery.docs.isNotEmpty) {
        setState(() => todayMood = moodQuery.docs.first.data());
      }

      final moodHistoryQuery = await FirebaseFirestore.instance
          .collection('moodLogs')
          .where('stud_id', isEqualTo: studId)
          .orderBy('log_date', descending: false)
          .get();

      setState(() {
        moodHistory = moodHistoryQuery.docs.map((d) => d.data()).toList();
      });

      final stressQuery = await FirebaseFirestore.instance
          .collection('stressAssessments')
          .where('stud_id', isEqualTo: studId)
          .orderBy('assessment_date', descending: true)
          .limit(1)
          .get();

      if (stressQuery.docs.isNotEmpty) {
        setState(() => latestStress = stressQuery.docs.first.data());
      }

      final referralQuery = await FirebaseFirestore.instance
          .collection('referrals')
          .where('stud_id', isEqualTo: studId)
          .where('status', isEqualTo: 'accepted')
          .limit(1)
          .get();

      if (referralQuery.docs.isNotEmpty) {
        final referralData = referralQuery.docs.first.data();
        if (referralData['done'] != true) {
          final counsellorId = referralData['counsellor_id'];
          final counsellorQuery = await FirebaseFirestore.instance
              .collection('counsellors')
              .doc(counsellorId)
              .get();
          if (counsellorQuery.exists) {
            setState(() => counsellorData = counsellorQuery.data());
          }
        }
      }

      if (counsellorData == null) {
        final directRequestQuery = await FirebaseFirestore.instance
            .collection('counsellorRequests')
            .where('stud_id', isEqualTo: studId)
            .where('status', isEqualTo: 'accepted')
            .limit(1)
            .get();

        if (directRequestQuery.docs.isNotEmpty) {
          final requestData = directRequestQuery.docs.first.data();
          if (requestData['done'] != true) {
            final counsellorId = requestData['counsellor_id'];
            final counsellorQuery = await FirebaseFirestore.instance
                .collection('counsellors')
                .doc(counsellorId)
                .get();
            if (counsellorQuery.exists) {
              setState(() => counsellorData = counsellorQuery.data());
            }
          }
        }
      }

    } catch (e) {
      print("Error loading dashboard: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ── Build last 7 days ending today for mini chart ──
  List<Map<String, dynamic>> get chartData {
    final now = DateTime.now();
    final moodMap = <String, int>{};
    for (final m in moodHistory) {
      moodMap[m['log_date'] as String] = m['mood_level'] as int;
    }

    // Always show last 7 days ending today
    final result = <Map<String, dynamic>>[];
    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dateStr = date.toIso8601String().substring(0, 10);
      result.add({
        'date': dateStr,
        'mood_level': moodMap[dateStr],
      });
    }
    return result;
  }

  bool get hasMoodHistory => moodHistory.isNotEmpty;

  // Weekly analysis shows if student has logged at least 1 mood in last 7 days
  bool get hasWeeklyData {
    final now = DateTime.now();
    final last7Dates = List.generate(7, (i) =>
      now.subtract(Duration(days: 6 - i)).toIso8601String().substring(0, 10));
    return moodHistory.any((m) => last7Dates.contains(m['log_date']));
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  void _onTabTapped(int index) {
    if (index == 0) return;
    setState(() => _currentIndex = index);
    final routes = {
      1: '/moodLogging',
      2: '/stressAssessment',
      3: '/moodTracking',
      4: '/counsellors',
    };
    if (routes.containsKey(index)) {
      Navigator.pushNamed(context, routes[index]!).then((_) {
        setState(() => _currentIndex = 0);
        loadDashboardData();
      });
    }
  }

  String get displayName {
    final fullName = studentData?['fullName'] ?? 'Student';
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
    if (_studId == null) {
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
          .where('recipient_id', isEqualTo: _studId)
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

  Map<String, dynamic> moodById(int value) =>
      moodMeta.firstWhere((m) => m['value'] == value, orElse: () => moodMeta[2]);

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
    final paName = studentData?['paName'] ?? 'Not assigned';
    final paPhone = paData?['phone'] ?? '';

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
            BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
            BottomNavigationBarItem(icon: Icon(Icons.sentiment_satisfied_alt), label: "Mood Log"),
            BottomNavigationBarItem(icon: Icon(Icons.monitor_heart), label: "Stress"),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Tracking"),
            BottomNavigationBarItem(icon: Icon(Icons.people), label: "Counsellors"),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
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
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.white,
                              child: Text(
                                paName.isNotEmpty ? paName[0].toUpperCase() : "P",
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primary),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("YOUR PERSONAL ADVISOR",
                                      style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1)),
                                  const SizedBox(height: 2),
                                  Text(paName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                  if (paPhone.isNotEmpty)
                                    Text(paPhone, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
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
                      _buildUpcomingSessionCard(),
                      todayMood == null ? _buildMoodInviteBox() : _buildTodayMoodBox(),
                      const SizedBox(height: 16),
                      if (counsellorData != null) ...[
                        _buildCounsellorBox(),
                        const SizedBox(height: 16),
                      ],
                      if (hasMoodHistory) ...[
                        _buildMiniMoodChart(),
                        const SizedBox(height: 12),
                      ],
                      if (hasWeeklyData) ...[
                        _buildDashboardAnalysisSummary(),
                        const SizedBox(height: 16),
                      ],
                      _buildStressBox(),
                      const SizedBox(height: 16),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ), // Scaffold
    ); // PopScope
  }

  Widget _buildUpcomingSessionCard() {
    if (_studId == null) return const SizedBox();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sessionSchedules')
          .where('stud_id', isEqualTo: _studId)
          .where('status', isEqualTo: 'scheduled')
          .orderBy('scheduled_at', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox();
        final doc = snapshot.data!.docs.first;
        final data = doc.data() as Map<String, dynamic>;
        final acknowledged = data['acknowledged'] == true;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.secondary.withOpacity(0.15), AppTheme.secondary.withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.secondary.withOpacity(0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.event_available, color: AppTheme.secondary, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text("Upcoming Session",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondary)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text("Your counsellor has scheduled a session with you.",
                    style: TextStyle(fontSize: 13, color: AppTheme.textDark, height: 1.4)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 14, color: AppTheme.textGrey),
                    const SizedBox(width: 6),
                    Text("${data['session_date']}", style: TextStyle(fontSize: 12, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 14),
                    const Icon(Icons.access_time, size: 14, color: AppTheme.textGrey),
                    const SizedBox(width: 6),
                    Text("${data['session_time']}", style: TextStyle(fontSize: 12, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                if (acknowledged)
                  Row(
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: AppTheme.secondary),
                      const SizedBox(width: 6),
                      Text("Acknowledged", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.secondary)),
                    ],
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _acknowledgeSession(doc.id),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: const Text("Got it 👍", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _acknowledgeSession(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('sessionSchedules')
          .doc(docId)
          .update({'acknowledged': true, 'acknowledged_at': FieldValue.serverTimestamp()});
      final scheduleDoc = await FirebaseFirestore.instance.collection('sessionSchedules').doc(docId).get();
      final counsellorId = scheduleDoc.data()?['counsellor_id'] as String?;
      if (counsellorId != null) {
        final counsellorDoc = await FirebaseFirestore.instance.collection('counsellors').doc(counsellorId).get();
        final counsellorPlayerId = counsellorDoc.data()?['playerId'];
        if (counsellorPlayerId != null) {
          final studentName = studentData?['fullName'] ?? 'Student';
          await NotificationService.sendPushNotification(
            playerIds: [counsellorPlayerId],
            title: 'Session Acknowledged ✅',
            body: '$studentName has confirmed the scheduled session.',
            type: 'session_acknowledged',
            recipientUitmId: counsellorId,
          );
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Thanks for confirming!"),
        backgroundColor: AppTheme.secondary,
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Widget _buildMoodInviteBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          const Text("🌤️", style: TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          const Text("How are you feeling today?",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text("Log your mood to track your mental wellbeing",
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(gradient: AppTheme.buttonGradient, borderRadius: BorderRadius.circular(12)),
            child: ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/moodLogging').then((_) => loadDashboardData()),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Log My Mood", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayMoodBox() {
    final moodLevel = todayMood!['mood_level'] as int? ?? 3;
    final mood = moodById(moodLevel);
    final date = todayMood!['log_date'] ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Text(mood['emoji'], style: const TextStyle(fontSize: 36)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("TODAY'S MOOD",
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(mood['label'],
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: mood['color'])),
                ),
                const SizedBox(height: 2),
                Text(date, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: AppTheme.textGrey)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(color: AppTheme.secondarySoft, borderRadius: BorderRadius.circular(10)),
            child: Text("Logged ✓",
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.secondary)),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMoodChart() {
    final data = chartData;
    final spots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      final moodLevel = data[i]['mood_level'];
      if (moodLevel != null) {
        spots.add(FlSpot(i.toDouble(), (moodLevel as int).toDouble()));
      }
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("MOOD THIS WEEK",
                  style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/moodTracking'),
                child: Text("View all →",
                    style: TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: LineChart(
              LineChartData(
                minY: 1, maxY: 5, minX: 0, maxX: 6,
                gridData: FlGridData(
                  show: true, drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(color: const Color(0xFFE8EDF2), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, interval: 1,
                      getTitlesWidget: (value, meta) {
                        final m = moodMeta.firstWhere(
                          (m) => m['value'] == value.toInt(),
                          orElse: () => {'emoji': ''},
                        );
                        return Text(m['emoji'] ?? '', style: const TextStyle(fontSize: 10));
                      },
                      reservedSize: 24,
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= 0 && index < data.length) {
                          final date = data[index]['date'].toString().substring(5);
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(date, style: TextStyle(fontSize: 8, color: AppTheme.textGrey)),
                          );
                        }
                        return const Text('');
                      },
                      reservedSize: 20,
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final mood = moodById(spot.y.toInt());
                        return LineTooltipItem(
                          '${mood['emoji']} ${mood['label']}',
                          const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: spots.isEmpty ? [] : [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppTheme.primary,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, pct, bar, index) => FlDotCirclePainter(
                        radius: 4, color: AppTheme.secondary, strokeWidth: 2, strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [AppTheme.primary.withOpacity(0.2), AppTheme.primary.withOpacity(0.0)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardAnalysisSummary() {
    if (_studId == null) return const SizedBox();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('moodAnalysis')
          .where('stud_id', isEqualTo: _studId)
          .where('type', isEqualTo: 'weekly')
          .orderBy('analysis_date', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        String? threshold;
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
          threshold = data['risk_level'] as String?;
        }
        if (threshold == null) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                const Text("📊", style: TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Weekly Analysis",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                      Text("Log mood for 7 days to get your analysis",
                          style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        Color thresholdColor() {
          switch (threshold) {
            case 'Normal': return const Color(0xFF4DB6AC);
            case 'Moderate': return const Color(0xFFFFB74D);
            case 'Critical': return const Color(0xFFE57373);
            default: return Colors.grey;
          }
        }
        Color thresholdBg() {
          switch (threshold) {
            case 'Normal': return const Color(0xFFE0F7F6);
            case 'Moderate': return const Color(0xFFFFF3E0);
            case 'Critical': return const Color(0xFFFFEBEE);
            default: return const Color(0xFFF0F0F0);
          }
        }
        String thresholdEmoji() {
          switch (threshold) {
            case 'Normal': return '😊';
            case 'Moderate': return '😐';
            case 'Critical': return '😟';
            default: return '❓';
          }
        }
        String thresholdSentence() {
          switch (threshold) {
            case 'Normal': return 'Your mood has been positive this week. Keep it up!';
            case 'Moderate': return 'Your mood has been mixed. Consider taking time to relax.';
            case 'Critical': return 'Your mood has been low. Please consider reaching out for support.';
            default: return '';
          }
        }
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: thresholdBg(),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: thresholdColor().withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Text(thresholdEmoji(), style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Weekly Analysis: $threshold",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: thresholdColor())),
                    Text(thresholdSentence(),
                        style: const TextStyle(fontSize: 11, color: AppTheme.textDark, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStressBox() {
    if (latestStress == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.monitor_heart, color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("DASS-21 Assessment",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
                  Text("No score yet — take your weekly assessment",
                      style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final depScore = latestStress!['depression_score'] ?? 0;
    final depLevel = latestStress!['depression_level'] ?? '-';
    final anxScore = latestStress!['anxiety_score'] ?? 0;
    final anxLevel = latestStress!['anxiety_level'] ?? '-';
    final strScore = latestStress!['stress_score'] ?? 0;
    final strLevel = latestStress!['stress_level'] ?? '-';
    final date = latestStress!['assessment_date'] ?? '-';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("DASS-21 Assessment",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
              Text(date, style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
            ],
          ),
          const SizedBox(height: 12),
          _dashboardScoreRow("Depression", depScore, depLevel),
          const SizedBox(height: 8),
          _dashboardScoreRow("Anxiety", anxScore, anxLevel),
          const SizedBox(height: 8),
          _dashboardScoreRow("Stress", strScore, strLevel),
        ],
      ),
    );
  }

  Widget _dashboardScoreRow(String category, int score, String level) {
    Color levelColor() {
      switch (level) {
        case 'Normal': return const Color(0xFF4DB6AC);
        case 'Mild': return const Color(0xFF81C784);
        case 'Moderate': return const Color(0xFFFFB74D);
        case 'Severe': return const Color(0xFFFF7043);
        default: return const Color(0xFFE57373);
      }
    }
    Color levelBg() {
      switch (level) {
        case 'Normal': return const Color(0xFFE0F7F6);
        case 'Mild': return const Color(0xFFE8F5E9);
        case 'Moderate': return const Color(0xFFFFF3E0);
        case 'Severe': return const Color(0xFFFBE9E7);
        default: return const Color(0xFFFFEBEE);
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: levelBg(), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("$category ($level)",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: levelColor())),
          Text("$score", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: levelColor())),
        ],
      ),
    );
  }

  Widget _buildCounsellorBox() {
    final counsellorName = counsellorData?['fullName'] ?? 'Your Counsellor';
    final counsellorPhone = counsellorData?['phone'] ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.secondary.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppTheme.secondarySoft,
            child: Text(counsellorName[0].toUpperCase(),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.secondary)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("YOUR COUNSELLOR",
                    style: TextStyle(color: AppTheme.secondary, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(counsellorName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark)),
                if (counsellorPhone.isNotEmpty)
                  Text(counsellorPhone, style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}