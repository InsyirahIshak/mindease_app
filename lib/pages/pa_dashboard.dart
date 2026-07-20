import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mindease_app/theme/app_theme.dart';

class PADashboard extends StatefulWidget {
  const PADashboard({super.key});

  @override
  State<PADashboard> createState() => _PADashboardState();
}

class _PADashboardState extends State<PADashboard> {
  Map<String, dynamic>? paData;
  String? paUitmId;
  bool isLoading = true;
  int _currentIndex = 0;
  String _searchQuery = '';
  String _filterBy = 'all';
  List<Map<String, dynamic>> _students = [];

  @override
  void initState() {
    super.initState();
    loadPAData();
  }

  Future<void> loadPAData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final paQuery = await FirebaseFirestore.instance
          .collection('personalAdvisor')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (paQuery.docs.isEmpty) return;

      paUitmId = paQuery.docs.first.id;
      setState(() => paData = paQuery.docs.first.data());

      await _loadStudents();

    } catch (e) {
      print("Error loading PA data: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ── Loads the basic student LIST (names, semester, etc) ──
  // Threshold and referral status are now handled live via StreamBuilder
  // in _buildStudentCard(), so this only needs to load once.
  Future<void> _loadStudents() async {
    try {
      final paName = paData?['fullName'] ?? '';

      final studentQuery = await FirebaseFirestore.instance
          .collection('students')
          .where('paName', isEqualTo: paName)
          .get();

      List<Map<String, dynamic>> studentsWithMood = [];

      for (var doc in studentQuery.docs) {
        final studentData = doc.data();
        final studId = doc.id;

        // Get latest mood log (static fetch is fine — last logged date
        // doesn't need second-by-second sync)
        final moodQuery = await FirebaseFirestore.instance
            .collection('moodLogs')
            .where('stud_id', isEqualTo: studId)
            .orderBy('log_date', descending: true)
            .limit(1)
            .get();

        bool hasMoodHistory = false;
        String lastLogged = 'No logs yet';

        if (moodQuery.docs.isNotEmpty) {
          hasMoodHistory = true;
          lastLogged = moodQuery.docs.first.data()['log_date'] ?? '-';
        }

        studentsWithMood.add({
          'uitm_id': studId,
          'name': studentData['fullName'] ?? '-',
          'phone': studentData['phone'] ?? '-',
          'email': studentData['email'] ?? '-',
          'gender': studentData['stud_gender'] ?? studentData['gender'] ?? '-',
          'semester': studentData['stud_semester'] ?? studentData['semester'] ?? '-',
          'hasMoodHistory': hasMoodHistory,
          'lastLogged': lastLogged,
          'studentName': studentData['fullName'] ?? '-',
        });
      }

      setState(() => _students = studentsWithMood);

    } catch (e) {
      print("Error loading students: $e");
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

  void _confirmLogout() {
    showDialog(
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
                      Navigator.pop(ctx);
                      logout();
                    },
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
  }

  List<Map<String, dynamic>> get filteredStudents {
    List<Map<String, dynamic>> result = _students;

    if (_searchQuery.isNotEmpty) {
      result = result
          .where((s) => s['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    // Note: filter by threshold is now done live within the stream;
    // here we just keep the search-filtered list and let each
    // StreamBuilder decide its own visual badge. Sorting by name only.
    return result;
  }

  int get totalStudents => _students.length;

  Map<String, dynamic> thresholdStyle(String threshold) {
    switch (threshold) {
      case 'normal':
        return {
          'bg': const Color(0xFFE0F7F6),
          'border': const Color(0xFF4DB6AC),
          'dot': const Color(0xFF4DB6AC),
          'label': 'Normal',
        };
      case 'moderate':
        return {
          'bg': const Color(0xFFFFF3E0),
          'border': const Color(0xFFFFB74D),
          'dot': const Color(0xFFFFB74D),
          'label': 'Moderate',
        };
      case 'critical':
        return {
          'bg': const Color(0xFFFFEBEE),
          'border': const Color(0xFFE57373),
          'dot': const Color(0xFFE57373),
          'label': 'Critical',
        };
      default:
        return {
          'bg': Colors.white,
          'border': const Color(0xFFE2E8F0),
          'dot': Colors.grey,
          'label': 'New',
        };
    }
  }

  void _onTabTapped(int index) {
    if (index == 0) return;
    setState(() => _currentIndex = index);
    final routes = {
      1: '/paCounsellors',
      2: '/paProfile',
    };
    if (routes.containsKey(index)) {
      Navigator.pushNamed(context, routes[index]!).then((_) {
        setState(() => _currentIndex = 0);
        _loadStudents(); // refresh student list (names) when returning
      });
    }
  }

  String get displayName {
    final fullName = paData?['fullName'] ?? 'Personal Advisor';
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
    if (paUitmId == null) {
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
          .where('recipient_id', isEqualTo: paUitmId)
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
            BottomNavigationBarItem(icon: Icon(Icons.local_hospital), label: "Counsellors"),
            BottomNavigationBarItem(icon: Icon(Icons.manage_accounts), label: "Profile"),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
          onRefresh: _loadStudents,
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
                                  onPressed: () => _confirmLogout(),
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

                      // ── Live Stats (real-time count via stream) ──
                      _buildLiveStats(),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Search + Filter ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search, color: Colors.grey, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                onChanged: (val) => setState(() => _searchQuery = val),
                                decoration: const InputDecoration(
                                  hintText: "Search students...",
                                  border: InputBorder.none,
                                  hintStyle: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterChip('all', 'All', Colors.grey),
                            const SizedBox(width: 8),
                            _filterChip('critical', 'Critical', const Color(0xFFE57373)),
                            const SizedBox(width: 8),
                            _filterChip('moderate', 'Moderate', const Color(0xFFFFB74D)),
                            const SizedBox(width: 8),
                            _filterChip('normal', 'Normal', const Color(0xFF4DB6AC)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Students List (each card is real-time) ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("MY STUDENTS",
                          style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),

                      if (filteredStudents.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                          child: Column(
                            children: [
                              Icon(Icons.people_outline, color: AppTheme.textGrey, size: 36),
                              const SizedBox(height: 8),
                              Text(
                                _students.isEmpty ? "No students assigned yet" : "No students found",
                                style: TextStyle(color: AppTheme.textGrey),
                              ),
                            ],
                          ),
                        ),

                      ...filteredStudents.map((s) => _buildStudentCard(s)),
                    ],
                  ),
                ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ), // SafeArea
      ), // Scaffold
    ); // PopScope
  }

  // ── Live aggregate stats using a stream over moodAnalysis for all students ──
  Widget _buildLiveStats() {
    if (_students.isEmpty) {
      return Row(
        children: [
          _statCard(Icons.people, "0", "Students"),
          const SizedBox(width: 10),
          _statCard(Icons.warning_amber_rounded, "0", "Critical"),
          const SizedBox(width: 10),
          _statCard(Icons.trending_up, "0", "Referred"),
        ],
      );
    }

    final studIds = _students.map((s) => s['uitm_id'] as String).toList();

    return StreamBuilder<QuerySnapshot>(
      // Listen to referrals for this PA's students
      stream: FirebaseFirestore.instance
          .collection('referrals')
          .where('pa_id', isEqualTo: paUitmId)
          .snapshots(),
      builder: (context, referralSnapshot) {
        int referredCount = 0;
        if (referralSnapshot.hasData) {
          final activeStatuses = {'pending', 'accepted', 'done'};
          // Count unique students with an active referral
          final referredIds = <String>{};
          for (var doc in referralSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (activeStatuses.contains(data['status'])) {
              referredIds.add(data['stud_id'] as String);
            }
          }
          referredCount = referredIds.length;
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('moodAnalysis')
              .where('stud_id', whereIn: studIds.length > 10 ? studIds.sublist(0, 10) : studIds)
              .where('type', isEqualTo: 'weekly')
              .snapshots(),
          builder: (context, analysisSnapshot) {
            int criticalCount = 0;
            if (analysisSnapshot.hasData) {
              // Keep only the latest analysis per student
              final latestByStudent = <String, Map<String, dynamic>>{};
              for (var doc in analysisSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final studId = data['stud_id'] as String;
                final date = data['analysis_date'] as String? ?? '';
                if (!latestByStudent.containsKey(studId) ||
                    (latestByStudent[studId]!['analysis_date'] as String? ?? '').compareTo(date) < 0) {
                  latestByStudent[studId] = data;
                }
              }
              criticalCount = latestByStudent.values
                  .where((d) => (d['risk_level']?.toString().toLowerCase()) == 'critical')
                  .length;
            }

            return Row(
              children: [
                _statCard(Icons.people, totalStudents.toString(), "Students"),
                const SizedBox(width: 10),
                _statCard(Icons.warning_amber_rounded, criticalCount.toString(), "Critical"),
                const SizedBox(width: 10),
                _statCard(Icons.trending_up, referredCount.toString(), "Referred"),
              ],
            );
          },
        );
      },
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

  Widget _filterChip(String value, String label, Color color) {
    final isSelected = _filterBy == value;
    return GestureDetector(
      onTap: () => setState(() => _filterBy = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : AppTheme.textGrey)),
      ),
    );
  }

  // ── Real-time student card: listens to moodAnalysis + referrals live ──
  Widget _buildStudentCard(Map<String, dynamic> s) {
    final studId = s['uitm_id'] as String;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('moodAnalysis')
          .where('stud_id', isEqualTo: studId)
          .where('type', isEqualTo: 'weekly')
          .orderBy('analysis_date', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, analysisSnapshot) {
        String threshold = 'none';
        if (analysisSnapshot.hasData && analysisSnapshot.data!.docs.isNotEmpty) {
          final data = analysisSnapshot.data!.docs.first.data() as Map<String, dynamic>;
          threshold = data['risk_level']?.toString().toLowerCase() ?? 'none';
        }

        // Apply threshold filter here (since it's now live)
        if (_filterBy != 'all' && threshold != _filterBy) {
          return const SizedBox.shrink();
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('referrals')
              .where('stud_id', isEqualTo: studId)
              .orderBy('referral_date', descending: true)
              .limit(1)
              .snapshots(),
          builder: (context, referralSnapshot) {
            String? referralStatus;
            if (referralSnapshot.hasData && referralSnapshot.data!.docs.isNotEmpty) {
              final data = referralSnapshot.data!.docs.first.data() as Map<String, dynamic>;
              referralStatus = data['status'] as String?;
            }

            final hasMood = s['hasMoodHistory'] as bool;
            final style = hasMood ? thresholdStyle(threshold) : thresholdStyle('new');

            // Check if done today
            String? doneDate;
            bool isDoneToday = false;
            if (referralSnapshot.hasData && referralSnapshot.data!.docs.isNotEmpty) {
              final data = referralSnapshot.data!.docs.first.data() as Map<String, dynamic>;
              doneDate = data['done_date'] as String?;
              final today = DateTime.now().toIso8601String().substring(0, 10);
              isDoneToday = referralStatus == 'done' && doneDate == today;
            }

            final liveIsReferred = referralStatus == 'pending' || referralStatus == 'accepted' || isDoneToday;
            final cardBg = isDoneToday
                ? const Color(0xFFE3F2FD) // blue for done today
                : liveIsReferred && referralStatus != 'done'
                    ? AppTheme.primarySoft
                    : style['bg'];
            final cardBorder = isDoneToday
                ? const Color(0xFF64B5F6)
                : liveIsReferred && referralStatus != 'done'
                    ? AppTheme.primary.withOpacity(0.3)
                    : (style['border'] as Color).withOpacity(0.4);

            return GestureDetector(
              onTap: () => Navigator.pushNamed(
                context,
                '/paStudentDetail',
                arguments: {...s, 'threshold': threshold, 'referralStatus': referralStatus},
              ),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder),
                ),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.white,
                          child: Text(
                            s['name'].toString().split(' ').map((w) => w[0]).take(2).join(),
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDoneToday ? const Color(0xFF1565C0) : liveIsReferred && referralStatus != 'done' ? AppTheme.primary : style['dot']),
                          ),
                        ),
                        if (hasMood)
                          Positioned(
                            bottom: 0, right: 0,
                            child: Container(
                              width: 12, height: 12,
                              decoration: BoxDecoration(
                                color: liveIsReferred ? AppTheme.primary : style['dot'],
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
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
                          Text(
                            hasMood ? "Last logged: ${s['lastLogged']}" : "No mood logs yet",
                            style: TextStyle(fontSize: 11, color: AppTheme.textGrey),
                          ),
                          if (referralStatus != null)
                            Text(
                              referralStatus == 'accepted'
                                  ? "✓ Counsellor accepted"
                                  : referralStatus == 'pending'
                                      ? "⏳ Pending counsellor"
                                      : isDoneToday
                                          ? "✅ Session completed"
                                          : "",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: referralStatus == 'accepted'
                                    ? AppTheme.secondary
                                    : isDoneToday
                                        ? const Color(0xFF1565C0)
                                        : const Color(0xFFFFB74D),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (threshold != 'none') ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: liveIsReferred ? AppTheme.primary : style['dot'],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              liveIsReferred ? "Referred" : style['label'],
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}