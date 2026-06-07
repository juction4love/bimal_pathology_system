import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bimal_pathology_system/app/app.dart';
// १. DbHelper अनिवार्य Import गर्ने
import 'package:bimal_pathology_system/services/database/db_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // २. एप रन हुनु भन्दा अगाडि क्रोमको IndexedDB सुरु गर्ने
  final dbHelper = DbHelper();
  await dbHelper.initDatabase();

  runApp(
    const ProviderScope(
      child: BimalPathologyApp(),
    ),
  );
}