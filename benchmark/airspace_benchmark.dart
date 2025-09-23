import 'dart:io';
import '../free_flight_log_app/lib/services/logging_service.dart';
import 'benchmark_runner.dart';

/// Main entry point for airspace indexing benchmark
void main(List<String> args) async {
  // Initialize logging
  LoggingService.info('Starting Airspace Indexing Benchmark');
  LoggingService.info('Arguments: ${args.join(' ')}');

  try {
    final runner = BenchmarkRunner();

    // Parse command line arguments
    if (args.contains('--quick') || args.contains('-q')) {
      LoggingService.info('Running quick benchmark test');
      await runner.runQuickTest();
    } else if (args.contains('--help') || args.contains('-h')) {
      _printUsage();
      return;
    } else {
      LoggingService.info('Running full benchmark suite');
      await runner.runBenchmark();
    }

    LoggingService.info('Benchmark completed successfully');
    exit(0);

  } catch (e, stack) {
    LoggingService.error('Benchmark failed with error', e, stack);
    print('\nBenchmark failed: $e');
    print('Check benchmark/results/ for any partial results');
    exit(1);
  }
}

/// Print usage information
void _printUsage() {
  print('Airspace Indexing Benchmark');
  print('');
  print('Usage:');
  print('  dart run benchmark/airspace_benchmark.dart [options]');
  print('');
  print('Options:');
  print('  --quick, -q    Run quick test (Perth region, Strategy A only)');
  print('  --help, -h     Show this help message');
  print('');
  print('Examples:');
  print('  dart run benchmark/airspace_benchmark.dart');
  print('  dart run benchmark/airspace_benchmark.dart --quick');
  print('');
  print('Results will be saved to benchmark/results/');
  print('');
  print('Full benchmark tests:');
  print('- 3 indexing strategies (spatial only, spatial+separate, covering index)');
  print('- 3 regions (Perth, Continental Australia, France)');
  print('- 5 runs per test for statistical reliability');
  print('- EXPLAIN QUERY PLAN analysis for each strategy');
  print('');
  print('Output files:');
  print('- benchmark_results.json    (Raw data)');
  print('- benchmark_results.csv     (Spreadsheet format)');
  print('- explain_plans.txt         (Query execution plans)');
  print('- benchmark_summary.md      (Human-readable summary)');
}