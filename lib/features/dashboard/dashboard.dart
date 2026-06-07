import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pathology Dashboard'),
        centerTitle: false,
      ),
      drawer: const _DashboardDrawer(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome Back',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Laboratory operations overview',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                GridView.count(
                  crossAxisCount: isWide ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: const [
                    _StatCard(
                      title: 'Patients',
                      value: '',
                      icon: Icons.people_outline,
                    ),
                    _StatCard(
                      title: 'Samples',
                      value: '',
                      icon: Icons.science_outlined,
                    ),
                    _StatCard(
                      title: 'Pending Results',
                      value: '',
                      icon: Icons.pending_actions_outlined,
                    ),
                    _StatCard(
                      title: 'Reports Issued',
                      value: '',
                      icon: Icons.description_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Quick Actions',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () => context.go('/patients'),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('New Patient'),
                    ),
                    FilledButton.icon(
                      onPressed: () => context.go('/samples'),
                      icon: const Icon(Icons.science),
                      label: const Text('New Sample'),
                    ),
                    FilledButton.icon(
                      onPressed: () => context.go('/results'),
                      icon: const Icon(Icons.fact_check),
                      label: const Text('Enter Result'),
                    ),
                    FilledButton.icon(
                      onPressed: () => context.go('/reports'),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Generate Report'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Recent Activity',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 5,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.history),
                        ),
                        title: Text('Activity ${index + 1}'),
                        subtitle: const Text(
                          'Recent laboratory operation recorded.',
                        ),
                        trailing: const Text('Today'),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.headlineSmall,
                  ),
                  Text(title),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardDrawer extends StatelessWidget {
  const _DashboardDrawer();

  @override
  Widget build(BuildContext context) {
    return NavigationDrawer(
      children: const [
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Pathology System',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: Text('Dashboard'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: Text('Patients'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.science_outlined),
          selectedIcon: Icon(Icons.science),
          label: Text('Samples'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.assignment_outlined),
          selectedIcon: Icon(Icons.assignment),
          label: Text('Results'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.picture_as_pdf_outlined),
          selectedIcon: Icon(Icons.picture_as_pdf),
          label: Text('Reports'),
        ),
      ],
    );
  }
}
