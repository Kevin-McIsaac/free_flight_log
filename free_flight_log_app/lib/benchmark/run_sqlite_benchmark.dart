import 'dart:io';
import 'sqlite_benchmark.dart';
import '../services/logging_service.dart';

/// Runner for SQLite benchmark with real database operations
void main() async {
  print('SQLite Airspace Indexing Benchmark');
  print('This runs actual SQL queries with EXPLAIN QUERY PLAN analysis');
  print('');

  final benchmark = SQLiteBenchmark();

  try {
    // Initialize database with sample data
    print('Initializing SQLite database...');
    await benchmark.initialize();

    // Run benchmark
    print('Running benchmark with 3 indexing strategies...');
    final results = await benchmark.runBenchmark();

    // Generate report
    print('Generating comprehensive report...');
    await benchmark.generateReport(results);

    print('');
    print('SQLite benchmark completed successfully!');
    print('Check sqlite_benchmark_results.md for detailed EXPLAIN QUERY PLAN analysis');

  } catch (e, stack) {
    print('Benchmark failed: $e');
    print(stack);
    exit(1);
  } finally {
    await benchmark.close();
  }
}