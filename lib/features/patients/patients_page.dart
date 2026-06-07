import 'package:flutter/material.dart';
import 'package:bimal_pathology_system/services/database/db_helper.dart';
import 'package:bimal_pathology_system/features/patients/models/patient.dart'; // 🎯 भर्खरै बनाएको मोडेल Import गरियो

class PatientsPage extends StatefulWidget {
  const PatientsPage({super.key});

  @override
  State<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<PatientsPage> {
  final DbHelper _dbHelper = DbHelper();
  List<Patient> _patientsList = [];
  List<Patient> _filteredPatientsList = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadPatientsData();
  }

  // 🔄 डेटाबेसबाट बिraमीहरूको सूची तान्ने र मोडेलमा कन्भर्ट गर्ने फङ्सन
  Future<void> _loadPatientsData() async {
    setState(() => _isLoading = true);
    try {
      final rawPatients = await _dbHelper.getAllData('patients');
      
      // Map डेटालाई Patient Object को List मा बदल्ने (Using Model)
      final List<Patient> loadedPatients = rawPatients.map((p) => Patient.fromJson(p)).toList();

      // दर्ता भएको मिति अनुसार नयाँ बिरामी माथि आउने गरी क्रमबद्ध (Sort) गर्ने
      loadedPatients.sort((a, b) => b.registeredAt.compareTo(a.registeredAt));

      setState(() {
        _patientsList = loadedPatients;
        _filterPatients();
        _isLoading = false;
      });
    } catch (e) {
      print("बिरामी सूची लोड गर्दा त्रुटि: $e");
      setState(() => _isLoading = false);
    }
  }

  // 🔍 नाम वा बिरामी ID अनुसार सर्च फिल्टर लागू गर्ने
  void _filterPatients() {
    if (_searchQuery.isEmpty) {
      _filteredPatientsList = _patientsList;
    } else {
      _filteredPatientsList = _patientsList.where((patient) {
        final nameMatches = patient.name.toLowerCase().contains(_searchQuery.toLowerCase());
        final idMatches = patient.patientId.toLowerCase().contains(_searchQuery.toLowerCase());
        return nameMatches || idMatches;
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registered Patients Directory'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPatientsData,
            tooltip: 'Refresh Directory',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🔍 १. बिरामी खोज्ने अत्याधुनिक सर्च बार
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search Patient by Name or Patient ID...',
                      prefixIcon: Icon(Icons.search, color: Colors.blueGrey),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        _filterPatients();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  Text(
                    'Total Patients: ${_filteredPatientsList.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),

                  // 📊 २. बिरामीहरूको गतिशील सूची (Dynamic ListView)
                  Expanded(
                    child: _filteredPatientsList.isEmpty
                        ? const Center(
                            child: Text(
                              'कुनै पनि बिरामीको रेकर्ड फेला परेन।',
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filteredPatientsList.length,
                            itemBuilder: (context, index) {
                              final Patient patient = _filteredPatientsList[index];
                              final String formattedDate = patient.registeredAt.toLocal().toString().split(' ')[0];

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                elevation: 1,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: patient.sex.toLowerCase() == 'male'
                                        ? Colors.blue.shade100
                                        : (patient.sex.toLowerCase() == 'female' ? Colors.pink.shade100 : Colors.purple.shade100),
                                    child: Icon(
                                      Icons.person,
                                      color: patient.sex.toLowerCase() == 'male'
                                          ? Colors.blue.shade800
                                          : (patient.sex.toLowerCase() == 'female' ? Colors.pink.shade800 : Colors.purple.shade800),
                                    ),
                                  ),
                                  title: Text(
                                    patient.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(
                                      'ID: ${patient.patientId}  |  Age/Sex: ${patient.age} Yrs / ${patient.sex}\nRef By: ${patient.referredBy}',
                                      style: const TextStyle(fontSize: 13, height: 1.4),
                                    ),
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Icon(Icons.badge_outlined, size: 18, color: Colors.blueGrey),
                                      const SizedBox(height: 4),
                                      Text(
                                        formattedDate,
                                        style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}