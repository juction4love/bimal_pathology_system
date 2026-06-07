import 'package:flutter/material.dart';
import 'package:bimal_pathology_system/services/database/db_helper.dart';
import 'package:bimal_pathology_system/features/results/models/result.dart';

class ReportsProvider extends ChangeNotifier {
  final DbHelper _db = DbHelper();
  List<LabResult> _results = [];
  List<LabResult> get results => _results;

  Future<void> loadResults() async {
    final raw = await _db.getAllData('results');
    _results = raw.map((e) => LabResult.fromJson(e)).toList();
    notifyListeners();
  }
}
