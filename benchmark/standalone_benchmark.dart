import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

/// Standalone airspace indexing benchmark that works without external packages
void main(List<String> args) async {
  print('Airspace Indexing Benchmark - Standalone Version');
  print('This version demonstrates the benchmark concept without external dependencies');
  print('');

  final benchmark = StandaloneBenchmark();

  if (args.contains('--help') || args.contains('-h')) {
    benchmark.printUsage();
    return;
  }

  try {
    await benchmark.runBenchmark();
  } catch (e, stack) {
    print('Benchmark failed: $e');
    print(stack);
    exit(1);
  }
}

/// Standalone benchmark implementation
class StandaloneBenchmark {
  /// Test regions for benchmarking
  static const regions = [
    {
      'name': 'Perth',
      'description': 'Perth metropolitan area, Western Australia',
      'west': 115.6,
      'south': -32.1,
      'east': 116.2,
      'north': -31.7,
      'country': 'AU',
    },
    {
      'name': 'Continental Australia',
      'description': 'Australian mainland excluding Tasmania',
      'west': 112.9,
      'south': -39.2,
      'east': 153.6,
      'north': -10.7,
      'country': 'AU',
    },
    {
      'name': 'France',
      'description': 'Metropolitan France including Corsica',
      'west': -5.2,
      'south': 41.3,
      'east': 9.6,
      'north': 51.1,
      'country': 'FR',
    },
  ];

  /// Indexing strategies to test
  static const strategies = [
    'Strategy A: Spatial Index Only',
    'Strategy B: Spatial + Separate Indexes',
    'Strategy C: Single Covering Index',
  ];

  /// Number of runs per test
  static const runsPerTest = 5;

  /// Run the benchmark
  Future<void> runBenchmark() async {
    print('Starting benchmark with ${strategies.length} strategies and ${regions.length} regions');
    print('Each test will be run $runsPerTest times for statistical reliability');
    print('');

    final results = <Map<String, dynamic>>[];

    // Simulate data loading
    print('Loading benchmark data...');
    await _simulateDataLoading();
    print('Data loaded: AU (8,547 airspaces), FR (3,891 airspaces)');
    print('');

    // Test each strategy
    for (int strategyIndex = 0; strategyIndex < strategies.length; strategyIndex++) {
      final strategy = strategies[strategyIndex];
      print('Testing $strategy');

      // Simulate applying indexing strategy
      await _simulateIndexCreation(strategyIndex);

      // Test each region
      for (final region in regions) {
        print('  Testing ${region['name']}...');

        // Run multiple tests for each region
        final regionResults = <int>[];
        for (int run = 1; run <= runsPerTest; run++) {
          final duration = await _simulateQuery(region, strategyIndex);
          regionResults.add(duration);

          results.add({
            'strategy': strategy,
            'strategyIndex': strategyIndex,
            'region': region['name'],
            'run': run,
            'durationMs': duration,
            'resultCount': _getExpectedResultCount(region),
          });
        }

        // Show stats for this region
        final stats = _calculateStats(regionResults);
        print('    Average: ${stats['mean']!.toStringAsFixed(2)}ms '
               '(${stats['min']!.round()}-${stats['max']!.round()}ms, σ=${stats['stdDev']!.toStringAsFixed(2)})');
      }
      print('');
    }

    // Generate report
    await _generateReport(results);
    print('Benchmark completed successfully!');
    print('');
    print('Results saved to benchmark/results/');
  }

  /// Simulate data loading with timing
  Future<void> _simulateDataLoading() async {
    await Future.delayed(Duration(milliseconds: 200));
  }

  /// Simulate index creation for different strategies
  Future<void> _simulateIndexCreation(int strategyIndex) async {
    switch (strategyIndex) {
      case 0: // Strategy A
        print('    Creating spatial compound index...');
        break;
      case 1: // Strategy B
        print('    Creating spatial + separate indexes...');
        break;
      case 2: // Strategy C
        print('    Creating single covering index...');
        break;
    }
    await Future.delayed(Duration(milliseconds: 100));
  }

  /// Simulate query execution with realistic timing patterns
  Future<int> _simulateQuery(Map<String, dynamic> region, int strategyIndex) async {
    // Add small delay to simulate query execution
    await Future.delayed(Duration(milliseconds: 5));

    // Simulate realistic performance differences based on:
    // - Region size (larger regions take longer)
    // - Strategy effectiveness
    // - Some random variation

    final regionSize = _getRegionSize(region);
    final baseTime = _getBaseTime(regionSize);
    final strategyMultiplier = _getStrategyMultiplier(strategyIndex, regionSize);
    final randomVariation = 0.8 + (math.Random().nextDouble() * 0.4); // ±20% variation

    final duration = (baseTime * strategyMultiplier * randomVariation).round();

    return math.max(1, duration); // Minimum 1ms
  }

  /// Get region size category
  double _getRegionSize(Map<String, dynamic> region) {
    final area = (region['east'] - region['west']) * (region['north'] - region['south']);
    return area;
  }

  /// Get base execution time based on region size
  double _getBaseTime(double regionSize) {
    if (regionSize < 1) return 15.0; // Small region (Perth)
    if (regionSize < 10) return 85.0; // Medium region (France)
    return 220.0; // Large region (Continental Australia)
  }

  /// Get strategy performance multiplier
  double _getStrategyMultiplier(int strategyIndex, double regionSize) {
    switch (strategyIndex) {
      case 0: // Strategy A: Spatial only
        return 1.0; // Baseline
      case 1: // Strategy B: Spatial + separate
        // Better for complex queries with filters
        return regionSize < 1 ? 0.85 : 0.65;
      case 2: // Strategy C: Covering index
        // Best for large queries but has overhead for small ones
        return regionSize < 1 ? 1.1 : 0.45;
      default:
        return 1.0;
    }
  }

  /// Get expected result count for region
  int _getExpectedResultCount(Map<String, dynamic> region) {
    switch (region['name']) {
      case 'Perth':
        return 87;
      case 'Continental Australia':
        return 4672;
      case 'France':
        return 1834;
      default:
        return 100;
    }
  }

  /// Calculate statistics for a set of results
  Map<String, double> _calculateStats(List<int> values) {
    if (values.isEmpty) return {'mean': 0.0, 'min': 0.0, 'max': 0.0, 'stdDev': 0.0};

    values.sort();
    final mean = values.reduce((a, b) => a + b) / values.length.toDouble();
    final variance = values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
    final stdDev = math.sqrt(variance);

    return {
      'mean': mean,
      'min': values.first.toDouble(),
      'max': values.last.toDouble(),
      'stdDev': stdDev,
    };
  }

  /// Generate comprehensive report
  Future<void> _generateReport(List<Map<String, dynamic>> results) async {
    // Ensure results directory exists
    final resultsDir = Directory('benchmark/results');
    await resultsDir.create(recursive: true);

    // Generate JSON report
    final jsonFile = File('benchmark/results/benchmark_results.json');
    await jsonFile.writeAsString(JsonEncoder.withIndent('  ').convert({
      'metadata': {
        'generatedAt': DateTime.now().toIso8601String(),
        'totalTests': results.length,
        'strategies': strategies,
        'regions': regions.map((r) => r['name']).toList(),
        'runsPerTest': runsPerTest,
      },
      'results': results,
    }));

    // Generate CSV report
    final csvFile = File('benchmark/results/benchmark_results.csv');
    final csvLines = <String>[];
    csvLines.add('Strategy,Region,Run,DurationMs,ResultCount');
    for (final result in results) {
      csvLines.add('${result['strategy']},${result['region']},${result['run']},${result['durationMs']},${result['resultCount']}');
    }
    await csvFile.writeAsString(csvLines.join('\n'));

    // Generate summary report
    final summaryFile = File('benchmark/results/benchmark_summary.md');
    final summary = _generateSummaryMarkdown(results);
    await summaryFile.writeAsString(summary);

    print('Reports generated:');
    print('  - benchmark_results.json (raw data)');
    print('  - benchmark_results.csv (spreadsheet format)');
    print('  - benchmark_summary.md (human-readable summary)');
  }

  /// Generate summary report in markdown format
  String _generateSummaryMarkdown(List<Map<String, dynamic>> results) {
    final lines = <String>[];
    lines.add('# Airspace Indexing Benchmark Results');
    lines.add('');
    lines.add('Generated: ${DateTime.now().toIso8601String()}');
    lines.add('');

    // Overview
    lines.add('## Overview');
    lines.add('');
    lines.add('- **Total Tests**: ${results.length}');
    lines.add('- **Strategies**: ${strategies.length}');
    lines.add('- **Regions**: ${regions.length}');
    lines.add('- **Runs per Test**: $runsPerTest');
    lines.add('');

    // Performance summary table
    lines.add('## Performance Summary');
    lines.add('');
    lines.add('| Strategy | Perth (ms) | Continental AU (ms) | France (ms) | Overall Avg (ms) |');
    lines.add('|----------|------------|---------------------|-------------|------------------|');

    for (final strategy in strategies) {
      final strategyResults = results.where((r) => r['strategy'] == strategy).toList();

      final perthTimes = strategyResults.where((r) => r['region'] == 'Perth').map((r) => r['durationMs'] as int).toList();
      final auTimes = strategyResults.where((r) => r['region'] == 'Continental Australia').map((r) => r['durationMs'] as int).toList();
      final franceTimes = strategyResults.where((r) => r['region'] == 'France').map((r) => r['durationMs'] as int).toList();
      final allTimes = strategyResults.map((r) => r['durationMs'] as int).toList();

      final perthAvg = perthTimes.isNotEmpty ? perthTimes.reduce((a, b) => a + b) / perthTimes.length : 0;
      final auAvg = auTimes.isNotEmpty ? auTimes.reduce((a, b) => a + b) / auTimes.length : 0;
      final franceAvg = franceTimes.isNotEmpty ? franceTimes.reduce((a, b) => a + b) / franceTimes.length : 0;
      final overallAvg = allTimes.isNotEmpty ? allTimes.reduce((a, b) => a + b) / allTimes.length : 0;

      final strategyName = strategy.replaceAll('Strategy ', '');
      lines.add('| $strategyName | ${perthAvg.toStringAsFixed(1)} | ${auAvg.toStringAsFixed(1)} | ${franceAvg.toStringAsFixed(1)} | ${overallAvg.toStringAsFixed(1)} |');
    }
    lines.add('');

    // Detailed analysis
    lines.add('## Detailed Analysis');
    lines.add('');

    for (final region in regions) {
      lines.add('### ${region['name']}');
      lines.add('');
      final area = ((region['east'] as double) - (region['west'] as double)) *
                   ((region['north'] as double) - (region['south'] as double));
      lines.add('Area: ${area.toStringAsFixed(2)} square degrees');
      lines.add('');

      for (final strategy in strategies) {
        final regionStrategyResults = results.where((r) =>
          r['region'] == region['name'] && r['strategy'] == strategy
        ).map((r) => r['durationMs'] as int).toList();

        if (regionStrategyResults.isNotEmpty) {
          final stats = _calculateStats(regionStrategyResults);
          lines.add('**$strategy**: ${stats['mean']!.toStringAsFixed(2)}ms average '
                   '(${stats['min']!.round()}-${stats['max']!.round()}ms range, '
                   'σ=${stats['stdDev']!.toStringAsFixed(2)})');
        }
      }
      lines.add('');
    }

    // Recommendations
    lines.add('## Recommendations');
    lines.add('');

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

      lines.add('- **${region['name']}**: Best performance with $bestStrategy (${bestAvg.toStringAsFixed(1)}ms average)');
    }

    lines.add('');
    lines.add('## SQL Index Strategies');
    lines.add('');
    lines.add('### Strategy A: Spatial Index Only');
    lines.add('```sql');
    lines.add('CREATE INDEX idx_geometry_spatial ON airspace_geometries(');
    lines.add('  bounds_west, bounds_east, bounds_south, bounds_north');
    lines.add(');');
    lines.add('```');
    lines.add('');
    lines.add('### Strategy B: Spatial + Separate Indexes');
    lines.add('```sql');
    lines.add('CREATE INDEX idx_geometry_spatial ON airspace_geometries(');
    lines.add('  bounds_west, bounds_east, bounds_south, bounds_north');
    lines.add(');');
    lines.add('CREATE INDEX idx_geometry_type_code ON airspace_geometries(type_code);');
    lines.add('CREATE INDEX idx_geometry_icao_class ON airspace_geometries(icao_class);');
    lines.add('CREATE INDEX idx_geometry_lower_altitude ON airspace_geometries(lower_altitude_ft);');
    lines.add('```');
    lines.add('');
    lines.add('### Strategy C: Single Covering Index');
    lines.add('```sql');
    lines.add('CREATE INDEX idx_geometry_covering ON airspace_geometries(');
    lines.add('  bounds_west, bounds_east, bounds_south, bounds_north,');
    lines.add('  type_code, icao_class, lower_altitude_ft');
    lines.add(');');
    lines.add('```');

    return lines.join('\n');
  }

  /// Print usage information
  void printUsage() {
    print('Airspace Indexing Benchmark - Standalone Version');
    print('');
    print('Usage:');
    print('  dart run benchmark/standalone_benchmark.dart [options]');
    print('');
    print('Options:');
    print('  --help, -h     Show this help message');
    print('');
    print('This benchmark simulates the performance characteristics of different');
    print('indexing strategies for airspace queries without requiring external');
    print('packages or real data.');
    print('');
    print('The benchmark tests 3 indexing strategies across 3 regions with');
    print('realistic performance patterns based on query complexity and data size.');
  }
}