import 'package:flutter/material.dart';
import 'package:bimal_pathology_system/routing/router.dart';
import 'package:bimal_pathology_system/core/theme/theme.dart';

class BimalPathologyApp extends StatelessWidget {
  const BimalPathologyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Bimal Pathology System',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      routerConfig: router,
    );
  }
}
