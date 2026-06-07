import 'package:flutter/material.dart';
import 'package:bimal_pathology_system/services/database/db_helper.dart';
import 'package:bimal_pathology_system/features/samples/models/sample.dart';

/// Provider to manage the list of samples.
class SampleListProvider extends ChangeNotifier {
  final DbHelper _db = DbHelper();
  List<Sample> _samples = [];
  bool _loading = false;

  List<Sample> get samples => _samples;
  bool get isLoading => _loading;

  Future<void> loadSamples() async {
    _loading = true;
    notifyListeners();
    final raw = await _db.getAllData('samples');
    _samples = raw.map((e) => Sample.fromJson(e)).toList();
    _loading = false;
    notifyListeners();
  }

  Future<void> addSample(Sample sample) async {
    await _db.insertData('samples', sample.toJson());
    await loadSamples();
  }
}
