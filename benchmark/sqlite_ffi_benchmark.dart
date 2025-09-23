import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite FFI-based airspace indexing benchmark with real EXPLAIN QUERY PLAN
void main() async {
  print('SQLite FFI Airspace Indexing Benchmark');
  print('This runs actual SQL queries with EXPLAIN QUERY PLAN analysis');
  print('');

  // Initialize FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final benchmark = SQLiteFFIBenchmark();

  try {
    await benchmark.runFullBenchmark();
  } catch (e, stack) {
    print('Benchmark failed: $e');
    print(stack);
    exit(1);
  }
}

class SQLiteFFIBenchmark {
  static const String _geometryTable = 'airspace_geometries';

  /// Test regions
  static const regions = [
    {'name': 'Perth', 'west': 115.6, 'south': -32.1, 'east': 116.2, 'north': -31.7},
    {'name': 'Continental Australia', 'west': 112.9, 'south': -39.2, 'east': 153.6, 'north': -10.7},
    {'name': 'France', 'west': -5.2, 'south': 41.3, 'east': 9.6, 'north': 51.1},
  ];

  /// Run full benchmark
  Future<void> runFullBenchmark() async {
    print('Creating temporary SQLite database...');

    final db = await openDatabase(
      'airspace_benchmark.db',
      version: 1,
      onCreate: _createDatabase,
    );

    try {
      print('Database created with sample data');
      print('');

      final allResults = <Map<String, dynamic>>[];

      // Test each strategy
      for (int strategy = 0; strategy < 3; strategy++) {
        final strategyName = _getStrategyName(strategy);
        print('Testing $strategyName');

        // Apply indexing strategy
        await _applyStrategy(db, strategy);

        // Test each region
        for (final region in regions) {
          print('  Testing ${region['name']}...');

          final regionResults = <Map<String, dynamic>>[];

          // Run 5 times for statistical reliability
          for (int run = 1; run <= 5; run++) {
            final result = await _runQuery(db, region);
            result['strategy'] = strategyName;
            result['strategyIndex'] = strategy;
            result['run'] = run;
            regionResults.add(result);
            allResults.add(result);

            // Small delay between runs
            await Future.delayed(Duration(milliseconds: 10));
          }

          // Show statistics
          final times = regionResults.map((r) => r['durationMs'] as int).toList();
          final avgTime = times.reduce((a, b) => a + b) / times.length;
          final minTime = times.reduce(math.min);
          final maxTime = times.reduce(math.max);
          final resultCount = regionResults.first['resultCount'];

          print('    Average: ${avgTime.toStringAsFixed(1)}ms (${minTime}-${maxTime}ms), Results: $resultCount');
        }
        print('');
      }

      // Generate comprehensive report
      await _generateReport(allResults);

    } finally {
      await db.close();
      // Clean up temporary database
      try {
        await File('airspace_benchmark.db').delete();
      } catch (e) {
        // Ignore cleanup errors
      }
    }
  }

  /// Create database with production schema and sample data
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

    // Load realistic sample data
    await _loadSampleData(db);
  }

  /// Load sample airspace data for testing
  Future<void> _loadSampleData(Database db) async {
    final batch = db.batch();
    final random = math.Random(42); // Fixed seed for reproducible results

    var id = 1;

    // Generate Australia airspaces (dense in populated areas)
    for (double lat = -39.0; lat <= -10.0; lat += 0.4) {
      for (double lng = 113.0; lng <= 153.0; lng += 0.6) {
        final typeCode = _getRealisticTypeCode(random);
        final altitude = _getRealisticAltitude(random);
        final icaoClass = random.nextInt(5) + 1;

        batch.insert(_geometryTable, {
          'id': 'AU_${id++}',
          'name': 'Airspace ${id}',
          'type_code': typeCode,
          'bounds_west': lng - 0.08,
          'bounds_south': lat - 0.08,
          'bounds_east': lng + 0.08,
          'bounds_north': lat + 0.08,
          'lower_altitude_ft': altitude,
          'upper_altitude_ft': altitude + random.nextInt(8000) + 1000,
          'icao_class': icaoClass,
          'activity': random.nextInt(100),
          'country': 'AU',
          'fetch_time': DateTime.now().millisecondsSinceEpoch,
          'geometry_hash': random.nextInt(1000000).toString(),
          'coordinate_count': random.nextInt(100) + 10,
        });
      }
    }

    // Generate France airspaces (European density)
    for (double lat = 41.8; lat <= 50.8; lat += 0.25) {
      for (double lng = -4.8; lng <= 9.2; lng += 0.4) {
        final typeCode = _getRealisticTypeCode(random);
        final altitude = _getRealisticAltitude(random);
        final icaoClass = random.nextInt(5) + 1;

        batch.insert(_geometryTable, {
          'id': 'FR_${id++}',
          'name': 'Espace ${id}',
          'type_code': typeCode,
          'bounds_west': lng - 0.04,
          'bounds_south': lat - 0.04,
          'bounds_east': lng + 0.04,
          'bounds_north': lat + 0.04,
          'lower_altitude_ft': altitude,
          'upper_altitude_ft': altitude + random.nextInt(6000) + 500,
          'icao_class': icaoClass,
          'activity': random.nextInt(100),
          'country': 'FR',
          'fetch_time': DateTime.now().millisecondsSinceEpoch,
          'geometry_hash': random.nextInt(1000000).toString(),
          'coordinate_count': random.nextInt(80) + 5,
        });
      }
    }

    await batch.commit(noResult: true);

    // Count inserted records
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $_geometryTable'));
    print('Loaded $count sample airspace records');
  }

  /// Get realistic airspace type codes
  int _getRealisticTypeCode(math.Random random) {
    // Weight towards common airspace types
    final types = [1, 1, 1, 2, 2, 3, 4, 5, 6, 7, 8, 9]; // CTR, TMA common
    return types[random.nextInt(types.length)];
  }

  /// Get realistic altitude distributions
  int _getRealisticAltitude(math.Random random) {
    // Most airspaces are below 20,000 feet
    final lowAlt = random.nextInt(5000) + 500;   // 500-5,500 ft
    final midAlt = random.nextInt(10000) + 5000; // 5,000-15,000 ft
    final highAlt = random.nextInt(20000) + 15000; // 15,000-35,000 ft

    // 60% low, 30% mid, 10% high
    final roll = random.nextInt(100);
    if (roll < 60) return lowAlt;
    if (roll < 90) return midAlt;
    return highAlt;
  }

  /// Apply indexing strategy
  Future<void> _applyStrategy(Database db, int strategy) async {
    // Drop all existing indexes
    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
    );

    for (final index in indexes) {
      final indexName = index['name'] as String;
      await db.execute('DROP INDEX IF EXISTS $indexName');
    }

    // Apply strategy-specific indexes
    switch (strategy) {
      case 0: // Strategy A: Spatial index only
        await db.execute('''
          CREATE INDEX idx_geometry_spatial ON $_geometryTable(
            bounds_west, bounds_east, bounds_south, bounds_north
          )
        ''');
        break;

      case 1: // Strategy B: Spatial + separate indexes
        await db.execute('''
          CREATE INDEX idx_geometry_spatial ON $_geometryTable(
            bounds_west, bounds_east, bounds_south, bounds_north
          )
        ''');
        await db.execute('CREATE INDEX idx_geometry_type_code ON $_geometryTable(type_code)');
        await db.execute('CREATE INDEX idx_geometry_icao_class ON $_geometryTable(icao_class)');
        await db.execute('CREATE INDEX idx_geometry_lower_altitude ON $_geometryTable(lower_altitude_ft)');
        break;

      case 2: // Strategy C: Single covering index
        await db.execute('''
          CREATE INDEX idx_geometry_covering ON $_geometryTable(
            bounds_west, bounds_east, bounds_south, bounds_north,
            type_code, icao_class, lower_altitude_ft
          )
        ''');
        break;
    }
  }

  /// Run query with timing and EXPLAIN QUERY PLAN
  Future<Map<String, dynamic>> _runQuery(Database db, Map<String, dynamic> region) async {
    final west = region['west'] as double;
    final south = region['south'] as double;
    final east = region['east'] as double;
    final north = region['north'] as double;

    // Production-style query
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
    final explainResults = await db.rawQuery(explainQuery, args);

    // Run actual query with timing
    final stopwatch = Stopwatch()..start();
    final results = await db.rawQuery(query, args);
    stopwatch.stop();

    return {
      'region': region['name'],
      'durationMs': stopwatch.elapsedMilliseconds,
      'resultCount': results.length,
      'explainPlan': explainResults,
    };
  }

  /// Generate comprehensive report
  Future<void> _generateReport(List<Map<String, dynamic>> results) async {
    final reportLines = <String>[];
    reportLines.add('# SQLite Airspace Indexing Benchmark Results');
    reportLines.add('');
    reportLines.add('Generated: ${DateTime.now().toIso8601String()}');
    reportLines.add('Database: SQLite with FFI (real database operations)');
    reportLines.add('');

    // Performance summary table
    reportLines.add('## Performance Summary');
    reportLines.add('');
    reportLines.add('| Strategy | Perth (ms) | Continental AU (ms) | France (ms) | Overall Avg (ms) |');
    reportLines.add('|----------|------------|---------------------|-------------|------------------|');

    final strategies = ['Strategy A: Spatial Index Only', 'Strategy B: Spatial + Separate Indexes', 'Strategy C: Single Covering Index'];

    for (final strategy in strategies) {
      final strategyResults = results.where((r) => r['strategy'] == strategy).toList();

      final perthTimes = strategyResults.where((r) => r['region'] == 'Perth').map((r) => r['durationMs'] as int);
      final auTimes = strategyResults.where((r) => r['region'] == 'Continental Australia').map((r) => r['durationMs'] as int);
      final franceTimes = strategyResults.where((r) => r['region'] == 'France').map((r) => r['durationMs'] as int);
      final allTimes = strategyResults.map((r) => r['durationMs'] as int);

      final perthAvg = perthTimes.isNotEmpty ? perthTimes.reduce((a, b) => a + b) / perthTimes.length : 0;
      final auAvg = auTimes.isNotEmpty ? auTimes.reduce((a, b) => a + b) / auTimes.length : 0;
      final franceAvg = franceTimes.isNotEmpty ? franceTimes.reduce((a, b) => a + b) / franceTimes.length : 0;
      final overallAvg = allTimes.isNotEmpty ? allTimes.reduce((a, b) => a + b) / allTimes.length : 0;

      final shortName = strategy.replaceAll('Strategy ', '');
      reportLines.add('| $shortName | ${perthAvg.toStringAsFixed(1)} | ${auAvg.toStringAsFixed(1)} | ${franceAvg.toStringAsFixed(1)} | ${overallAvg.toStringAsFixed(1)} |');
    }

    reportLines.add('');

    // Detailed analysis
    reportLines.add('## Detailed Analysis');
    reportLines.add('');

    for (final region in regions) {
      reportLines.add('### ${region['name']}');
      reportLines.add('');

      for (final strategy in strategies) {
        final strategyResults = results.where((r) =>
          r['region'] == region['name'] && r['strategy'] == strategy
        ).map((r) => r['durationMs'] as int).toList();

        if (strategyResults.isNotEmpty) {
          strategyResults.sort();
          final mean = strategyResults.reduce((a, b) => a + b) / strategyResults.length;
          final min = strategyResults.first;
          final max = strategyResults.last;
          final variance = strategyResults.map((t) => math.pow(t - mean, 2)).reduce((a, b) => a + b) / strategyResults.length;
          final stdDev = math.sqrt(variance);
          final resultCount = results.firstWhere((r) => r['region'] == region['name'] && r['strategy'] == strategy)['resultCount'];

          reportLines.add('**$strategy**: ${mean.toStringAsFixed(2)}ms average '
                         '(${min}-${max}ms range, σ=${stdDev.toStringAsFixed(2)}) - $resultCount results');
        }
      }
      reportLines.add('');
    }

    // EXPLAIN QUERY PLAN section
    reportLines.add('## EXPLAIN QUERY PLAN Analysis');
    reportLines.add('');

    for (final strategy in strategies) {
      reportLines.add('### $strategy');
      reportLines.add('');

      // Get first result for explain plan
      final firstResult = results.firstWhere((r) => r['strategy'] == strategy);
      final explainPlan = firstResult['explainPlan'] as List<dynamic>;

      reportLines.add('**Query Plan:**');
      reportLines.add('```');
      for (final row in explainPlan) {
        final detail = row['detail'] ?? row.toString();
        reportLines.add(detail);
      }
      reportLines.add('```');
      reportLines.add('');
    }

    // Recommendations
    reportLines.add('## Recommendations');
    reportLines.add('');

    // Find best strategy for each region
    for (final region in regions) {
      final regionResults = results.where((r) => r['region'] == region['name']).toList();

      double bestAvg = double.infinity;
      String bestStrategy = '';

      for (final strategy in strategies) {
        final strategyTimes = regionResults.where((r) => r['strategy'] == strategy).map((r) => r['durationMs'] as int).toList();
        if (strategyTimes.isNotEmpty) {
          final avg = strategyTimes.reduce((a, b) => a + b) / strategyTimes.length;
          if (avg < bestAvg) {
            bestAvg = avg;
            bestStrategy = strategy;
          }
        }
      }

      reportLines.add('- **${region['name']}**: Best performance with $bestStrategy (${bestAvg.toStringAsFixed(1)}ms average)');
    }

    reportLines.add('');
    reportLines.add('## Implementation');
    reportLines.add('');
    reportLines.add('To implement the recommended covering index in production:');
    reportLines.add('');
    reportLines.add('```sql');
    reportLines.add('CREATE INDEX idx_geometry_covering ON airspace_geometries(');
    reportLines.add('  bounds_west, bounds_east, bounds_south, bounds_north,');
    reportLines.add('  type_code, icao_class, lower_altitude_ft');
    reportLines.add(');');
    reportLines.add('```');

    // Save report
    final reportContent = reportLines.join('\n');
    final file = File('results/sqlite_benchmark_results.md');
    await Directory('results').create(recursive: true);
    await file.writeAsString(reportContent);

    print('SQLite benchmark report saved to: ${file.path}');
    print('');
    print('Key findings:');

    // Show quick summary
    final bestOverall = strategies.map((strategy) {
      final strategyResults = results.where((r) => r['strategy'] == strategy);
      final avgTime = strategyResults.map((r) => r['durationMs'] as int).reduce((a, b) => a + b) / strategyResults.length;
      return {'strategy': strategy, 'avgTime': avgTime};
    }).reduce((a, b) => a['avgTime'] < b['avgTime'] ? a : b);

    print('- Best overall strategy: ${bestOverall['strategy']} (${(bestOverall['avgTime'] as double).toStringAsFixed(1)}ms average)');
    print('- Check the full report for EXPLAIN QUERY PLAN details');
  }

  String _getStrategyName(int strategy) {
    switch (strategy) {
      case 0: return 'Strategy A: Spatial Index Only';
      case 1: return 'Strategy B: Spatial + Separate Indexes';
      case 2: return 'Strategy C: Single Covering Index';
      default: return 'Unknown Strategy';
    }
  }
}