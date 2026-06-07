// lib/features/patients/patient_form.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/patient_repository.dart';
import '../../features/patients/models/patient.dart';

class PatientFormPage extends ConsumerStatefulWidget {
  const PatientFormPage({Key? key}) : super(key: key);

  @override
  ConsumerState<PatientFormPage> createState() => _PatientFormPageState();
}

class _PatientFormPageState extends ConsumerState<PatientFormPage> {
  final _formKey = GlobalKey<FormState>();

  // Simple incremental id for demo purposes
  int _nextId = 3;
  String _firstName = '';
  String _lastName = '';
  String _mrn = '';
  DateTime _dob = DateTime(2000, 1, 1);
  String _gender = 'Male';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final newPatient = Patient(
      id: _nextId++,
      firstName: _firstName,
      lastName: _lastName,
      mrn: _mrn,
      dateOfBirth: _dob,
      gender: _gender,
    );

    await ref.read(patientRepositoryProvider).addPatient(newPatient);
    // After adding, go back to the list page.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Patient')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'First Name'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                onSaved: (v) => _firstName = v!.trim(),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Last Name'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                onSaved: (v) => _lastName = v!.trim(),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'MRN'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                onSaved: (v) => _mrn = v!.trim(),
              ),
              // Date of birth picker
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Date of Birth'),
                child: GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dob,
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _dob = picked);
                  },
                  child: Text('${_dob.toLocal()}'.split(' ')[0]),
                ),
              ),
              DropdownButtonFormField<String>(
                value: _gender,
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                ],
                decoration: const InputDecoration(labelText: 'Gender'),
                onChanged: (v) => setState(() => _gender = v!),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _submit,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
