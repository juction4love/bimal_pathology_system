import 'package:flutter/material.dart';
import 'package:bimal_pathology_system/services/database/db_helper.dart';
import 'package:bimal_pathology_system/features/samples/sample_list_provider.dart';
import 'package:bimal_pathology_system/features/samples/models/sample.dart';
import 'package:bimal_pathology_system/features/results/results_entry_form.dart';
import 'package:bimal_pathology_system/services/pdf_report_service.dart'; // ➕ १. PDF Service Import गरियो

class SampleList extends StatefulWidget {
  const SampleList({super.key});

  @override
  State<SampleList> createState() => _SampleListState();
}

class _SampleListState extends State<SampleList> {
  final SampleListProvider _provider = SampleListProvider();
  final DbHelper _dbHelper = DbHelper();
  List<Map<String, dynamic>> _patientsList = []; // ड्रपडाउनका लागि बिरामीहरू

  @override
  void initState() {
    super.initState();
    _provider.loadSamples();
    _loadPatientsForDropdown();
  }

  Future<void> _loadPatientsForDropdown() async {
    final patients = await _dbHelper.getAllData('patients');
    setState(() {
      _patientsList = patients;
    });
  }

  // नयाँ नमुना संकलनको पपअप डायलग
  void _openSampleCollectionDialog() {
    if (_patientsList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('नमुना संकलन गर्न पहिले बिरामी दर्ता हुनुपर्छ!')),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    String? selectedPatientId;
    String selectedSampleType = 'Blood';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('New Sample Collection'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Select Patient',
                        prefixIcon: Icon(Icons.person),
                      ),
                      value: selectedPatientId,
                      items: _patientsList.map((p) {
                        return DropdownMenuItem<String>(
                          value: p['patientId'].toString(),
                          child: Text(p['name'].toString()),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedPatientId = value);
                      },
                      validator: (v) => v == null ? 'Please select a patient' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Sample Type',
                        prefixIcon: Icon(Icons.science),
                      ),
                      value: selectedSampleType,
                      items: const [
                        DropdownMenuItem(value: 'Blood', child: Text('Blood')),
                        DropdownMenuItem(value: 'Urine', child: Text('Urine')),
                        DropdownMenuItem(value: 'Serum', child: Text('Serum')),
                      ],
                      onChanged: (value) {
                        setDialogState(() => selectedSampleType = value!);
                      },
                    ),
                  ],
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
                      final newSample = Sample(
                        sampleId: 'SMP-${DateTime.now().millisecondsSinceEpoch}',
                        patientId: selectedPatientId!,
                        type: selectedSampleType,
                        collectedAt: DateTime.now(),
                      );

                      await _dbHelper.insertData('samples', newSample.toJson());
                      await _provider.loadSamples();

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Sample Collected Successfully!')),
                        );
                      }
                    }
                  },
                  child: const Text('Collect'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Samples List'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _provider.loadSamples();
              _loadPatientsForDropdown();
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _provider,
        builder: (context, _) {
          if (_provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_provider.samples.isEmpty) {
            return const Center(
              child: Text(
                'कुनै नमूना दर्ता गरिएको छैन।\nतलको बटन थिचेर संकलन सुरु गर्नुहोस्।',
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView.builder(
            itemCount: _provider.samples.length,
            itemBuilder: (context, i) {
              final Sample s = _provider.samples[i];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.shade100,
                    child: const Icon(Icons.biotech, color: Colors.orange),
                  ),
                  title: Text('Sample ${s.sampleId} – ${s.type}'),
                  subtitle: Text('Patient ID: ${s.patientId}\nCollected: ${s.collectedAt.toLocal()}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_chart, color: Colors.blue),
                    tooltip: 'Enter Result',
                    onPressed: () async {
                      await showDialog(
                        context: context,
                        builder: (_) => ResultsEntryForm(sampleId: s.sampleId),
                      );
                      _provider.loadSamples();
                      setState(() {});
                    },
                  ),
                  children: [
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _dbHelper.getAllData('results'),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: LinearProgressIndicator(),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: Text('No result entered yet.', style: TextStyle(color: Colors.grey)),
                          );
                        }

                        final matches = snapshot.data!.where((r) => r['sampleId'] == s.sampleId).toList();

                        if (matches.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: Text('No result found for this sample.', style: TextStyle(color: Colors.grey)),
                          );
                        }

                        return Container(
                          color: Colors.grey.shade50,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            children: [
                              // रिजल्टहरूको सूची
                              ...matches.map((r) {
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    'Parameter: ${r['parameterName']}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  subtitle: Text('Remarks: ${r['remarks'] ?? '-'}'),
                                  trailing: Text(
                                    '${r['value']} ${r['unit']}',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                  ),
                                ),
                              );
                            }).toList(),
                            
                            const Divider(),
                            
                            // ➕ २. पीडीएफ जेनेरेट र प्रिन्ट गर्ने बटन यहाँ थपियो
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0, right: 16.0),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.picture_as_pdf),
                                  label: const Text('Print / View PDF Report'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade700,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () async {
                                    // सूचिबाट बिरामीको नाम खोज्ने
                                    final currentPatient = _patientsList.firstWhere(
                                      (p) => p['patientId'].toString() == s.patientId.toString(),
                                      orElse: () => {'name': 'Unknown Patient'},
                                    );

                                    // PDF Service कल गर्ने
                                    await PdfReportService.generateAndShowReport(
                                      sampleId: s.sampleId,
                                      patientId: s.patientId,
                                      patientName: currentPatient['name'].toString(),
                                      sampleType: s.type,
                                      date: s.collectedAt.toLocal().toString().split(' ')[0],
                                      results: matches,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  )
                ],
              ),
            );
          },
        );
      },
    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openSampleCollectionDialog,
        icon: const Icon(Icons.add_box),
        label: const Text('Collect Sample'),
      ),
    );
  }
}