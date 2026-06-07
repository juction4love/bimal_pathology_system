import 'package:flutter/material.dart';
import 'package:bimal_pathology_system/services/database/db_helper.dart';

class ResultsEntryForm extends StatefulWidget {
  final String sampleId;
  const ResultsEntryForm({super.key, required this.sampleId});

  @override
  State<ResultsEntryForm> createState() => _ResultsEntryFormState();
}

class _ResultsEntryFormState extends State<ResultsEntryForm> { // 🔄 यहाँ नाम सच्याइयो
  final _formKey = GlobalKey<FormState>();
  final _dbHelper = DbHelper();
  
  String _selectedPanel = 'CBC'; 
  bool _isSaving = false;

  // 🔬 ल्याबका वास्तविक प्यानल, युनिट र स्वतः भरिने आधिकारिक REFERENCE RANGE
  final Map<String, List<Map<String, String>>> _panelTemplates = {
    'CBC': [
      {'name': 'Hemoglobin', 'unit': 'g/dl', 'ref': '12-15'},
      {'name': 'Total WBC Count', 'unit': '/cu mm', 'ref': '4000-11000'},
      {'name': 'RBC Count', 'unit': 'millions/cu mm', 'ref': '3.8-4.8'},
      {'name': 'Platelet Count', 'unit': 'lakhs/cu mm', 'ref': '1.5-4.5'},
    ],
    'Urine Routine': [
      {'name': 'Urine Color', 'unit': '', 'ref': 'Pale Yellow'},
      {'name': 'Transparency', 'unit': '', 'ref': 'Clear'},
      {'name': 'Urine Albumin', 'unit': '', 'ref': 'Nil'},
      {'name': 'Urine Sugar', 'unit': '', 'ref': 'Nil'},
      {'name': 'Pus Cells', 'unit': '/HPF', 'ref': '1-4'},
    ],
    'Biochemistry (Sugar/Urea)': [
      {'name': 'Blood Sugar (Random)', 'unit': 'mg/dl', 'ref': '70-140'},
      {'name': 'Serum Creatinine', 'unit': 'mg/dl', 'ref': '0.6-1.2'},
      {'name': 'Blood Urea', 'unit': 'mg/dl', 'ref': '15-45'},
    ]
  };

  // कन्ट्रोलर म्यापहरू
  final Map<String, TextEditingController> _valueControllers = {};
  final Map<String, TextEditingController> _referenceControllers = {}; 
  final Map<String, TextEditingController> _remarksControllers = {};

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  // 🔄 प्यानल अनुसार डाटाहरू स्वतः सुरुमै लोड गर्ने फङ्सन
  void _initializeControllers() {
    _valueControllers.clear();
    _referenceControllers.clear();
    _remarksControllers.clear();

    for (var param in _panelTemplates[_selectedPanel]!) {
      final String name = param['name']!;
      final String defaultRef = param['ref']!; 

      _valueControllers[name] = TextEditingController();
      _referenceControllers[name] = TextEditingController(text: defaultRef); 
      _remarksControllers[name] = TextEditingController(text: 'Normal');
    }
  }

  @override
  void dispose() {
    for (var c in _valueControllers.values) { c.dispose(); }
    for (var c in _referenceControllers.values) { c.dispose(); }
    for (var c in _remarksControllers.values) { c.dispose(); }
    super.dispose();
  }

  // 💾 डेटाबेसमा सेभ गर्ने
  Future<void> _saveAllResults() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    
    try {
      for (var param in _panelTemplates[_selectedPanel]!) {
        final paramName = param['name']!;
        final value = _valueControllers[paramName]!.text;
        final finalRef = _referenceControllers[paramName]!.text; 
        final remarks = _remarksControllers[paramName]!.text;

        final resultData = {
          'resultId': 'RES-${widget.sampleId}-$paramName',
          'sampleId': widget.sampleId,
          'parameterName': paramName,
          'value': value,
          'unit': param['unit'],
          'referenceRange': finalRef, 
          'remarks': remarks,
        };

        await _dbHelper.insertData('results', resultData);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$_selectedPanel Panel Results Saved with Reference Ranges!')),
        );
      }
    } catch (e) {
      print("त्रुटि: $e");
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.biotech, color: Colors.blue),
          const SizedBox(width: 10),
          Text('Panel Entry [Sample: ${widget.sampleId}]'),
        ],
      ),
      content: SizedBox(
        width: 750, 
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                value: _selectedPanel,
                decoration: const InputDecoration(
                  labelText: 'Select Test Panel Template',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.assignment),
                ),
                items: _panelTemplates.keys.map((String panel) {
                  return DropdownMenuItem<String>(
                    value: panel,
                    child: Text(panel, style: const TextStyle(fontWeight: FontWeight.bold)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedPanel = value;
                      _initializeControllers(); 
                    });
                  }
                },
              ),
              const SizedBox(height: 15),
              
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.0),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Text('PARAMETER', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey))),
                    Expanded(flex: 2, child: Text('VALUE / RESULT', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey))),
                    Expanded(flex: 2, child: Text('AUTO REFERENCE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey))),
                    Expanded(flex: 2, child: Text('REMARKS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey))),
                  ],
                ),
              ),
              const Divider(),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: _panelTemplates[_selectedPanel]!.map((param) {
                      final name = param['name']!;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                            ),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _valueControllers[name],
                                decoration: InputDecoration(
                                  hintText: 'Result',
                                  suffixText: param['unit'],
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (v) => v!.isEmpty ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _referenceControllers[name], 
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  border: OutlineInputBorder(),
                                  fillColor: Color(0xFFF5F5F5), // 🔄 यहाँ रङको कोड सच्याइयो
                                  filled: true,
                                ),
                                style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _remarksControllers[name],
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
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
          onPressed: _isSaving ? null : _saveAllResults,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800),
          child: _isSaving 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Save Panel Results', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}