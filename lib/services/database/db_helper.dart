import 'dart:async';
import 'dart:html' as html; // window को लागि यो अनिवार्य छ
import 'dart:indexed_db' as idb;

class DbHelper {
  static final DbHelper _instance = DbHelper._internal();
  factory DbHelper() => _instance;
  DbHelper._internal();

  idb.Database? _database;
  final String _dbName = "BimalPathologyDB";
  final int _dbVersion = 1;

  Future<void> initDatabase() async {
    // यहाँ html.window.indexedDB प्रयोग गरिएको छ, जसले एरर हटाउँछ
    final idbFactory = html.window.indexedDB;
    
    if (idbFactory == null) {
      print("यो ब्राउजरले IndexedDB सपोर्ट गर्दैन।");
      return;
    }

    try {
      _database = await idbFactory.open(
        _dbName,
        version: _dbVersion,
        onUpgradeNeeded: _onUpgradeNeeded,
      );
      print("Chrome IndexedDB सफलतापूर्वक जडान भयो!");
    } catch (e) {
      print("IndexedDB खोल्न त्रुटि: $e");
    }
  }

  void _onUpgradeNeeded(idb.VersionChangeEvent event) {
    final idb.OpenDBRequest request = event.target as idb.OpenDBRequest;
    final idb.Database db = request.result as idb.Database;
    
    if (!db.objectStoreNames!.contains('patients')) {
      db.createObjectStore('patients', keyPath: 'patientId');
    }
    if (!db.objectStoreNames!.contains('samples')) {
      db.createObjectStore('samples', keyPath: 'sampleId');
    }
    if (!db.objectStoreNames!.contains('results')) {
      db.createObjectStore('results', keyPath: 'resultId');
    }
  }

  Future<void> insertData(String storeName, Map<String, dynamic> json) async {
    if (_database == null) return;
    final transaction = _database!.transaction(storeName, 'readwrite');
    final store = transaction.objectStore(storeName);
    await store.put(json);
    await transaction.completed;
  }

  Future<List<Map<String, dynamic>>> getAllData(String storeName) async {
    if (_database == null) return [];
    final transaction = _database!.transaction(storeName, 'readonly');
    final store = transaction.objectStore(storeName);
    
    final List<Map<String, dynamic>> records = [];
    await for (final cursor in store.openCursor(autoAdvance: true)) {
      if (cursor.value is Map) {
        records.add(Map<String, dynamic>.from(cursor.value as Map));
      }
    }
    return records;
  }
}