import 'package:flutter/material.dart';
import '../services/auth_services.dart';
import 'signup_screen.dart';
import '../home/home_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool isLoading = false;
  String? error;

  Future<String> _getUserName(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists) {
      final data = doc.data();
      return "${data?['firstName']} ${data?['lastName']}";
    }
    return "User";
  }

  void _login() async {
    setState(() { isLoading = true; error = null; });
    final user = await _authService.signIn(emailController.text, passwordController.text);
    setState(() { isLoading = false; });
    if (user != null) {
      final name = await _getUserName(user.uid);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomePage(name: name)),
      );
    } else {
      setState(() { error = 'Login failed. Please check your credentials.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : _login,
              child: isLoading ? const CircularProgressIndicator() : const Text('Login'),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SignupScreen()),
                );
              },
              child: const Text("Don't have an account? Sign up"),
            ),
          ],
        ),
      ),
    );
  }
}