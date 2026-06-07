import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:bimal_pathology_system/features/dashboard/dashboard_page.dart';
import 'package:bimal_pathology_system/features/login/login_page.dart';
import 'package:bimal_pathology_system/features/error/not_found_page.dart';
import 'package:bimal_pathology_system/features/patients/patient_list.dart';
import 'package:bimal_pathology_system/features/samples/sample_list.dart';
import 'package:bimal_pathology_system/features/shell/main_shell.dart';
import 'package:bimal_pathology_system/security/auth/auth_service.dart';

final GoRouter router = GoRouter(
  initialLocation: '/',
  errorBuilder: (context, state) => const NotFoundPage(),
  redirect: (context, state) {
    // यहाँ `isAuthenticated` लाई बदलेर `isLoggedIn` राखिएको छ
    final bool isLoggedIn = AuthService.instance.isLoggedIn;
    final isLoggingIn = state.uri.path == '/login';

    if (!isLoggedIn && !isLoggingIn) return '/login';
    if (isLoggedIn && isLoggingIn) return '/';
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardPage(),
        ),
        GoRoute(
          path: '/patients',
          builder: (context, state) => const PatientList(),
        ),
        GoRoute(
          path: '/samples',
          builder: (context, state) => const SampleList(),
        ),
      ],
    ),
  ],
);