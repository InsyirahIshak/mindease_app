import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:mindease_app/theme/app_theme.dart';
import 'package:mindease_app/services/notification_service.dart';


// Pages
import 'package:mindease_app/pages/home_screen.dart';
import 'package:mindease_app/pages/register_page.dart';
import 'package:mindease_app/pages/login_page.dart';


import 'package:mindease_app/pages/student_dashboard.dart';
import 'package:mindease_app/pages/mood_logging_page.dart';
import 'package:mindease_app/pages/stress_assessment_page.dart';
import 'package:mindease_app/pages/mood_tracking_page.dart';
import 'package:mindease_app/pages/counsellors_page.dart';
import 'package:mindease_app/pages/pa_dashboard.dart';
import 'package:mindease_app/pages/pa_student_detail.dart';
import 'package:mindease_app/pages/pa_counsellors_page.dart';
import 'package:mindease_app/pages/counsellor_dashboard.dart';
import 'package:mindease_app/pages/admin_dashboard.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:mindease_app/pages/manage_profile_page.dart';
import 'package:mindease_app/pages/staff_profile_page.dart';
import 'package:mindease_app/pages/notification_inbox_page.dart';




void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // OneSignal setup
  OneSignal.initialize("5e7af0b4-b070-4407-9277-5c38afa7738d");
  OneSignal.Notifications.requestPermission(true);
  
  // Initialize OneSignal
  await NotificationService.initialize();


  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NotificationService.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData,
      home: const HomeScreen(),
      routes: {
        '/register': (context) => const RegisterPage(),
        '/login': (context) => const LoginPage(),
        '/dashboard': (context) => const StudentDashboard(),
        '/moodLogging': (context) => const MoodLoggingPage(),
        '/stressAssessment': (context) => const StressAssessmentPage(),
        '/moodTracking': (context) => const MoodTrackingPage(),
        '/counsellors': (context) => const CounsellorsPage(),
        '/personalAdvisor': (context) => const PADashboard(),
        '/paStudentDetail': (context) => const PAStudentDetail(),
        '/paCounsellors': (context) => const PACounsellorsPage(),
        '/counsellors_dashboard': (context) => const CounsellorDashboard(),
        '/counsellorStudentDetail': (context) => const PAStudentDetail(),
        '/admins': (context) => const AdminDashboard(),
        '/manageProfile': (context) => const ManageProfilePage(),
        '/notifications': (context) => const NotificationInboxPage(),
        // PA Profile
'/paProfile': (context) => const StaffProfilePage(
  collection: 'personalAdvisor',
  role: 'Personal Advisor',
),

// Counsellor Profile
'/counsellorProfile': (context) => const StaffProfilePage(
  collection: 'counsellors',
  role: 'Counsellor',
),

// Admin Profile
'/adminProfile': (context) => const StaffProfilePage(
  collection: 'admins',
  role: 'Admin',
),
      },
    );
  }
}