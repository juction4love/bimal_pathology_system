import 'package:flutter/material.dart';
import 'package:bimal_pathology_system/features/patients/models/patient.dart';
import 'package:bimal_pathology_system/services/patient_repository.dart';

/// Provider that notifies listeners when patient data changes.
/// Uses a simple `ChangeNotifier` pattern (compatible with
/// `Provider` or `ChangeNotifierProvider` in the UI).
class PatientListProvider extends ChangeNotifier {
  final PatientRepository _repository = PatientRepository();

  List<Patient> _patients = [];
  bool _isLoading = false;

  List<Patient> get patients => _patients;
  bool get isLoading => _isLoading;

  /// Load all patients from the repository.
  Future<void> loadPatients() async {
    _isLoading = true;
    notifyListeners();

    _patients = await _repository.getAllPatients();

    _isLoading = false;
    notifyListeners();
  }

  /// Create a new patient and refresh the list.
  Future<void> createPatient(Patient patient) async {
    await _repository.addPatient(patient);
    await loadPatients(); // reload list after addition
  }
}
