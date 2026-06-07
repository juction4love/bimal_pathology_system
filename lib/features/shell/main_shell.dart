import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _getSelectedIndex(context),
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (index) {
              if (index == 0) context.go('/');
              if (index == 1) context.go('/patients');
              if (index == 2) context.go('/samples');
            },
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.analytics), label: Text('Dashboard')),
              NavigationRailDestination(icon: Icon(Icons.accessible), label: Text('Patients')),
              NavigationRailDestination(icon: Icon(Icons.biotech), label: Text('Samples')),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: SafeArea(child: child)),
        ],
      ),
    );
  }

  int _getSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/patients')) return 1;
    if (location.startsWith('/samples')) return 2;
    return 0;
  }
}
