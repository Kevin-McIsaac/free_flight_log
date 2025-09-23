import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import '../free_flight_log_app/lib/services/logging_service.dart';

/// Results reporter for airspace indexing benchmark
class BenchmarkReporter {

  /// Generate comprehensive benchmark report
  Future<void> generateReport(List<Map<String, dynamic>> results) async {
    LoggingService.info('Generating benchmark report from ${results.length} test results');

    try {
      // Generate JSON report
      await _generateJsonReport(results);

      // Generate CSV report
      await _generateCsvReport(results);

      // Generate EXPLAIN plans report
      await _generateExplainReport(results);

      // Generate summary report
      await _generateSummaryReport(results);

      LoggingService.info('All benchmark reports generated successfully');

    } catch (e, stack) {
      LoggingService.error('Failed to generate benchmark report', e, stack);
      rethrow;
    }
  }

  /// Generate detailed JSON report with all data
  Future<void> _generateJsonReport(List<Map<String, dynamic>> results) async {
    final file = File('benchmark/results/benchmark_results.json');

    final reportData = {
      'metadata': {
        'generatedAt': DateTime.now().toIso8601String(),
        'totalTests': results.length,
        'runsPerStrategy': _countRunsPerStrategy(results),
        'regions': _getUniqueRegions(results),
        'strategies': _getUniqueStrategies(results),
      },
      'results': results,
      'statistics': _calculateStatistics(results),
    };

    await file.writeAsString(JsonEncoder.withIndent('  ').convert(reportData));
    LoggingService.info('JSON report saved: ${file.path}');
  }

  /// Generate CSV report for easy analysis in spreadsheets
  Future<void> _generateCsvReport(List<Map<String, dynamic>> results) async {
    final file = File('benchmark/results/benchmark_results.csv');

    final csvLines = <String>[];

    // CSV Header
    csvLines.add('Strategy,StrategyIndex,Region,RegionArea,Run,DurationMs,ResultCount,QueryType');

    // Data rows
    for (final result in results) {
      final queryType = result['run'] == 'ORDER_BY' ? 'WITH_ORDER_BY' : 'BASIC';
      csvLines.add([
        result['strategy'],
        result['strategyIndex'],
        result['region'],
        result['regionArea'].toStringAsFixed(2),
        result['run'],
        result['durationMs'],
        result['resultCount'],
        queryType,
      ].map((v) => '"$v"').join(','));
    }

    await file.writeAsString(csvLines.join('\n'));
    LoggingService.info('CSV report saved: ${file.path}');
  }

  /// Generate EXPLAIN QUERY PLAN analysis
  Future<void> _generateExplainReport(List<Map<String, dynamic>> results) async {
    final file = File('benchmark/results/explain_plans.txt');

    final explainLines = <String>[];
    explainLines.add('AIRSPACE INDEXING BENCHMARK - EXPLAIN QUERY PLAN ANALYSIS');
    explainLines.add('Generated at: ${DateTime.now().toIso8601String()}');
    explainLines.add('=' * 80);

    // Group by strategy and region
    final groupedResults = <String, List<Map<String, dynamic>>>{};
    for (final result in results) {
      final key = '${result['strategy']}_${result['region']}';
      groupedResults.putIfAbsent(key, () => []).add(result);
    }

    for (final entry in groupedResults.entries) {
      final parts = entry.key.split('_');
      final strategy = parts.take(parts.length - 1).join('_');
      final region = parts.last;

      explainLines.add('');
      explainLines.add('Strategy: $strategy');
      explainLines.add('Region: $region');
      explainLines.add('-' * 40);

      // Take first result for explain plan (they should be the same for the same strategy/region)
      final firstResult = entry.value.first;
      final explainPlan = firstResult['explainPlan'] as List<dynamic>;

      for (final planRow in explainPlan) {
        explainLines.add('${planRow['detail'] ?? planRow['notused'] ?? planRow}');
      }

      // Add performance summary for this combination
      final timings = entry.value
          .where((r) => r['run'] != 'ORDER_BY')
          .map((r) => r['durationMs'] as int)
          .toList();

      if (timings.isNotEmpty) {
        final stats = _calculateTimingStats(timings);
        explainLines.add('');
        explainLines.add('Performance (${timings.length} runs):');
        explainLines.add('  Mean: ${stats['mean'].toStringAsFixed(2)}ms');
        explainLines.add('  Median: ${stats['median'].toStringAsFixed(2)}ms');
        explainLines.add('  Std Dev: ${stats['stdDev'].toStringAsFixed(2)}ms');
        explainLines.add('  Min: ${stats['min']}ms, Max: ${stats['max']}ms');
      }
    }

    await file.writeAsString(explainLines.join('\n'));
    LoggingService.info('EXPLAIN plans report saved: ${file.path}');
  }

  /// Generate human-readable summary report
  Future<void> _generateSummaryReport(List<Map<String, dynamic>> results) async {
    final file = File('benchmark/results/benchmark_summary.md');

    final summaryLines = <String>[];
    summaryLines.add('# Airspace Indexing Benchmark Results');
    summaryLines.add('');
    summaryLines.add('Generated: ${DateTime.now().toIso8601String()}');
    summaryLines.add('');

    // Overview
    summaryLines.add('## Overview');
    summaryLines.add('');
    summaryLines.add('- **Total Tests**: ${results.length}');
    summaryLines.add('- **Strategies Tested**: ${_getUniqueStrategies(results).length}');
    summaryLines.add('- **Regions Tested**: ${_getUniqueRegions(results).length}');
    summaryLines.add('- **Runs per Test**: ${_countRunsPerStrategy(results)}');
    summaryLines.add('');

    // Strategy Performance Summary
    summaryLines.add('## Strategy Performance Summary');
    summaryLines.add('');
    summaryLines.add('| Strategy | Avg Duration (ms) | Min (ms) | Max (ms) | Std Dev (ms) |');
    summaryLines.add('|----------|-------------------|----------|----------|--------------|');

    final strategyStats = _calculateStrategyStatistics(results);
    for (final strategy in strategyStats.keys) {
      final stats = strategyStats[strategy]!;
      summaryLines.add('| ${strategy.replaceAll('Strategy ', '')} | '
          '${stats['mean'].toStringAsFixed(2)} | '
          '${stats['min']} | '
          '${stats['max']} | '
          '${stats['stdDev'].toStringAsFixed(2)} |');
    }
    summaryLines.add('');

    // Region Performance Summary
    summaryLines.add('## Performance by Region');
    summaryLines.add('');

    for (final region in _getUniqueRegions(results)) {
      summaryLines.add('### $region');
      summaryLines.add('');
      summaryLines.add('| Strategy | Avg Duration (ms) | Result Count | Index Usage |');
      summaryLines.add('|----------|-------------------|--------------|-------------|');

      for (final strategy in _getUniqueStrategies(results)) {
        final regionResults = results.where((r) =>
            r['region'] == region &&
            r['strategy'] == strategy &&
            r['run'] != 'ORDER_BY').toList();

        if (regionResults.isNotEmpty) {
          final timings = regionResults.map((r) => r['durationMs'] as int).toList();
          final stats = _calculateTimingStats(timings);
          final resultCount = regionResults.first['resultCount'];

          // Extract index usage from explain plan
          final explainPlan = regionResults.first['explainPlan'] as List<dynamic>;
          final indexUsage = _extractIndexUsage(explainPlan);

          summaryLines.add('| ${strategy.replaceAll('Strategy ', '')} | '
              '${stats['mean'].toStringAsFixed(2)} | '
              '$resultCount | '
              '$indexUsage |');
        }
      }
      summaryLines.add('');
    }

    // Recommendations
    summaryLines.add('## Recommendations');
    summaryLines.add('');
    final recommendations = _generateRecommendations(results);
    for (final recommendation in recommendations) {
      summaryLines.add('- $recommendation');
    }
    summaryLines.add('');

    await file.writeAsString(summaryLines.join('\n'));
    LoggingService.info('Summary report saved: ${file.path}');
  }

  /// Calculate statistics for all results
  Map<String, dynamic> _calculateStatistics(List<Map<String, dynamic>> results) {
    final stats = <String, dynamic>{};

    // Calculate per-strategy statistics
    stats['byStrategy'] = _calculateStrategyStatistics(results);

    // Calculate per-region statistics
    stats['byRegion'] = _calculateRegionStatistics(results);

    return stats;
  }

  /// Calculate statistics by strategy
  Map<String, Map<String, dynamic>> _calculateStrategyStatistics(List<Map<String, dynamic>> results) {
    final strategyStats = <String, Map<String, dynamic>>{};

    for (final strategy in _getUniqueStrategies(results)) {
      final strategyResults = results.where((r) =>
          r['strategy'] == strategy && r['run'] != 'ORDER_BY').toList();

      if (strategyResults.isNotEmpty) {
        final timings = strategyResults.map((r) => r['durationMs'] as int).toList();
        strategyStats[strategy] = _calculateTimingStats(timings);
      }
    }

    return strategyStats;
  }

  /// Calculate statistics by region
  Map<String, Map<String, dynamic>> _calculateRegionStatistics(List<Map<String, dynamic>> results) {
    final regionStats = <String, Map<String, dynamic>>{};

    for (final region in _getUniqueRegions(results)) {
      final regionResults = results.where((r) =>
          r['region'] == region && r['run'] != 'ORDER_BY').toList();

      if (regionResults.isNotEmpty) {
        final timings = regionResults.map((r) => r['durationMs'] as int).toList();
        regionStats[region] = _calculateTimingStats(timings);
      }
    }

    return regionStats;
  }

  /// Calculate timing statistics for a list of durations
  Map<String, dynamic> _calculateTimingStats(List<int> timings) {
    if (timings.isEmpty) {
      return {'mean': 0.0, 'median': 0.0, 'stdDev': 0.0, 'min': 0, 'max': 0, 'count': 0};
    }

    timings.sort();
    final count = timings.length;
    final sum = timings.reduce((a, b) => a + b);
    final mean = sum / count;

    final median = count % 2 == 0
        ? (timings[count ~/ 2 - 1] + timings[count ~/ 2]) / 2.0
        : timings[count ~/ 2].toDouble();

    final variance = timings.map((t) => math.pow(t - mean, 2)).reduce((a, b) => a + b) / count;
    final stdDev = math.sqrt(variance);

    return {
      'mean': mean,
      'median': median,
      'stdDev': stdDev,
      'min': timings.first,
      'max': timings.last,
      'count': count,
    };
  }

  /// Extract index usage information from explain plan
  String _extractIndexUsage(List<dynamic> explainPlan) {
    for (final planRow in explainPlan) {
      final detail = (planRow['detail'] ?? planRow['notused'] ?? planRow).toString();
      if (detail.contains('USING INDEX')) {
        final match = RegExp(r'USING INDEX (\w+)').firstMatch(detail);
        if (match != null) {
          return match.group(1)!;
        }
        return 'Index Used';
      }
    }
    return 'Table Scan';
  }

  /// Generate performance-based recommendations
  List<String> _generateRecommendations(List<Map<String, dynamic>> results) {
    final recommendations = <String>[];

    // Find best performing strategy overall
    final strategyStats = _calculateStrategyStatistics(results);
    final bestStrategy = strategyStats.entries
        .reduce((a, b) => a.value['mean'] < b.value['mean'] ? a : b);

    recommendations.add('**Best Overall Strategy**: ${bestStrategy.key} '
        '(Average: ${bestStrategy.value['mean'].toStringAsFixed(2)}ms)');

    // Check for significant performance differences
    final allMeans = strategyStats.values.map((s) => s['mean'] as double).toList();
    if (allMeans.isNotEmpty) {
      final minMean = allMeans.reduce(math.min);
      final maxMean = allMeans.reduce(math.max);
      final improvementPercent = ((maxMean - minMean) / maxMean * 100);

      if (improvementPercent > 20) {
        recommendations.add('**Significant Performance Difference**: Up to '
            '${improvementPercent.toStringAsFixed(1)}% improvement possible with optimal indexing');
      }
    }

    // Region-specific recommendations
    for (final region in _getUniqueRegions(results)) {
      final regionResults = results.where((r) => r['region'] == region && r['run'] != 'ORDER_BY').toList();
      if (regionResults.isNotEmpty) {
        final bestForRegion = regionResults
            .reduce((a, b) => (a['durationMs'] as int) < (b['durationMs'] as int) ? a : b);

        recommendations.add('**${region}**: Best performance with ${bestForRegion['strategy']} '
            '(${bestForRegion['durationMs']}ms, ${bestForRegion['resultCount']} results)');
      }
    }

    return recommendations;
  }

  /// Helper methods
  List<String> _getUniqueStrategies(List<Map<String, dynamic>> results) {
    return results.map((r) => r['strategy'] as String).toSet().toList()..sort();
  }

  List<String> _getUniqueRegions(List<Map<String, dynamic>> results) {
    return results.map((r) => r['region'] as String).toSet().toList()..sort();
  }

  int _countRunsPerStrategy(List<Map<String, dynamic>> results) {
    final firstStrategy = results.isNotEmpty ? results.first['strategy'] : '';
    final firstRegion = results.isNotEmpty ? results.first['region'] : '';

    return results
        .where((r) => r['strategy'] == firstStrategy && r['region'] == firstRegion && r['run'] != 'ORDER_BY')
        .length;
  }
}