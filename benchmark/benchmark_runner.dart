import 'dart:io';
import '../free_flight_log_app/lib/services/logging_service.dart';
import 'benchmark_database.dart';
import 'benchmark_data_loader.dart';
import 'benchmark_regions.dart';
import 'benchmark_reporter.dart';

/// Main benchmark runner for testing airspace query indexing strategies
class BenchmarkRunner {
  final BenchmarkDatabase _database = BenchmarkDatabase.instance;
  final BenchmarkDataLoader _dataLoader = BenchmarkDataLoader();
  final BenchmarkReporter _reporter = BenchmarkReporter();

  /// Indexing strategies to test
  static const List<String> indexingStrategies = [
    'Strategy A: Spatial Index Only',
    'Strategy B: Spatial + Separate Indexes',
    'Strategy C: Single Covering Index',
  ];

  /// Number of runs per test for statistical reliability
  static const int runsPerTest = 5;

  /// Run complete benchmark suite
  Future<void> runBenchmark() async {
    LoggingService.info('Starting airspace indexing benchmark');

    try {
      // Ensure data is loaded
      await _ensureDataLoaded();

      // Validate test regions
      if (!BenchmarkRegions.validateRegions()) {
        throw Exception('Test region validation failed');
      }

      // Log region information
      BenchmarkRegions.logRegionInfo();

      // Run benchmarks for each strategy
      final allResults = <Map<String, dynamic>>[];

      for (int strategyIndex = 0; strategyIndex < indexingStrategies.length; strategyIndex++) {
        final strategyName = indexingStrategies[strategyIndex];
        LoggingService.info('Testing $strategyName');

        // Apply the indexing strategy
        await _applyIndexingStrategy(strategyIndex);

        // Test each region
        for (final region in BenchmarkRegions.allRegions) {
          LoggingService.info('Testing region: ${region.name}');

          final regionResults = await _testRegion(region, strategyName, strategyIndex);
          allResults.addAll(regionResults);
        }

        LoggingService.info('Completed $strategyName');
      }

      // Generate and save report
      await _reporter.generateReport(allResults);

      LoggingService.info('Benchmark completed successfully');

    } catch (e, stack) {
      LoggingService.error('Benchmark failed', e, stack);
      rethrow;
    } finally {
      await _database.close();
    }
  }

  /// Ensure benchmark data is loaded
  Future<void> _ensureDataLoaded() async {
    if (await _dataLoader.isDataLoaded()) {
      LoggingService.info('Benchmark data already loaded');
      final stats = await _dataLoader.getLoadingStats();
      LoggingService.info('Data stats: ${stats['totalAirspaces']} total airspaces '
          '(AU: ${stats['auAirspaces']}, FR: ${stats['frAirspaces']})');
    } else {
      LoggingService.info('Loading benchmark data...');
      await _dataLoader.loadAllData();
      final stats = await _dataLoader.getLoadingStats();
      LoggingService.info('Data loaded: ${stats['totalAirspaces']} total airspaces');
    }
  }

  /// Apply specific indexing strategy
  Future<void> _applyIndexingStrategy(int strategyIndex) async {
    switch (strategyIndex) {
      case 0: // Strategy A: Spatial index only
        await _database.applyIndexingStrategyA();
        break;
      case 1: // Strategy B: Spatial + separate indexes
        await _database.applyIndexingStrategyB();
        break;
      case 2: // Strategy C: Single covering index
        await _database.applyIndexingStrategyC();
        break;
      default:
        throw Exception('Unknown indexing strategy: $strategyIndex');
    }

    // Get database statistics after applying strategy
    final stats = await _database.getStatistics();
    LoggingService.info('Applied indexing strategy. Active indexes: ${stats['indexes']}');
  }

  /// Test a specific region with current indexing strategy
  Future<List<Map<String, dynamic>>> _testRegion(
    TestRegion region,
    String strategyName,
    int strategyIndex,
  ) async {
    final results = <Map<String, dynamic>>[];
    final queryParams = BenchmarkRegions.getTypicalQueryParams(region);

    // Perform multiple runs for statistical reliability
    for (int run = 1; run <= runsPerTest; run++) {
      LoggingService.info('  Run $run/$runsPerTest for ${region.name}');

      // Clear SQLite query cache to ensure cold start
      await _clearQueryCache();

      // Execute query with timing and EXPLAIN
      final result = await _database.executeQueryWithExplain(
        west: region.west,
        south: region.south,
        east: region.east,
        north: region.north,
        countryCodes: region.countryCodes,
        maxAltitudeFt: queryParams['maxAltitudeFt'],
        excludedTypes: queryParams['excludedTypes'],
        excludedClasses: queryParams['excludedClasses'],
        orderByAltitude: false, // Test without ordering first
      );

      // Record result
      results.add({
        'strategy': strategyName,
        'strategyIndex': strategyIndex,
        'region': region.name,
        'regionDescription': region.description,
        'regionArea': region.area,
        'run': run,
        'durationMs': result['durationMs'],
        'resultCount': result['resultCount'],
        'explainPlan': result['explainPlan'],
        'queryParams': queryParams,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Small delay between runs to ensure distinct timing
      await Future.delayed(Duration(milliseconds: 100));
    }

    // Also test with ORDER BY for comparison
    LoggingService.info('  Testing with ORDER BY altitude for ${region.name}');
    await _clearQueryCache();

    final orderedResult = await _database.executeQueryWithExplain(
      west: region.west,
      south: region.south,
      east: region.east,
      north: region.north,
      countryCodes: region.countryCodes,
      maxAltitudeFt: queryParams['maxAltitudeFt'],
      excludedTypes: queryParams['excludedTypes'],
      excludedClasses: queryParams['excludedClasses'],
      orderByAltitude: true, // Test with ordering
    );

    results.add({
      'strategy': strategyName,
      'strategyIndex': strategyIndex,
      'region': region.name,
      'regionDescription': region.description,
      'regionArea': region.area,
      'run': 'ORDER_BY',
      'durationMs': orderedResult['durationMs'],
      'resultCount': orderedResult['resultCount'],
      'explainPlan': orderedResult['explainPlan'],
      'queryParams': {...queryParams, 'orderByAltitude': true},
      'timestamp': DateTime.now().toIso8601String(),
    });

    return results;
  }

  /// Clear SQLite query cache to ensure cold queries
  Future<void> _clearQueryCache() async {
    final db = await _database.database;

    // Shrink memory to force cache clear
    await db.execute('PRAGMA shrink_memory');

    // Small delay to ensure cache is cleared
    await Future.delayed(Duration(milliseconds: 50));
  }

  /// Quick test run for development
  Future<void> runQuickTest() async {
    LoggingService.info('Running quick benchmark test (1 run per test)');

    try {
      await _ensureDataLoaded();

      // Test only Perth region with Strategy A
      await _database.applyIndexingStrategyA();

      final region = BenchmarkRegions.perth;
      final queryParams = BenchmarkRegions.getTypicalQueryParams(region);

      final result = await _database.executeQueryWithExplain(
        west: region.west,
        south: region.south,
        east: region.east,
        north: region.north,
        countryCodes: region.countryCodes,
        maxAltitudeFt: queryParams['maxAltitudeFt'],
      );

      LoggingService.info('Quick test result:');
      LoggingService.info('  Region: ${region.name}');
      LoggingService.info('  Results: ${result['resultCount']}');
      LoggingService.info('  Duration: ${result['durationMs']}ms');
      LoggingService.info('  Explain plan: ${result['explainPlan']}');

    } catch (e, stack) {
      LoggingService.error('Quick test failed', e, stack);
      rethrow;
    } finally {
      await _database.close();
    }
  }
}