import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mindease_app/theme/app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:http/http.dart' as http;
import 'dart:convert';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  Map<String, dynamic>? adminData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAdminData();
  }

  Future<void> _loadAdminData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final query = await FirebaseFirestore.instance
          .collection('admins')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        setState(() => adminData = query.docs.first.data());
      }
    } catch (e) {
      print("Error loading admin: $e");
    } finally {
      setState(() => isLoading = false);
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final name = (adminData?['fullName'] ?? 'Admin').toString().split(' ').first;

    final pages = [
      _UsersPage(),
      _RelaxationContentPage(),
      _ReferralPage(),
    ];

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
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: Colors.grey,
        selectedFontSize: 11,
        unselectedFontSize: 10,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: "Users",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.spa),
            label: "Content",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.swap_horiz),
            label: "Referrals",
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [

            // ── Header ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              decoration: const BoxDecoration(
                gradient: AppTheme.headerGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Hello,",
                          style: TextStyle(
                              color: Colors.white70, fontSize: 14)),
                      Text("$name 👋",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          )),
                      const SizedBox(height: 4),
                      const Text(
                        "Admin Panel",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed:  () => _confirmLogout(),
                    icon: const Icon(Icons.logout, color: Colors.white),
                
                  ),
                ],
              ),
            ),

            // ── Page Content ──
            Expanded(child: pages[_currentIndex]),
          ],
        ),
      ),
       ) // Scaffold
    ); // PopScope
  }
}

// ══════════════════════════════════════════
// ── USERS PAGE ──
// ══════════════════════════════════════════
class _UsersPage extends StatefulWidget {
  @override
  State<_UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<_UsersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isImporting = false;
  String _importStatus = '';
  int _importSuccess = 0;
  int _importSkipped = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _bulkImport() async {
    try {
      // Pick Excel file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final fileName = result.files.first.name.toLowerCase();
      if (!fileName.endsWith('.csv') && !fileName.endsWith('.xlsx') && !fileName.endsWith('.xls')) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please select a CSV or Excel file (.csv, .xlsx, .xls)"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (result.files.first.bytes == null) return;

      setState(() {
        _isImporting = true;
        _importStatus = 'Reading file...';
        _importSuccess = 0;
        _importSkipped = 0;
      });

      final bytes = result.files.first.bytes;
      if (bytes == null) {
        print("DEBUG: File bytes is null!");
        setState(() => _isImporting = false);
        return;
      }

      print("DEBUG: File bytes loaded, size=${bytes.length}");

      setState(() {
        _isImporting = true;
        _importStatus = 'Reading file...';
        _importSuccess = 0;
        _importSkipped = 0;
      });

      int totalSuccess = 0;
      int totalSkipped = 0;

      // ── Parse rows from CSV or Excel ──
      List<List<String>> allRows = [];

      if (fileName.endsWith('.csv')) {
        // Parse CSV
        final csvString = String.fromCharCodes(bytes);
        final lines = csvString.split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          allRows.add(line.split(',').map((e) => e.trim()).toList());
        }
        print("DEBUG: CSV parsed, rows=${allRows.length}");
      } else {
        // Parse Excel
        try {
          final excel = Excel.decodeBytes(bytes);
          print("DEBUG: Excel decoded, sheets=${excel.tables.keys.toList()}");
          final sheetName = excel.tables.keys.first;
          final sheet = excel.tables[sheetName]!;
          for (final row in sheet.rows) {
            allRows.add(row.map((c) {
              if (c == null || c.value == null) return '';
              final str = c.value.toString().trim();
              return str.endsWith('.0') ? str.substring(0, str.length - 2) : str;
            }).toList());
          }
          print("DEBUG: Excel rows parsed=${allRows.length}");
        } catch (e) {
          print("DEBUG: Excel decode failed: $e");
          setState(() => _isImporting = false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Cannot read Excel file. Please use CSV format (.csv) instead."),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
          return;
        }
      }

      if (allRows.isEmpty) {
        setState(() => _isImporting = false);
        return;
      }

      // Get headers from first row
      final headers = allRows.first.map((h) => h.toLowerCase()).toList();
      print("DEBUG: Headers=$headers");

      final docIdIndex = headers.indexWhere((h) => h.contains('document') || h == 'id');
      final fullNameIndex = headers.indexWhere((h) => h.contains('fullname') || h.contains('full name'));
      final roleIndex = headers.indexWhere((h) => h == 'role');
      final paNameIndex = headers.indexWhere((h) => h.contains('paname') || h.contains('pa name'));
      final positionIndex = headers.indexWhere((h) => h.contains('position'));

      print("DEBUG: docIdIndex=$docIdIndex, fullNameIndex=$fullNameIndex, roleIndex=$roleIndex, paNameIndex=$paNameIndex");

      if (docIdIndex == -1 || fullNameIndex == -1 || roleIndex == -1) {
        setState(() => _isImporting = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Missing required columns: Document ID, fullName, role")),
        );
        return;
      }

      // Process data rows (skip header)
      for (int i = 1; i < allRows.length; i++) {
        try {
          final row = allRows[i];
          if (row.isEmpty || row.every((e) => e.isEmpty)) { totalSkipped++; continue; }

          String getVal(int idx) {
            if (idx < 0 || idx >= row.length) return '';
            return row[idx].trim();
          }

          final docId = getVal(docIdIndex);
          final fullName = getVal(fullNameIndex);
          final role = getVal(roleIndex);

          if (docId.isEmpty || fullName.isEmpty || role.isEmpty) { totalSkipped++; continue; }

          String collection;
          if (role.toLowerCase().contains('student')) {
            collection = 'students';
          } else if (role.toLowerCase().contains('personal advisor') || role.toLowerCase().contains('pa')) {
            collection = 'personalAdvisor';
          } else if (role.toLowerCase().contains('counsellor')) {
            collection = 'counsellors';
          } else if (role.toLowerCase().contains('admin')) {
            collection = 'admins';
          } else { totalSkipped++; continue; }

          final Map<String, dynamic> data = {
            'fullName': fullName,
            'role': role,
            'email': '',
            'phone': '',
          };

          if (paNameIndex >= 0) {
            final paName = getVal(paNameIndex);
            if (paName.isNotEmpty) data['paName'] = paName;
          }

          if (positionIndex >= 0) {
            final position = getVal(positionIndex);
            if (position.isNotEmpty) data['position'] = position;
          }

          await FirebaseFirestore.instance.collection(collection).doc(docId).set(data);
          totalSuccess++;
          setState(() => _importStatus = 'Imported $totalSuccess records...');
          print("DEBUG: Imported $docId — $fullName");
        } catch (rowError) {
          print("DEBUG: Row $i error: $rowError");
          totalSkipped++;
        }
      }

      setState(() {
        _isImporting = false;
        _importSuccess = totalSuccess;
        _importSkipped = totalSkipped;
        _importStatus = 'Import complete!';
      });

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text("🎉", style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text("Import Complete!",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("✅ $totalSuccess records imported successfully",
                style: TextStyle(color: AppTheme.secondary)),
            if (totalSkipped > 0)
              Text("⚠️ $totalSkipped rows skipped (missing data)",
                  style: const TextStyle(color: Colors.orange)),
          ]),
          actions: [
            Center(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                child: const Text("Done", style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    } catch (e) {
      setState(() {
        _isImporting = false;
        _importStatus = 'Error: $e';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Import failed: ${e.toString().replaceAll('Exception: ', '')}"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Bulk Import Button — scrollable ──
        SingleChildScrollView(
          child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _isImporting
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LinearProgressIndicator(
                                backgroundColor: AppTheme.primarySoft,
                                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                              ),
                              const SizedBox(height: 4),
                              Text(_importStatus,
                                  style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                            ],
                          )
                        : _importStatus == 'Import complete!'
                            ? Row(children: [
                                Icon(Icons.check_circle, color: AppTheme.secondary, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text("$_importSuccess imported, $_importSkipped skipped",
                                      style: TextStyle(fontSize: 11, color: AppTheme.secondary)),
                                ),
                              ])
                            : const SizedBox(),
                  ),
                  const SizedBox(width: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppTheme.buttonGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _isImporting ? null : _bulkImport,
                      icon: const Icon(Icons.upload_file, color: Colors.white, size: 16),
                      label: const Text("Import Student Data",
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 12, color: AppTheme.textGrey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      "File must be in Excel (.xlsx) or CSV (.csv) format with columns: Document ID, fullName, role, and paName (for students).",
                      style: TextStyle(fontSize: 10, color: AppTheme.textGrey, height: 1.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ), // SingleChildScrollView

        // Tab bar
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textGrey,
            indicatorColor: AppTheme.primary,
            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            tabs: const [
              Tab(text: "Students"),
              Tab(text: "PA"),
              Tab(text: "Counsellor"),
            ],
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _UserList(collection: 'students', roleLabel: 'Student'),
              _UserList(collection: 'personalAdvisor', roleLabel: 'Personal Advisor'),
              _UserList(collection: 'counsellors', roleLabel: 'Counsellor'),
            ],
          ),
        ),
      ],
    );
  }
}

class _UserList extends StatefulWidget {
  final String collection;
  final String roleLabel;

  const _UserList({
    required this.collection,
    required this.roleLabel,
  });

  @override
  State<_UserList> createState() => _UserListState();
}

class _UserListState extends State<_UserList> {
  String _searchQuery = '';

  void _confirmDelete(BuildContext context, String docId, String name, String collection) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Remove User?",
            style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark)),
        content: Text(
          "Are you sure you want to remove $name (ID: $docId) from the system? This action cannot be undone.",
          style: const TextStyle(color: AppTheme.textGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseFirestore.instance.collection(collection).doc(docId).delete();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("$name removed successfully"),
                    backgroundColor: const Color(0xFFE57373),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error: $e")),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE57373)),
            child: const Text("Remove", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Search Bar ──
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.grey, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                    decoration: InputDecoration(
                      hintText: "Search ${widget.roleLabel}...",
                      border: InputBorder.none,
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── User List ──
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection(widget.collection)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, color: AppTheme.textGrey, size: 48),
                      const SizedBox(height: 12),
                      Text("No ${widget.roleLabel} found",
                          style: TextStyle(color: AppTheme.textGrey)),
                    ],
                  ),
                );
              }

              // Filter by search query
              final docs = snapshot.data!.docs.where((doc) {
                if (_searchQuery.isEmpty) return true;
                final data = doc.data() as Map<String, dynamic>;
                final name = (data['fullName'] ?? '').toString().toLowerCase();
                final id = doc.id.toLowerCase();
                final email = (data['email'] ?? '').toString().toLowerCase();
                return name.contains(_searchQuery) ||
                    id.contains(_searchQuery) ||
                    email.contains(_searchQuery);
              }).toList();

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("🔍", style: TextStyle(fontSize: 36)),
                      const SizedBox(height: 8),
                      Text("No results for \"$_searchQuery\"",
                          style: TextStyle(color: AppTheme.textGrey)),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final docId = docs[index].id;
                  final name = data['fullName'] ?? '-';
                  final email = data['email'] ?? '-';
                  final phone = data['phone'] ?? '-';
                  final isRegistered = data['uid'] != null;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
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
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: isRegistered
                              ? AppTheme.primarySoft
                              : const Color(0xFFF0F0F0),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isRegistered ? AppTheme.primary : Colors.grey,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppTheme.textDark,
                                ),
                              ),
                              Text("ID: $docId",
                                  style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                              if (email.isNotEmpty && email != '-')
                                Text(email,
                                    style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                              if (phone.isNotEmpty && phone != '-')
                                Text(phone,
                                    style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isRegistered
                                ? AppTheme.secondarySoft
                                : const Color(0xFFF0F0F0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isRegistered ? "Registered" : "Pending",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isRegistered ? AppTheme.secondary : Colors.grey,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _confirmDelete(context, docId, name, widget.collection),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEBEE),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.delete_outline, color: Color(0xFFE57373), size: 16),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════
// ── RELAXATION CONTENT PAGE ──
// ══════════════════════════════════════════
class _RelaxationContentPage extends StatefulWidget {
  @override
  State<_RelaxationContentPage> createState() =>
      _RelaxationContentPageState();
}

class _RelaxationContentPageState extends State<_RelaxationContentPage> {
  String _selectedType = 'quote';
  String _selectedRiskLevel = 'all';
  final _contentController = TextEditingController();
  bool _isSaving = false;
  bool _isSendingDass = false;
  bool _breakMode = false;
  bool _loadingBreakMode = true;

  @override
  void initState() {
    super.initState();
    _loadBreakMode();
  }

  Future<void> _loadBreakMode() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('systemSettings')
          .doc('breakMode')
          .get();
      setState(() {
        _breakMode = doc.exists ? (doc.data()?['enabled'] ?? false) : false;
        _loadingBreakMode = false;
      });
    } catch (e) {
      setState(() => _loadingBreakMode = false);
    }
  }

  Future<void> _toggleBreakMode(bool value) async {
    setState(() => _breakMode = value);
    await FirebaseFirestore.instance
        .collection('systemSettings')
        .doc('breakMode')
        .set({'enabled': value, 'updatedAt': FieldValue.serverTimestamp()});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(value
          ? "🏖️ Break Mode ON — scheduled notifications paused"
          : "📚 Break Mode OFF — notifications resumed"),
      backgroundColor: value ? const Color(0xFFFFB74D) : AppTheme.secondary,
    ));
  }

  Future<void> _sendDassReminder() async {
    setState(() => _isSendingDass = true);
    try {
      final studentsSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .get();

      final List<String> playerIds = [];
      final List<String> studIds = [];

      for (final doc in studentsSnapshot.docs) {
        final data = doc.data();
        final playerId = data['playerId'] as String?;
        if (playerId != null && playerId.isNotEmpty) {
          playerIds.add(playerId);
        }
        studIds.add(doc.id);
      }

      if (playerIds.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No students with registered devices found")),
        );
        return;
      }

      // Send push notification to all students
      await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Basic os_v2_app_lz5pbnfqobcapetxlq4k7j3trx4wm4ed2siuthvr3lxw6cz2q5l3kclxja5hg6ghkoxa4l3dzqnzi7pzm2e5plw66jocn3nblh2y3bq',
        },
        body: jsonEncode({
          'app_id': '5e7af0b4-b070-4407-9277-5c38afa7838d',
          'include_player_ids': playerIds,
          'headings': {'en': 'DASS-21 Assessment Reminder 📋'},
          'contents': {
            'en':
                'It\'s time to complete your DASS-21 stress assessment. Please complete it in the app today!'
          },
          'data': {'type': 'dass21_reminder'},
          'small_icon': 'ic_stat_mindease',
          'android_accent_color': 'FF4DB6AC',
        }),
      );

      // Save to each student's notification inbox
      for (final studId in studIds) {
        await FirebaseFirestore.instance.collection('notificationInbox').add({
          'recipient_id': studId,
          'title': 'DASS-21 Assessment Reminder 📋',
          'body':
              'It\'s time to complete your DASS-21 stress assessment. Please complete it in the app today!',
          'type': 'dass21_reminder',
          'read': false,
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "✅ DASS-21 reminder sent to ${playerIds.length} students!"),
          backgroundColor: AppTheme.secondary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => _isSendingDass = false);
    }
  }

  final List<Map<String, String>> types = [
    {'value': 'quote', 'label': 'Quote'},
    {'value': 'tip', 'label': 'Self-Care Tip'},
  ];

  final List<Map<String, String>> riskLevels = [
    {'value': 'all', 'label': 'All'},
    {'value': 'normal', 'label': 'Normal'},
    {'value': 'moderate', 'label': 'Moderate'},
    {'value': 'critical', 'label': 'Critical'},
  ];

  Future<void> _saveContent() async {
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter content")),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;

      await FirebaseFirestore.instance
          .collection('relaxationContent')
          .add({
        'type': _selectedType,
        'description': _contentController.text.trim(),
        'risk_level': _selectedRiskLevel,
        'admin_id': user?.uid ?? '',
        'created_at': FieldValue.serverTimestamp(),
      });

      _contentController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Content added successfully!"),
          backgroundColor: Color(0xFF4DB6AC),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteContent(String docId) async {
    await FirebaseFirestore.instance
        .collection('relaxationContent')
        .doc(docId)
        .delete();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Content deleted")),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'quote': return AppTheme.secondary;
      case 'tip': return AppTheme.primary;
      case 'breathing': return const Color(0xFF7B5EA7);
      default: return Colors.grey;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'quote': return Icons.format_quote;
      case 'tip': return Icons.favorite;
      case 'breathing': return Icons.air;
      default: return Icons.note;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          const SizedBox(height: 8),

          // ── Break Mode Toggle Card ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _breakMode ? const Color(0xFFFFF3E0) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _breakMode
                    ? const Color(0xFFFFB74D)
                    : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "NOTIFICATION SCHEDULE",
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    color: AppTheme.textGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      _breakMode ? "🏖️" : "📚",
                      style: const TextStyle(fontSize: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _breakMode
                                ? "Break Mode — ON"
                                : "Break Mode — OFF",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: _breakMode
                                  ? const Color(0xFFFFB74D)
                                  : AppTheme.textDark,
                            ),
                          ),
                          Text(
                            _breakMode
                                ? "Scheduled reminders paused. Students can still log mood anytime."
                                : "Scheduled reminders active. Mood & PA alerts running normally.",
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textGrey,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _loadingBreakMode
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Switch(
                            value: _breakMode,
                            onChanged: _toggleBreakMode,
                            activeThumbColor: const Color(0xFFFFB74D),
                          ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── DASS-21 Reminder Card ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "DASS-21 REMINDER",
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    color: AppTheme.textGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text("📋", style: TextStyle(fontSize: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Send DASS-21 Assessment Reminder",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppTheme.textDark,
                            ),
                          ),
                          Text(
                            "Notifies ALL registered students to complete their stress assessment",
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textGrey,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppTheme.buttonGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _isSendingDass ? null : _sendDassReminder,
                    icon: _isSendingDass
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.send, color: Colors.white, size: 16),
                    label: Text(
                      _isSendingDass ? "Sending..." : "Send to All Students",
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Add Content Form ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "ADD CONTENT",
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    color: AppTheme.textGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),

                // Type selector
                Text("Type",
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textDark)),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: types.map((t) {
                      final isSelected = _selectedType == t['value'];
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedType = t['value']!),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primarySoft
                                : const Color(0xFFF8F9FA),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primary
                                  : const Color(0xFFE2E8F0),
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            t['label']!,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.textGrey,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 14),

                // Risk level selector
                Text("Show for",
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textDark)),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: riskLevels.map((r) {
                      final isSelected = _selectedRiskLevel == r['value'];
                      return GestureDetector(
                        onTap: () => setState(
                            () => _selectedRiskLevel = r['value']!),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.secondarySoft
                                : const Color(0xFFF8F9FA),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.secondary
                                  : const Color(0xFFE2E8F0),
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            r['label']!,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isSelected
                                  ? AppTheme.secondary
                                  : AppTheme.textGrey,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 14),

                // Content text field
                TextField(
                  controller: _contentController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: "Enter content here...",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Save button
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppTheme.buttonGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveContent,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(
                            color: Colors.white)
                        : const Text(
                            "Add Content",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Content List ──
          Text(
            "ALL CONTENT",
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1,
              color: AppTheme.textGrey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('relaxationContent')
                .orderBy('created_at', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    "No content yet. Add your first content above!",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textGrey),
                  ),
                );
              }

              return Column(
                children: snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final type = data['type'] ?? 'quote';
                  final description = data['description'] ?? '';
                  final riskLevel = data['risk_level'] ?? 'all';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Type icon
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _typeColor(type).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _typeIcon(type),
                            color: _typeColor(type),
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Content
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _typeColor(type)
                                          .withOpacity(0.1),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      type.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: _typeColor(type),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primarySoft,
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      riskLevel.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                description,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textDark,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Edit + Delete buttons
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => _showEditDialog(context, doc.id, data),
                              icon: const Icon(Icons.edit_outlined,
                                  color: AppTheme.primary, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => _showDeleteDialog(context, doc.id),
                              icon: const Icon(Icons.delete_outline,
                                  color: Color(0xFFE57373), size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, String docId, Map<String, dynamic> data) {
    final editController = TextEditingController(text: data['description'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Edit Content",
            style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Type: ${(data['type'] ?? '').toString().toUpperCase()}",
              style: TextStyle(fontSize: 11, color: AppTheme.textGrey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: editController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: "Edit content here...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: AppTheme.textGrey)),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppTheme.buttonGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ElevatedButton(
              onPressed: () async {
                final newText = editController.text.trim();
                if (newText.isEmpty) return;
                Navigator.pop(ctx);
                await FirebaseFirestore.instance
                    .collection('relaxationContent')
                    .doc(docId)
                    .update({'description': newText});
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Content updated successfully!"),
                    backgroundColor: AppTheme.secondary,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("Save", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text("Delete Content?"),
        content: const Text(
            "This content will be permanently deleted."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteContent(docId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE57373),
            ),
            child: const Text("Delete",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════
// ── REFERRAL PAGE ──
// ══════════════════════════════════════════
class _ReferralPage extends StatefulWidget {
  @override
  State<_ReferralPage> createState() => _ReferralPageState();
}

class _ReferralPageState extends State<_ReferralPage> {
  String _filterStatus = 'all';

  final List<Map<String, String>> filters = [
    {'value': 'all', 'label': 'All'},
    {'value': 'pending', 'label': 'Pending'},
    {'value': 'accepted', 'label': 'Accepted'},
    {'value': 'declined', 'label': 'Declined'},
    {'value': 'done', 'label': 'Done'},
  ];

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return const Color(0xFFFFB74D);
      case 'accepted': return const Color(0xFF4DB6AC);
      case 'declined': return const Color(0xFFE57373);
      case 'done': return AppTheme.primary;
      default: return Colors.grey;
    }
  }

  String _statusEmoji(String status) {
    switch (status) {
      case 'pending': return '⏳';
      case 'accepted': return '✅';
      case 'declined': return '❌';
      case 'done': return '🎯';
      default: return '❓';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Filter chips ──
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filters.map((f) {
                final isSelected = _filterStatus == f['value'];
                return GestureDetector(
                  onTap: () => setState(() => _filterStatus = f['value']!),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primary : const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? AppTheme.primary : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Text(
                      f['label']!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : AppTheme.textGrey,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // ── Referral list ──
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('referrals')
                .orderBy('referral_date', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.swap_horiz, color: AppTheme.textGrey, size: 48),
                      const SizedBox(height: 12),
                      Text("No referrals yet", style: TextStyle(color: AppTheme.textGrey)),
                    ],
                  ),
                );
              }

              // Filter by status
              var docs = snapshot.data!.docs;
              if (_filterStatus != 'all') {
                docs = docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return data['status'] == _filterStatus;
                }).toList();
              }

              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    "No $_filterStatus referrals",
                    style: TextStyle(color: AppTheme.textGrey),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  return _ReferralCard(data: data, statusColor: _statusColor, statusEmoji: _statusEmoji);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Referral Card with real names ──
class _ReferralCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final Color Function(String) statusColor;
  final String Function(String) statusEmoji;

  const _ReferralCard({
    required this.data,
    required this.statusColor,
    required this.statusEmoji,
  });

  @override
  State<_ReferralCard> createState() => _ReferralCardState();
}

class _ReferralCardState extends State<_ReferralCard> {
  String studentName = '-';
  String paName = '-';
  String counsellorName = '-';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadNames();
  }

  Future<void> _loadNames() async {
    try {
      final studId = widget.data['stud_id'] as String? ?? '';
      final paId = widget.data['pa_id'] as String? ?? '';
      final counsellorId = widget.data['counsellor_id'] as String? ?? '';

      if (studId.isNotEmpty) {
        final studDoc = await FirebaseFirestore.instance
            .collection('students').doc(studId).get();
        if (studDoc.exists) {
          studentName = studDoc.data()?['fullName'] ?? studId;
        }
      }

      if (paId.isNotEmpty) {
        final paDoc = await FirebaseFirestore.instance
            .collection('personalAdvisor').doc(paId).get();
        if (paDoc.exists) {
          paName = paDoc.data()?['fullName'] ?? paId;
        }
      }

      if (counsellorId.isNotEmpty) {
        final counsellorDoc = await FirebaseFirestore.instance
            .collection('counsellors').doc(counsellorId).get();
        if (counsellorDoc.exists) {
          counsellorName = counsellorDoc.data()?['fullName'] ?? counsellorId;
        }
      }

      if (mounted) setState(() => _loaded = true);
    } catch (e) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.data['status'] ?? 'pending';
    final date = widget.data['referral_date'] ?? '-';
    final source = widget.data['source'] as String? ?? 'pa';
    final isStudentRequest = source == 'student';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.statusColor(status).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "${widget.statusEmoji(status)} ${status.toUpperCase()}",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: widget.statusColor(status),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isStudentRequest
                          ? AppTheme.secondarySoft
                          : AppTheme.primarySoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isStudentRequest ? "🙋 Student" : "📋 PA",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isStudentRequest ? AppTheme.secondary : AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              Text(date, style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          if (!_loaded)
            const Center(child: SizedBox(height: 20, width: 20,
                child: CircularProgressIndicator(strokeWidth: 2)))
          else ...[
            _referralRow(Icons.school, "Student", studentName),
            const SizedBox(height: 8),
            if (!isStudentRequest) ...[
              _referralRow(Icons.person, "Personal Advisor", paName),
              const SizedBox(height: 8),
            ],
            _referralRow(Icons.local_hospital, "Counsellor", counsellorName),
          ],
        ],
      ),
    );
  }

  Widget _referralRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 16),
        const SizedBox(width: 8),
        Text("$label: ",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textGrey)),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontSize: 12, color: AppTheme.textDark, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}