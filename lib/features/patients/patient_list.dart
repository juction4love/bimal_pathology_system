import 'package:flutter/material.dart';
import 'package:bimal_pathology_system/features/patients/patient_list_provider.dart';
import 'package:bimal_pathology_system/features/patients/models/patient.dart';

class PatientList extends StatefulWidget {
  const PatientList({super.key});

  @override
  State<PatientList> createState() => _PatientListState();
}

class _PatientListState extends State<PatientList> {
  final PatientListProvider _provider = PatientListProvider();

  @override
  void initState() {
    super.initState();
    _provider.loadPatients(); // डेटाबेसबाट बिरामीहरू लोड गर्ने
  }

  // ➕ नयाँ बिरामी थप्ने डायलग फारम (Popup Form)
  void _openAddPatientDialog() {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final ageCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('नयाँ बिरामी दर्ता (Add Patient)'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'बिरामीको नाम',
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (v) => v!.isEmpty ? 'कृपया नाम लेख्नुहोस्' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: ageCtrl,
                    decoration: const InputDecoration(
                      labelText: 'उमेर (Age)',
                      prefixIcon: Icon(Icons.cake),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'कृपया उमेर लेख्नुहोस्' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'फोन नम्बर',
                      prefixIcon: Icon(Icons.phone),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (v) => v!.isEmpty ? 'कृपया फोन नम्बर लेख्नुहोस्' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  // १. नयाँ Patient अब्जेक्ट तयार गर्ने
                  final newPatient = Patient(
                    patientId: 'P-${DateTime.now().millisecondsSinceEpoch}', // Unique ID
                    name: nameCtrl.text,
                    age: int.parse(ageCtrl.text),
                    phone: phoneCtrl.text,
                  );

                  // २. Provider मार्फत IndexedDB मा सेभ गर्ने
                  await _provider.createPatient(newPatient);
                  
                  if (context.mounted) {
                    Navigator.pop(context); // पपअप विन्डो बन्द गर्ने
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('बिरामी सफलतापूर्वक दर्ता भयो!')),
                    );
                  }
                }
              },
              child: const Text('Save Patient'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients Registry'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _provider.loadPatients(), // रिफ्रेस बटन
          )
        ],
      ),
      body: ListenableBuilder(
        listenable: _provider,
        builder: (context, child) {
          if (_provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_provider.patients.isEmpty) {
            return const Center(
              child: Text(
                'कोही पनि बिरामी दर्ता गरिएको छैन।\nतलको (+) बटन थिचेर नयाँ बिरामी थप्नुहोस्।',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            itemCount: _provider.patients.length,
            itemBuilder: (context, index) {
              final Patient patient = _provider.patients[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(patient.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('उमेर: ${patient.age} | फोन: ${patient.phone}'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                ),
              );
            },
          );
        },
      ),
      // बटन थिच्दा अब पपअप फारम खुल्नेछ
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddPatientDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}