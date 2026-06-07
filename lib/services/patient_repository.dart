import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bimal_pathology_system/features/patients/models/patient.dart';
import 'package:bimal_pathology_system/services/database/db_helper.dart';

class PatientRepository {
  final DbHelper _dbHelper = DbHelper();
  final List<Patient> _mockPatients = [];

  // १. सबै बिरामीहरू तान्ने मेथड
  Future<List<Patient>> getAllPatients() async {
    final rawData = await _dbHelper.getAllData('patients');
    if (rawData.isEmpty) {
      return _mockPatients; // यदि DB खाली छ भने डमी खाली लिष्ट दिने
    }
    return rawData.map((json) => Patient.fromJson(json)).toList();
  }

  // २. नयाँ बिरामी थप्ने हराएको मेथड (patientId प्रयोग गरेर)
  Future<void> addPatient(Patient patient) async {
    await _dbHelper.insertData('patients', patient.toJson());
  }

  // ३. ID फिल्टर सच्याइएको खण्ड
  Patient? getPatientById(String id) {
    // पुराना `id` को सट्टा `patientId` सँग म्याच गर्ने
    for (var p in _mockPatients) {
      if (p.patientId == id) return p;
    }
    return null;
  }
}