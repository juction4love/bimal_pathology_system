import 'package:flutter/material.dart';
import 'package:bimal_pathology_system/services/database/db_helper.dart';

class PatientRegistration extends StatefulWidget {
  const PatientRegistration({super.key});

  @override
  State<PatientRegistration> createState() => _PatientRegistrationState();
}

class _PatientRegistrationState extends State<PatientRegistration> {
  final _formKey = GlobalKey<FormState>();
  final _dbHelper = DbHelper();

  // टेक्स्ट कन्ट्रोलरहरू
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _referredByController = TextEditingController();
  
  String _selectedSex = 'Male';
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _referredByController.dispose();
    super.dispose();
  }

  // 🎯 जादुमयी स्वचालित स्याम्पल कलेक्सन डायलग (Auto Sample Dialog)
  void _showAutoSampleCollectionDialog(BuildContext context, String patientId, String patientName) {
    String selectedSampleType = 'Blood';

    showDialog(
      context: context,
      barrierDismissible: false, // प्रयोगकर्ताले यसलाई बीचमा काट्न नमिलोस् (अनिवार्य वा स्किप मात्र)
      builder: (context) {
        return StatefulBuilder( // डायलग भित्र ड्रपडाउन परिवर्तन गर्न
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.science, color: Colors.orange, size: 28),
                  const SizedBox(width: 10),
                  Text('Collect Sample: $patientName'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Patient ID: $patientId', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Select Sample Type',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.biotech),
                    ),
                    value: selectedSampleType,
                    items: const [
                      DropdownMenuItem(value: 'Blood', child: Text('Blood 🩸')),
                      DropdownMenuItem(value: 'Urine', child: Text('Urine 🟡')),
                      DropdownMenuItem(value: 'Serum', child: Text('Serum 🧪')),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        selectedSampleType = value!;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                // यदि तत्कालै स्याम्पल लिने मुड छैन भने स्किप गर्न मिल्ने
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Skip / Collect Later', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
                  onPressed: () async {
                    // नयाँ स्याम्पल अब्जेक्ट
                    final newSample = {
                      'sampleId': 'SMP-${DateTime.now().millisecondsSinceEpoch}',
                      'patientId': patientId,
                      'type': selectedSampleType,
                      'collectedAt': DateTime.now().toString(),
                    };

                    // 'samples' स्टोरमा सेभ गर्ने
                    await _dbHelper.insertData('samples', newSample);

                    if (context.mounted) {
                      Navigator.pop(context); // डायलग बन्द गर्ने
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$patientName को $selectedSampleType नमूना सफलतापूर्वक संकलन गरियो!'),
                          backgroundColor: Colors.green.shade700,
                        ),
                      );
                    }
                  },
                  child: const Text('Confirm & Collect', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 💾 बिरामी दर्ता सेभ गर्ने मुख्य फङ्सन
  Future<void> _registerPatient() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final String newPatientId = 'P-${DateTime.now().millisecondsSinceEpoch}';
      final String patientName = _nameController.text;

      final newPatient = {
        'patientId': newPatientId,
        'name': patientName,
        'age': _ageController.text,
        'sex': _selectedSex,
        'referredBy': _referredByController.text.isEmpty ? 'Self' : _referredByController.text,
        'registeredAt': DateTime.now().toString(),
      };

      // १. पहिले बिरामी सेभ गर्ने
      await _dbHelper.insertData('patients', newPatient);

      // फारमका इन्पुटहरू क्लियर गर्ने
      _nameController.clear();
      _ageController.clear();
      _referredByController.clear();

      setState(() => _isSaving = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('बिरामी सफलतापूर्वक दर्ता भयो!')),
        );

        // २. 🎯 दर्ता हुने बित्तिकै तत्कालै स्वतः स्याम्पल कलेक्सन विन्डो ट्रिगर गर्ने
        _showAutoSampleCollectionDialog(context, newPatientId, patientName);
      }
    } catch (e) {
      print("बिरामी दर्ता गर्दा त्रुटि: $e");
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Patient Registration'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Container(
            maxWidth: 550,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.grey.shade300, blurRadius: 10, offset: const Offset(0, 4))
              ],
            ),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Patient Information Form',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                    ),
                    const Divider(height: 25),
                    
                    // १. बिरामीको नाम
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? 'Please enter full name' : null,
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        // २. उमेर
                        Expanded(
                          child: TextFormField(
                            controller: _ageController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Age (Yrs)',
                              prefixIcon: Icon(Icons.cake),
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) => v!.isEmpty ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        
                        // ३. लिङ्ग (Sex Dropdown)
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedSex,
                            decoration: const InputDecoration(
                              labelText: 'Sex',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Male', child: Text('Male')),
                              DropdownMenuItem(value: 'Female', child: Text('Female')),
                              DropdownMenuItem(value: 'Other', child: Text('Other')),
                            ],
                            onChanged: (v) => setState(() => _selectedSex = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ४. डाक्टर सिफारिस (Referred By)
                    TextFormField(
                      controller: _referredByController,
                      decoration: const InputDecoration(
                        labelText: 'Referred By (Doctor / Hospital)',
                        prefixIcon: Icon(Icons.local_hospital),
                        border: OutlineInputBorder(),
                        hintText: 'e.g. Dr. BPKMCH (Leave blank for Self)',
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ५. दर्ता बटन
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.how_to_reg, color: Colors.white),
                        label: _isSaving
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Register & Proceed to Sample', style: TextStyle(fontSize: 16, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade800,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isSaving ? null : _registerPatient,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}