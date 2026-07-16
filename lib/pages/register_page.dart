import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mindease_app/theme/app_theme.dart';
import 'package:flutter/services.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final uitmIdController = TextEditingController();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final semesterController = TextEditingController();

  String? selectedGender;
  String? detectedRole;
  bool isLoading = false;
  bool isCheckingId = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasNumber = false;
  bool _hasSpecialChar = false;

  bool get _isPasswordValid =>
      _hasMinLength && _hasUppercase && _hasLowercase && _hasNumber && _hasSpecialChar;

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
        return {
          'collection': collection,
          'docId': doc.id,
          'data': doc.data(),
        };
      }
    }
    return null;
  }

  Future<void> checkUitmId() async {
    final uitmId = uitmIdController.text.trim();
    if (uitmId.isEmpty) return;

    setState(() => isCheckingId = true);

    final result = await findUserByUitmId(uitmId);

    setState(() {
      isCheckingId = false;
      if (result != null) {
        final data = result['data'] as Map<String, dynamic>;
        detectedRole = data['role'] as String?;
      } else {
        detectedRole = null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("UITM ID not found. Please contact admin."),
            backgroundColor: Color(0xFFE57373),
          ),
        );
      }
    });
  }

  void _validatePassword(String password) {
    setState(() {
      _hasMinLength = password.length >= 8;
      _hasUppercase = password.contains(RegExp(r'[A-Z]'));
      _hasLowercase = password.contains(RegExp(r'[a-z]'));
      _hasNumber = password.contains(RegExp(r'[0-9]'));
      _hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=~`\[\];/]'));
    });
  }

  Future<void> registerUser() async {
    final uitmId = uitmIdController.text.trim();
    final email = emailController.text.trim();
    final phone = phoneController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();
    final semester = semesterController.text.trim();

    if (uitmId.isEmpty ||
        nameController.text.isEmpty ||
        email.isEmpty ||
        phone.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all fields")),
      );
      return;
    }

    if (detectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please check your UITM ID first")),
      );
      return;
    }

    if (detectedRole == "Student") {
      if (semester.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter your semester")),
        );
        return;
      }
      final semInt = int.tryParse(semester);
      if (semInt == null || semInt < 1 || semInt > 8) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Semester must be between 1 and 8")),
        );
        return;
      }
      if (selectedGender == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select your gender")),
        );
        return;
      }
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Passwords do not match")),
      );
      return;
    }

    // ── Updated: check full password requirements instead of just length ──
    if (!_isPasswordValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password does not meet all requirements")),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final result = await findUserByUitmId(uitmId);

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("UITM ID not found. Please contact admin.")),
        );
        setState(() => isLoading = false);
        return;
      }

      final data = result['data'] as Map<String, dynamic>;
      final collection = result['collection'] as String;
      final docId = result['docId'] as String;
      final role = data['role'] as String;

      final storedName = (data['fullName'] as String).toLowerCase().trim();
      final enteredName = nameController.text.toLowerCase().trim();

      if (enteredName != storedName) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Name does not match our records. Please contact admin.")),
        );
        setState(() => isLoading = false);
        return;
      }

      if (data['uid'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("This UITM ID is already registered.")),
        );
        setState(() => isLoading = false);
        return;
      }

      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = userCredential.user!.uid;

      Map<String, dynamic> updateData = {
        'email': email,
        'phone': phone,
        'uid': uid,
        'registered': true,
      };

      if (role == "Student") {
        updateData['semester'] = int.tryParse(semester) ?? 0;
        updateData['gender'] = selectedGender;
      }

      await FirebaseFirestore.instance.collection(collection).doc(docId).update(updateData);

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(
                  gradient: AppTheme.headerGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 16),
              const Text(
                "Registration Successful!",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Your account has been created as $role. Please login to continue.",
                style: TextStyle(fontSize: 13, color: AppTheme.textGrey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppTheme.buttonGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Go to Login", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/');

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }

    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [

              // ── Header ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                decoration: const BoxDecoration(
                  gradient: AppTheme.headerGradient,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(40),
                    bottomRight: Radius.circular(40),
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
                            Text("Back", style: TextStyle(color: Colors.white, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_add, color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Create Account",
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Register with your UITM ID",
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),

              // ── Form ──
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    const SizedBox(height: 8),

                    _sectionLabel("Step 1 — Verify UITM ID"),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: uitmIdController,
                            decoration: InputDecoration(
                              labelText: "UITM ID",
                              hintText: "Enter your UITM ID",
                              prefixIcon: const Icon(Icons.badge_outlined, color: AppTheme.primary),
                              suffixIcon: isCheckingId
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : detectedRole != null
                                      ? const Icon(Icons.check_circle, color: Color(0xFF4DB6AC))
                                      : null,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onSubmitted: (_) => checkUitmId(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppTheme.buttonGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ElevatedButton(
                            onPressed: isCheckingId ? null : checkUitmId,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text("Check", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),

                    if (detectedRole != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.secondarySoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.secondary.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.verified_user, color: AppTheme.secondary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "UITM ID Verified ✓ Please fill in your details below.",
                                style: TextStyle(fontSize: 13, color: AppTheme.secondary, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (detectedRole != null) ...[
                      const SizedBox(height: 24),
                      _sectionLabel("Step 2 — Personal Information"),
                      const SizedBox(height: 10),

                      Padding(
                        padding: const EdgeInsets.only(bottom: 6, left: 4),
                        child: Text(
                          "Capitalize the first letter of each name",
                          style: TextStyle(fontSize: 12, color: AppTheme.textGrey),
                        ),
                      ),
                      TextField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: "Full Name",
                          hintText: "e.g., Nur Aisyah Binti Ahmad",
                          prefixIcon: const Icon(Icons.person_outline, color: AppTheme.primary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: "Email",
                          prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.primary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 14),

                    
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6, left: 4),
                        child: Text(
                          "Numbers only, without hyphens (-)",
                          style: TextStyle(fontSize: 12, color: AppTheme.textGrey),
                        ),
                      ),
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: "Phone Number",
                          hintText: "e.g., 0123456789",
                          prefixIcon: const Icon(Icons.phone_outlined, color: AppTheme.primary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),

                      if (detectedRole == "Student") ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: semesterController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: "Semester (1-8)",
                            prefixIcon: const Icon(Icons.school_outlined, color: AppTheme.primary),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: selectedGender,
                          decoration: InputDecoration(
                            labelText: "Gender",
                            prefixIcon: const Icon(Icons.wc_outlined, color: AppTheme.primary),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          items: const [
                            DropdownMenuItem(value: "Male", child: Text("Male")),
                            DropdownMenuItem(value: "Female", child: Text("Female")),
                          ],
                          onChanged: (val) => setState(() => selectedGender = val),
                        ),
                      ],

                      const SizedBox(height: 24),
                      _sectionLabel("Step 3 — Set Password"),
                      const SizedBox(height: 10),

                      // Password
                      TextField(
                        controller: passwordController,
                        obscureText: _obscurePassword,
                        onChanged: _validatePassword,
                        decoration: InputDecoration(
                          labelText: "Password",
                          hintText: "Minimum 8 characters",
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

                      const SizedBox(height: 10),

                      // ── Password requirements checklist ──
                      _buildPasswordRequirements(),

                      const SizedBox(height: 14),

                      // Confirm Password
                      TextField(
                        controller: confirmPasswordController,
                        obscureText: _obscureConfirm,
                        decoration: InputDecoration(
                          labelText: "Confirm Password",
                          prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.primary),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                              color: AppTheme.textGrey,
                            ),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),

                      const SizedBox(height: 28),

                      isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: AppTheme.buttonGradient,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primary.withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: registerUser,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  minimumSize: const Size(double.infinity, 56),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                child: const Text(
                                  "Register",
                                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                    ],

                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Already have an account? ", style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
                        GestureDetector(
                          onTap: () => Navigator.pushReplacementNamed(context, '/'),
                          child: const Text(
                            "Login here",
                            style: TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            gradient: AppTheme.buttonGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textDark),
        ),
      ],
    );
  }

  Widget _buildPasswordRequirements() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Password must contain:",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textGrey),
          ),
          const SizedBox(height: 8),
          _requirementRow("At least 8 characters", _hasMinLength),
          _requirementRow("One uppercase letter (A-Z)", _hasUppercase),
          _requirementRow("One lowercase letter (a-z)", _hasLowercase),
          _requirementRow("One number (0-9)", _hasNumber),
          _requirementRow("One special character (!@#\$%^&*)", _hasSpecialChar),
        ],
      ),
    );
  }

  Widget _requirementRow(String text, bool isMet) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: isMet ? const Color(0xFF4DB6AC) : Colors.grey.shade400,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: isMet ? const Color(0xFF4DB6AC) : AppTheme.textGrey,
                fontWeight: isMet ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}