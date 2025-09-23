import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../services/logging_service.dart';

/// SQLite-based airspace indexing benchmark with real EXPLAIN QUERY PLAN
class SQLiteBenchmark {
  static const String _databaseName = 'airspace_benchmark.db';
  static const String _geometryTable = 'airspace_geometries';

  Database? _database;

  /// Test regions
  static const regions = [
    {'name': 'Perth', 'west': 115.6, 'south': -32.1, 'east': 116.2, 'north': -31.7},
    {'name': 'Continental Australia', 'west': 112.9, 'south': -39.2, 'east': 153.6, 'north': -10.7},
    {'name': 'France', 'west': -5.2, 'south': 41.3, 'east': 9.6, 'north': 51.1},
  ];

  /// Initialize benchmark database
  Future<void> initialize() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _databaseName);

    // Delete existing database for clean test
    await deleteDatabase(path);

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: _createDatabase,
    );

    LoggingService.info('SQLite benchmark database initialized');
  }

  /// Create database with production schema
  Future<void> _createDatabase(Database db, int version) async {
    // Create table with exact production schema
    await db.execute('''
      CREATE TABLE $_geometryTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type_code INTEGER NOT NULL,
        bounds_west REAL NOT NULL,
        bounds_south REAL NOT NULL,
        bounds_east REAL NOT NULL,
        bounds_north REAL NOT NULL,
        lower_altitude_ft INTEGER,
        upper_altitude_ft INTEGER,
        icao_class INTEGER,
        activity INTEGER,
        country TEXT,
        fetch_time INTEGER NOT NULL,
        geometry_hash TEXT NOT NULL,
        coordinate_count INTEGER NOT NULL
      )
    ''');

    // Load sample data
    await _loadSampleData(db);
  }

  /// Load sample airspace data for testing
  Future<void> _loadSampleData(Database db) async {
    LoggingService.info('Loading sample airspace data...');

    final batch = db.batch();
    final random = math.Random(42); // Fixed seed for reproducible results

    // Generate sample airspaces across Australia and France
    var id = 1;

    // Australia airspaces
    for (double lat = -39.0; lat <= -10.0; lat += 0.5) {
      for (double lng = 113.0; lng <= 153.0; lng += 0.8) {
        final typeCode = random.nextInt(10) + 1;
        final altitude = random.nextInt(20000) + 1000;
        final icaoClass = random.nextInt(5) + 1;

        batch.insert(_geometryTable, {
          'id': 'AU_${id++}',
          'name': 'Airspace $id',
          'type_code': typeCode,
          'bounds_west': lng - 0.1,
          'bounds_south': lat - 0.1,
          'bounds_east': lng + 0.1,
          'bounds_north': lat + 0.1,
          'lower_altitude_ft': altitude,
          'upper_altitude_ft': altitude + random.nextInt(10000),
          'icao_class': icaoClass,
          'activity': random.nextInt(100),
          'country': 'AU',
          'fetch_time': DateTime.now().millisecondsSinceEpoch,
          'geometry_hash': random.nextInt(1000000).toString(),
          'coordinate_count': random.nextInt(100) + 10,
        });
      }
    }

    // France airspaces
    for (double lat = 41.5; lat <= 51.0; lat += 0.3) {
      for (double lng = -5.0; lng <= 9.5; lng += 0.5) {
        final typeCode = random.nextInt(10) + 1;
        final altitude = random.nextInt(15000) + 500;
        final icaoClass = random.nextInt(5) + 1;

        batch.insert(_geometryTable, {
          'id': 'FR_${id++}',
          'name': 'Espace $id',
          'type_code': typeCode,
          'bounds_west': lng - 0.05,
          'bounds_south': lat - 0.05,
          'bounds_east': lng + 0.05,
          'bounds_north': lat + 0.05,
          'lower_altitude_ft': altitude,
          'upper_altitude_ft': altitude + random.nextInt(8000),
          'icao_class': icaoClass,
          'activity': random.nextInt(100),
          'country': lng < 2.0 ? 'FR' : 'FR',
          'fetch_time': DateTime.now().millisecondsSinceEpoch,
          'geometry_hash': random.nextInt(1000000).toString(),
          'coordinate_count': random.nextInt(80) + 5,
        });
      }
    }

    await batch.commit(noResult: true);

    // Count inserted records
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $_geometryTable'));
    LoggingService.info('Loaded $count sample airspace records');
  }

  /// Apply indexing strategy A: Spatial compound index only
  Future<void> applyStrategyA() async {
    await _dropAllIndexes();
    await _database!.execute('''
      CREATE INDEX idx_geometry_spatial ON $_geometryTable(
        bounds_west, bounds_east, bounds_south, bounds_north
      )
    ''');
    LoggingService.info('Applied Strategy A: Spatial index only');
  }

  /// Apply indexing strategy B: Spatial + separate indexes
  Future<void> applyStrategyB() async {
    await _dropAllIndexes();
    await _database!.execute('''
      CREATE INDEX idx_geometry_spatial ON $_geometryTable(
        bounds_west, bounds_east, bounds_south, bounds_north
      )
    ''');
    await _database!.execute('CREATE INDEX idx_geometry_type_code ON $_geometryTable(type_code)');
    await _database!.execute('CREATE INDEX idx_geometry_icao_class ON $_geometryTable(icao_class)');
    await _database!.execute('CREATE INDEX idx_geometry_lower_altitude ON $_geometryTable(lower_altitude_ft)');
    LoggingService.info('Applied Strategy B: Spatial + separate indexes');
  }

  /// Apply indexing strategy C: Single covering index
  Future<void> applyStrategyC() async {
    await _dropAllIndexes();
    await _database!.execute('''
      CREATE INDEX idx_geometry_covering ON $_geometryTable(
        bounds_west, bounds_east, bounds_south, bounds_north,
        type_code, icao_class, lower_altitude_ft
      )
    ''');
    LoggingService.info('Applied Strategy C: Single covering index');
  }

  /// Drop all user-created indexes
  Future<void> _dropAllIndexes() async {
    final indexes = await _database!.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
    );

    for (final index in indexes) {
      final indexName = index['name'] as String;
      await _database!.execute('DROP INDEX IF EXISTS $indexName');
    }
  }

  /// Run benchmark query with EXPLAIN QUERY PLAN
  Future<Map<String, dynamic>> runQuery(Map<String, dynamic> region) async {
    final west = region['west'] as double;
    final south = region['south'] as double;
    final east = region['east'] as double;
    final north = region['north'] as double;

    // Build production-style query
    const query = '''
      SELECT * FROM $_geometryTable
      WHERE bounds_west <= ? AND bounds_east >= ?
        AND bounds_south <= ? AND bounds_north >= ?
        AND (lower_altitude_ft IS NULL OR lower_altitude_ft <= 20000)
        AND type_code NOT IN (4, 5, 6)
    ''';

    final args = [east, west, north, south];

    // Get EXPLAIN QUERY PLAN
    final explainQuery = 'EXPLAIN QUERY PLAN $query';
    final explainResults = await _database!.rawQuery(explainQuery, args);

    // Run actual query with timing
    final stopwatch = Stopwatch()..start();
    final results = await _database!.rawQuery(query, args);
    stopwatch.stop();

    return {
      'region': region['name'],
      'durationMs': stopwatch.elapsedMilliseconds,
      'resultCount': results.length,
      'explainPlan': explainResults,
    };
  }

  /// Run complete benchmark
  Future<Map<String, dynamic>> runBenchmark() async {
    final results = <String, List<Map<String, dynamic>>>{};

    for (int strategy = 0; strategy < 3; strategy++) {
      final strategyName = _getStrategyName(strategy);
      LoggingService.info('Testing $strategyName');

      // Apply indexing strategy
      switch (strategy) {
        case 0: await applyStrategyA(); break;
        case 1: await applyStrategyB(); break;
        case 2: await applyStrategyC(); break;
      }

      final strategyResults = <Map<String, dynamic>>[];

      // Test each region multiple times
      for (final region in regions) {
        LoggingService.info('  Testing ${region['name']}');

        final regionResults = <Map<String, dynamic>>[];
        for (int run = 0; run < 5; run++) {
          final result = await runQuery(region);
          result['strategy'] = strategyName;
          result['run'] = run + 1;
          regionResults.add(result);

          // Small delay between runs
          await Future.delayed(Duration(milliseconds: 10));
        }

        strategyResults.addAll(regionResults);

        // Show average for this region
        final times = regionResults.map((r) => r['durationMs'] as int).toList();
        final avgTime = times.reduce((a, b) => a + b) / times.length;
        final resultCount = regionResults.first['resultCount'];
        LoggingService.info('    Average: ${avgTime.toStringAsFixed(1)}ms, Results: $resultCount');
      }

      results[strategyName] = strategyResults;
    }

    return results;
  }

  /// Generate comprehensive report
  Future<void> generateReport(Map<String, dynamic> results) async {
    final reportLines = <String>[];
    reportLines.add('# SQLite Airspace Indexing Benchmark Results');
    reportLines.add('');
    reportLines.add('Generated: ${DateTime.now().toIso8601String()}');
    reportLines.add('');

    // Performance summary
    reportLines.add('## Performance Summary');
    reportLines.add('');
    reportLines.add('| Strategy | Perth (ms) | Continental AU (ms) | France (ms) |');
    reportLines.add('|----------|------------|---------------------|-------------|');

    for (final entry in results.entries) {
      final strategyName = entry.key as String;
      final strategyResults = entry.value as List<Map<String, dynamic>>;

      final perthResults = strategyResults.where((r) => r['region'] == 'Perth').map((r) => r['durationMs'] as int);
      final auResults = strategyResults.where((r) => r['region'] == 'Continental Australia').map((r) => r['durationMs'] as int);
      final franceResults = strategyResults.where((r) => r['region'] == 'France').map((r) => r['durationMs'] as int);

      final perthAvg = perthResults.isNotEmpty ? perthResults.reduce((a, b) => a + b) / perthResults.length : 0;
      final auAvg = auResults.isNotEmpty ? auResults.reduce((a, b) => a + b) / auResults.length : 0;
      final franceAvg = franceResults.isNotEmpty ? franceResults.reduce((a, b) => a + b) / franceResults.length : 0;

      final shortName = strategyName.replaceAll('Strategy ', '').replaceAll(': ', ': ');
      reportLines.add('| $shortName | ${perthAvg.toStringAsFixed(1)} | ${auAvg.toStringAsFixed(1)} | ${franceAvg.toStringAsFixed(1)} |');
    }

    reportLines.add('');

    // EXPLAIN QUERY PLAN section
    reportLines.add('## EXPLAIN QUERY PLAN Analysis');
    reportLines.add('');

    for (final entry in results.entries) {
      final strategyName = entry.key as String;
      final strategyResults = entry.value as List<Map<String, dynamic>>;

      reportLines.add('### $strategyName');
      reportLines.add('');

      // Get first result for explain plan (should be same for all runs)
      final firstResult = strategyResults.first;
      final explainPlan = firstResult['explainPlan'] as List<dynamic>;

      reportLines.add('```');
      for (final row in explainPlan) {
        reportLines.add(row['detail'] ?? row.toString());
      }
      reportLines.add('```');
      reportLines.add('');
    }

    // Save report
    final reportContent = reportLines.join('\n');
    final file = File('sqlite_benchmark_results.md');
    await file.writeAsString(reportContent);

    LoggingService.info('SQLite benchmark report saved to: ${file.path}');
  }

  String _getStrategyName(int strategy) {
    switch (strategy) {
      case 0: return 'Strategy A: Spatial Index Only';
      case 1: return 'Strategy B: Spatial + Separate Indexes';
      case 2: return 'Strategy C: Single Covering Index';
      default: return 'Unknown Strategy';
    }
  }

  /// Close database
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}