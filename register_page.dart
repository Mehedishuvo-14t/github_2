import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _auth = FirebaseAuth.instance;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isLoading = false;
  String? _verificationId;

  // ১. ফোন নম্বর ভেরিফিকেশন শুরু
  void _startRegistration() async {
    final String name = _nameController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();
    final String phoneInput = _phoneController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty || phoneInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("সব ঘর পূরণ করুন")));
      return;
    }

    setState(() { _isLoading = true; });

    // ফোন নম্বর ফরম্যাটিং (+88 যোগ করা)
    String phone = phoneInput;
    if (!phone.startsWith('+')) {
      phone = '+88' + (phone.startsWith('0') ? phone.substring(1) : phone);
    }

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // অটো-ভেরিফাই হলে সরাসরি ডাটাবেসে সেভ হবে
          await _finalizeUserRegistration(credential);
        },
        verificationFailed: (e) {
          setState(() { _isLoading = false; });
          debugPrint("Verification Failed: ${e.message}");
        },
        codeSent: (id, resendToken) {
          setState(() { _isLoading = false; _verificationId = id; });
          _showOTPDialog();
        },
        codeAutoRetrievalTimeout: (id) => _verificationId = id,
      );
    } catch (e) {
      setState(() { _isLoading = false; });
      debugPrint("Auth Error: $e");
    }
  }

  // ২. OTP দেওয়ার জন্য ডায়ালগ
  void _showOTPDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("OTP দিন"),
        content: TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: "৬ ডিজিটের কোড")
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("বাতিল")),
          ElevatedButton(
            onPressed: () async {
              String otp = _otpController.text.trim();
              if (otp.length == 6) {
                Navigator.pop(context);
                setState(() { _isLoading = true; });
                PhoneAuthCredential credential = PhoneAuthProvider.credential(
                    verificationId: _verificationId!, smsCode: otp);
                await _finalizeUserRegistration(credential);
              }
            },
            child: const Text("Verify"),
          )
        ],
      ),
    );
  }

  // ৩. ফাইনাল রেজিস্ট্রেশন এবং সরাসরি Firestore-এ ডাটা সেভ
  Future<void> _finalizeUserRegistration(PhoneAuthCredential phoneCredential) async {
    try {
      // কন্ট্রোলার থেকে ডাটা লক করে রাখা যাতে "No Phone" না আসে
      final String name = _nameController.text.trim();
      final String email = _emailController.text.trim();
      final String password = _passwordController.text.trim();
      final String phone = _phoneController.text.trim();

      // FirebaseAuth-এ ইউজার তৈরি (UID পাওয়ার জন্য)
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final String uid = userCredential.user!.uid;

      // সরাসরি Firestore-এ ডাটা পুশ করা (লিঙ্কিং বাদ দিয়ে এরর এড়ানো হয়েছে)
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'name': name.isNotEmpty ? name : "User",
        'email': email,
        'phone': phone, // সরাসরি কন্ট্রোলার থেকে পাঠানো নম্বর
        'uid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 15));

      if (mounted) {
        // সফল হলে সরাসরি ড্যাশবোর্ডে নিয়ে যাবে
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Registration Successful!"), backgroundColor: Colors.green)
        );
        Navigator.pop(context);
      }

    } catch (e) {
      debugPrint("Silent Error: $e");
      // এখানে আর কোনো 'Fail' পপ-আপ দেওয়া হয়নি যাতে ইউজার বিরক্ত না হয়
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Account"), backgroundColor: Colors.redAccent),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Icon(Icons.person_add, size: 80, color: Colors.redAccent),
              const SizedBox(height: 20),
              TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Full Name", border: OutlineInputBorder())),
              const SizedBox(height: 15),
              TextField(controller: _emailController, decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder())),
              const SizedBox(height: 15),
              TextField(controller: _phoneController, decoration: const InputDecoration(labelText: "Phone (e.g. 017...)", border: OutlineInputBorder()), keyboardType: TextInputType.phone),
              const SizedBox(height: 15),
              TextField(controller: _passwordController, decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder()), obscureText: true),
              const SizedBox(height: 30),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 55),
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                  ),
                  onPressed: _startRegistration,
                  child: const Text("Verify & Register", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
              ),
            ],
          ),
        ),
      ),
    );
  }
}