import 'package:flutter/material.dart';
import 'package:bimal_pathology_system/services/database/db_helper.dart';
import 'package:bimal_pathology_system/features/results/models/result.dart';

class ResultEntryProvider extends ChangeNotifier {
  final DbHelper _db = DbHelper();

  Future<void> addResult(LabResult result) async {
    await _db.insertData('results', result.toJson());
    notifyListeners();
  }
}