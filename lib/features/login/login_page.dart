import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart'; // १. GoRouter अनिवार्य Import गर्ने
import 'package:bimal_pathology_system/security/auth/auth_service.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            // Dummy login – replace with real authentication later.
            AuthService.instance.signIn();
            
            // २. पुरानो Navigator लाई बदलेर GoRouter को शैली प्रयोग गरिएको:
            context.go('/');
          },
          child: const Text('Sign In'),
        ),
      ),
    );
  }
}