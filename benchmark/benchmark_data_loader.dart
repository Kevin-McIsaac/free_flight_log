import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../free_flight_log_app/lib/services/logging_service.dart';
import '../free_flight_log_app/lib/services/airspace_geojson_service.dart' show ClipperData;
import '../free_flight_log_app/lib/data/models/airspace_cache_models.dart';
import 'benchmark_database.dart';

/// Data loader for downloading and processing AU/FR airspace data for benchmarking
class BenchmarkDataLoader {
  static const String _storageBaseUrl = 'https://storage.googleapis.com/29f98e10-a489-4c82-ae5e-489dbcd4912f';
  static const Duration _requestTimeout = Duration(minutes: 5);

  final BenchmarkDatabase _database = BenchmarkDatabase.instance;

  /// Download and load airspace data for both AU and FR
  Future<void> loadAllData() async {
    LoggingService.info('Starting benchmark data loading for AU and FR');

    await _downloadAndLoadCountry('AU');
    await _downloadAndLoadCountry('FR');

    final stats = await _database.getStatistics();
    LoggingService.info('Benchmark data loading complete: ${stats['rowCount']} airspaces loaded');
  }

  /// Download and load airspace data for a specific country
  Future<void> _downloadAndLoadCountry(String countryCode) async {
    final stopwatch = Stopwatch()..start();

    try {
      LoggingService.info('Loading country data: $countryCode');

      // Check if data file already exists locally
      final dataFile = File('benchmark/data/${countryCode.toLowerCase()}_asp.geojson');
      Map<String, dynamic> geoJson;

      if (await dataFile.exists()) {
        LoggingService.info('Using cached data file for $countryCode');
        final jsonString = await dataFile.readAsString();
        geoJson = json.decode(jsonString);
      } else {
        // Download from Google Storage
        LoggingService.info('Downloading $countryCode data from cloud storage');
        geoJson = await _downloadCountryData(countryCode);

        // Cache the data locally
        await dataFile.writeAsString(json.encode(geoJson));
        LoggingService.info('Cached $countryCode data locally');
      }

      // Process and load into database
      if (geoJson['type'] != 'FeatureCollection') {
        throw Exception('Invalid GeoJSON format for $countryCode');
      }

      final features = geoJson['features'] as List<dynamic>;
      LoggingService.info('Processing ${features.length} features for $countryCode');

      // Process features in batches for better memory management
      const batchSize = 100;
      for (int i = 0; i < features.length; i += batchSize) {
        final batchEnd = (i + batchSize < features.length) ? i + batchSize : features.length;
        final batch = features.sublist(i, batchEnd);

        await _processBatch(batch.cast<Map<String, dynamic>>(), countryCode);

        if (i % 500 == 0) {
          LoggingService.info('Processed ${i + batch.length}/${features.length} features for $countryCode');
        }
      }

      stopwatch.stop();
      LoggingService.info('Completed loading $countryCode data in ${stopwatch.elapsedMilliseconds}ms');

    } catch (e, stack) {
      LoggingService.error('Failed to load country data for $countryCode', e, stack);
      rethrow;
    }
  }

  /// Download country data from Google Storage
  Future<Map<String, dynamic>> _downloadCountryData(String countryCode) async {
    final url = '$_storageBaseUrl/${countryCode.toLowerCase()}_asp.geojson';

    LoggingService.structured('BENCHMARK_DOWNLOAD_START', {
      'country': countryCode,
      'url': url,
    });

    // Use HttpClient instead of http package
    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Failed to download $countryCode data: HTTP ${response.statusCode}');
      }

      // Download with progress tracking
      final contentLength = response.contentLength;
      final bytes = <int>[];
      var downloadedBytes = 0;

      await for (final chunk in response) {
        bytes.addAll(chunk);
        downloadedBytes += chunk.length;

        if (contentLength > 0 && downloadedBytes % (1024 * 1024) == 0) {
          final progress = downloadedBytes / contentLength.toDouble();
          LoggingService.info('Download progress: ${(progress * 100).toStringAsFixed(1)}%');
        }
      }

      final jsonString = utf8.decode(bytes);
      final geoJson = json.decode(jsonString);

      LoggingService.structured('BENCHMARK_DOWNLOAD_COMPLETE', {
        'country': countryCode,
        'size_bytes': bytes.length,
        'size_mb': (bytes.length / 1024 / 1024).toStringAsFixed(2),
      });

      return geoJson;
    } finally {
      httpClient.close();
    }
  }

  /// Process a batch of features and insert into database
  Future<void> _processBatch(List<Map<String, dynamic>> features, String countryCode) async {
    for (final feature in features) {
      try {
        final geometry = await _convertFeatureToGeometry(feature, countryCode);
        if (geometry != null) {
          await _database.insertGeometry(geometry);
        }
      } catch (e) {
        LoggingService.error('Failed to process feature: ${feature['id'] ?? 'unknown'}', e);
        // Continue processing other features
      }
    }
  }

  /// Convert GeoJSON feature to CachedAirspaceGeometry using production logic
  Future<CachedAirspaceGeometry?> _convertFeatureToGeometry(
    Map<String, dynamic> feature,
    String countryCode,
  ) async {
    try {
      final id = feature['id']?.toString();
      if (id == null) return null;

      final properties = feature['properties'] as Map<String, dynamic>? ?? {};
      final geometry = feature['geometry'] as Map<String, dynamic>?;

      if (geometry == null || geometry['type'] != 'Polygon') {
        return null;
      }

      // Extract basic properties
      final name = properties['name']?.toString() ?? 'Unknown';
      final typeCode = _extractTypeCode(properties);

      // Process coordinates into ClipperData format (same as production)
      final coordinates = geometry['coordinates'] as List<dynamic>;
      final clipperData = _processCoordinates(coordinates);

      // Add country to properties
      final enhancedProperties = Map<String, dynamic>.from(properties);
      enhancedProperties['country'] = countryCode;

      // Create geometry hash
      final geometryHash = _createGeometryHash(feature);

      return CachedAirspaceGeometry(
        id: id,
        name: name,
        typeCode: typeCode,
        clipperData: clipperData,
        properties: enhancedProperties,
        fetchTime: DateTime.now(),
        geometryHash: geometryHash,
        compressedSize: clipperData.coords.lengthInBytes + clipperData.offsets.lengthInBytes,
        uncompressedSize: clipperData.coords.length * 8, // Estimate
      );

    } catch (e, stack) {
      LoggingService.error('Failed to convert feature to geometry', e, stack);
      return null;
    }
  }

  /// Extract type code from properties (simplified for benchmark)
  int _extractTypeCode(Map<String, dynamic> properties) {
    // Try common type field names
    final type = properties['type'] ?? properties['airspaceType'] ?? properties['class'];

    if (type is int) return type;
    if (type is String) {
      // Map common string types to numeric codes
      switch (type.toUpperCase()) {
        case 'CTR': return 1;
        case 'TMA': return 2;
        case 'CTA': return 3;
        case 'RESTRICTED': return 4;
        case 'DANGER': return 5;
        case 'PROHIBITED': return 6;
        default: return 0; // Unknown type
      }
    }

    return 0; // Default for unknown types
  }

  /// Process polygon coordinates into ClipperData format (same as production)
  ClipperData _processCoordinates(List<dynamic> coordinates) {
    final allCoords = <int>[];
    final offsets = <int>[];

    // Process each polygon ring
    for (final ring in coordinates) {
      if (ring is List) {
        offsets.add(allCoords.length ~/ 2); // Offset in coordinate pairs

        for (final point in ring) {
          if (point is List && point.length >= 2) {
            final lng = point[0] as double;
            final lat = point[1] as double;

            // Convert to Int32 format (scaled by 10^7) as used in production
            allCoords.add((lng * 10000000).round());
            allCoords.add((lat * 10000000).round());
          }
        }
      }
    }

    // Convert to typed arrays
    final coordArray = Int32List.fromList(allCoords);
    final offsetArray = Int32List.fromList(offsets);

    return ClipperData(coordArray, offsetArray);
  }

  /// Create geometry hash for the feature
  String _createGeometryHash(Map<String, dynamic> feature) {
    final geometryString = json.encode(feature['geometry']);
    // Simple hash using string hashCode for benchmark purposes
    return geometryString.hashCode.toRadixString(16).padLeft(8, '0');
  }

  /// Check if data is already loaded
  Future<bool> isDataLoaded() async {
    final stats = await _database.getStatistics();
    return stats['rowCount'] > 0;
  }

  /// Clear all loaded data
  Future<void> clearData() async {
    await _database.clearAll();
    LoggingService.info('Cleared all benchmark data');
  }

  /// Get loading statistics
  Future<Map<String, dynamic>> getLoadingStats() async {
    final stats = await _database.getStatistics();

    // Count by country if possible
    final db = await _database.database;
    final auCount = await db.rawQuery("SELECT COUNT(*) as count FROM airspace_geometries WHERE country = 'AU'");
    final frCount = await db.rawQuery("SELECT COUNT(*) as count FROM airspace_geometries WHERE country = 'FR'");

    return {
      'totalAirspaces': stats['rowCount'],
      'auAirspaces': auCount.first['count'],
      'frAirspaces': frCount.first['count'],
      'databaseSizeMB': stats['databaseSizeMB'],
    };
  }
}