import 'package:flutter/material.dart';
import 'package:bimal_pathology_system/services/database/db_helper.dart';
import 'package:bimal_pathology_system/features/samples/models/sample.dart';
import 'package:bimal_pathology_system/features/results/results_entry_form.dart';
import 'package:bimal_pathology_system/services/pdf_report_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final DbHelper _dbHelper = DbHelper();
  
  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _allResults = [];
  List<Map<String, dynamic>> _allSamples = [];
  List<Map<String, dynamic>> _filteredSamples = [];

  String _searchQuery = '';
  String _selectedStatusFilter = 'All'; // All, Pending, Completed
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  // 🔄 डेटाबेसबाट सम्पूर्ण तथ्याङ्क लोड गर्ने फङ्सन
  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final patientsData = await _dbHelper.getAllData('patients');
      final samplesData = await _dbHelper.getAllData('samples');
      final resultsData = await _dbHelper.getAllData('results');

      setState(() {
        _patients = patientsData;
        _allSamples = samplesData;
        _allResults = resultsData;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      print("ड्यासबोर्ड डाटा लोड गर्दा त्रुटि: $e");
      setState(() => _isLoading = false);
    }
  }

  // 🔍 सर्च र स्टेटस फिल्टर लागू गर्ने फङ्सन
  void _applyFilters() {
    List<Map<String, dynamic>> temp = [];

    for (var sample in _allSamples) {
      // यो स्याम्पलको रिजल्ट सेभ भएको छ कि छैन चेक गरेर स्थिति (Status) पत्ता लगाउने
      final hasResult = _allResults.any((r) => r['sampleId'].toString() == sample['sampleId'].toString());
      final String status = hasResult ? 'Completed' : 'Pending';

      // बिरामीको नाम खोज्ने
      final patient = _patients.firstWhere(
        (p) => p['patientId'].toString() == sample['patientId'].toString(),
        orElse: () => {'name': 'Unknown'},
      );
      final patientName = patient['name'].toString().toLowerCase();
      final sampleId = sample['sampleId'].toString().toLowerCase();

      // १. सर्च फिल्टर (नाम वा स्याम्पल ID)
      final matchesSearch = patientName.contains(_searchQuery.toLowerCase()) || sampleId.contains(_searchQuery.toLowerCase());

      // २. स्टेटस फिल्टर (All, Pending, Completed)
      bool matchesStatus = _selectedStatusFilter == 'All' || status == _selectedStatusFilter;

      if (matchesSearch && matchesStatus) {
        // नयाँ म्याप बनाएर स्टेटस र बिरामीको नाम थप्ने ताकि UI मा देखाउन सजिलो होस्
        temp.add({
          ...sample,
          'status': status,
          'patientName': patient['name'],
        });
      }
    }

    setState(() {
      _filteredSamples = temp;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 📊 संख्यात्मक तथ्याङ्क गणना (Statistics Calculation)
    final int totalPatientsToday = _patients.length; // रियल एपमा यसलाई मिति अनुसार फिल्टर गर्न सकिन्छ
    final int pendingCount = _allSamples.where((s) => !_allResults.any((r) => r['sampleId'] == s['sampleId'])).length;
    final int completedCount = _allSamples.where((s) => _allResults.any((r) => r['sampleId'] == s['sampleId'])).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bimal Pathology - Dashboard Overview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboardData,
            tooltip: 'Refresh Data',
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
                  // =================== १. तथ्याङ्क बक्सहरू (STATISTICS CARDS) ===================
                  Row(
                    children: [
                      _buildStatCard('Total Patients', totalPatientsToday.toString(), Icons.people, Colors.blue),
                      _buildStatCard('Pending Samples', pendingCount.toString(), Icons.hourglass_top, Colors.orange),
                      _buildStatCard('Completed Reports', completedCount.toString(), Icons.check_circle, Colors.green),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // =================== २. सर्च र फिल्टर नियन्त्रण खण्ड ===================
                  Row(
                    children: [
                      // सर्च बार
                      Expanded(
                        flex: 3,
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Search Patient Name or Sample ID...',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            _searchQuery = value;
                            _applyFilters();
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      // स्टेटस फिल्टर ड्रपडाउन
                      Expanded(
                        flex: 1,
                        child: DropdownButtonFormField<String>(
                          value: _selectedStatusFilter,
                          decoration: const InputDecoration(
                            labelText: 'Status Filter',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'All', child: Text('All Samples')),
                            DropdownMenuItem(value: 'Pending', child: Text('⏳ Pending')),
                            DropdownMenuItem(value: 'Completed', child: Text('✅ Completed')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              _selectedStatusFilter = value;
                              _applyFilters();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // =================== ३. फिल्टर गरिएको स्याम्पल तालिका (Data Table) ===================
                  const Text('Recent Lab Workloads', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _filteredSamples.isEmpty
                        ? const Center(child: Text('कुनै रेकर्ड फेला परेन।', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: _filteredSamples.length,
                            itemBuilder: (context, index) {
                              final sample = _filteredSamples[index];
                              final bool isDone = sample['status'] == 'Completed';

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isDone ? Colors.green.shade50 : Colors.orange.shade50,
                                    child: Icon(Icons.science, color: isDone ? Colors.green : Colors.orange),
                                  ),
                                  title: Text('${sample['patientName']} [ID: ${sample['patientId']}]'),
                                  subtitle: Text('Sample: ${sample['sampleId']} (${sample['type']})'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // स्थिति ब्याज (Status Badge)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isDone ? Colors.green : Colors.orange,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          sample['status'],
                                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // 🖨️ सिधै पिडिएफ प्रिन्ट गर्ने एक्शन बटन
                                      IconButton(
                                        icon: Icon(Icons.picture_as_pdf, color: isDone ? Colors.red : Colors.grey),
                                        tooltip: isDone ? 'Print Report' : 'Result Not Ready',
                                        onPressed: isDone
                                            ? () async {
                                                final matches = _allResults.where((r) => r['sampleId'].toString() == sample['sampleId'].toString()).toList();
                                                await PdfReportService.generateAndShowReport(
                                                  sampleId: sample['sampleId'],
                                                  patientId: sample['patientId'],
                                                  patientName: sample['patientName'],
                                                  sampleType: sample['type'],
                                                  date: sample['collectedAt'].toString().split(' ')[0],
                                                  results: matches,
                                                );
                                              }
                                            : null, // यदि रिजल्ट छैन भने प्रिन्ट बटन डिसेबल हुन्छ
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

  // कस्टुम विजेट: तथ्याङ्क कार्ड डिजाइन
  Widget _buildStatCard(String title, String count, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.only(right: 12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Text(count, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
                ],
              ),
              Icon(icon, size: 36, color: color.withOpacity(0.7)),
            ],
          ),
        ),
      ),
    );
  }
}