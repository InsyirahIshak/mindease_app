import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mindease_app/theme/app_theme.dart';
import 'package:mindease_app/services/notification_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final uitmIdController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;
  bool _obscurePassword = true;

  final List<String> collections = [
    'students',
    'personalAdvisor',
    'counsellors',
    'admins',
  ];

  Future<Map<String, dynamic>?> findUserByUitmId(String uitmId) async {
    final firestore = FirebaseFirestore.instance;
    for (String collection in collections) {
      final doc = await firestore.collection(collection).doc(uitmId).get();
      if (doc.exists) {
        return {'collection': collection, 'data': doc.data()};
      }
    }
    return null;
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        title: const Text("Reset Password", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Enter your registered email address. A password reset link will be sent to your email.",
                style: TextStyle(fontSize: 12, color: AppTheme.textGrey),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: "Email Address",
                  hintText: "Enter your email",
                  prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.primary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
              const SizedBox(height: 4),
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
                    side: BorderSide(color: AppTheme.primary),
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
                    onPressed: () async {
                      final email = emailController.text.trim();
                      if (email.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text("Please enter your email address")),
                        );
                        return;
                      }
                      try {
                        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                        if (!mounted) return;
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Password reset email sent! Please check your inbox."),
                            backgroundColor: AppTheme.primary,
                          ),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text("Error: ${e.toString()}")),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text("Send Link", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> loginUser() async {
    final uitmId = uitmIdController.text.trim();
    final password = passwordController.text.trim();

    if (uitmId.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all fields")),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final result = await findUserByUitmId(uitmId);

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("UITM ID not found.")),
        );
        setState(() => isLoading = false);
        return;
      }

      final data = result['data'] as Map<String, dynamic>;
      final role = data['role'] as String;
      final email = data['email'] as String;

      if (data['uid'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Account not registered yet. Please register first.")),
        );
        setState(() => isLoading = false);
        return;
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // ── Register/refresh OneSignal playerId now that we have a logged in user ──
      try {
        await NotificationService.savePlayerIdToFirestore();
      } catch (e) {
        print("Error saving player ID after login: $e");
      }

      if (!mounted) return;
      if (role == "Student") {
        Navigator.pushReplacementNamed(context, "/dashboard");
      } else if (role == "Personal Advisor") {
        Navigator.pushReplacementNamed(context, "/personalAdvisor");
      } else if (role == "Counsellor") {
        Navigator.pushReplacementNamed(context, "/counsellors_dashboard");
      } else if (role == "Admin") {
        Navigator.pushReplacementNamed(context, "/admins");
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login failed: $e")),
      );
    }

    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: AppTheme.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: keyboardHeight > 0
              ? const AlwaysScrollableScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          child: SizedBox(
            height: screenHeight - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
            child: Column(
              children: [

                // ── Header — compact ──
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(24, screenHeight * 0.03, 24, screenHeight * 0.03),
                  decoration: const BoxDecoration(
                    gradient: AppTheme.headerGradient,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(36),
                      bottomRight: Radius.circular(36),
                    ),
                  ),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_back_ios, color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text("Back", style: TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.015),
                      Container(
                        width: screenHeight * 0.1,
                        height: screenHeight * 0.1,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset('assets/icon/icon.png', fit: BoxFit.cover),
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.01),
                      const Text(
                        "MindEase",
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Welcome!",
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),

                // ── Form ──
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Login",
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Enter your UITM ID and password",
                          style: TextStyle(fontSize: 13, color: AppTheme.textGrey),
                        ),
                        const SizedBox(height: 20),

                        // UITM ID
                        TextField(
                          controller: uitmIdController,
                          decoration: InputDecoration(
                            labelText: "UITM ID",
                            hintText: "Enter your UITM ID",
                            prefixIcon: const Icon(Icons.badge_outlined, color: AppTheme.primary),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Password
                        TextField(
                          controller: passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: "Password",
                            prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.primary),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                color: AppTheme.textGrey,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Forgot Password
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: _showForgotPasswordDialog,
                            child: const Text(
                              "Forgot Password?",
                              style: TextStyle(
                                color: AppTheme.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Login button
                        isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: AppTheme.buttonGradient,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ElevatedButton(
                                  onPressed: loginUser,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    minimumSize: const Size(double.infinity, 52),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text(
                                    "Login",
                                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),

                        const SizedBox(height: 20),

                        // Register link
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Don't have an account? ",
                              style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pushNamed(context, '/register'),
                              child: const Text(
                                "Register here",
                                style: TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}