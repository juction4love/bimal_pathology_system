import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PatientDetailPage extends StatelessWidget {
  final String id;
  const PatientDetailPage({required this.id, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Patient Details: $id')),
      body: Center(
        child: Text('Showing details for patient with ID: $id'),
      ),
    );
  }
}
