import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

// For standalone benchmark, we'll define minimal required models
class ClipperData {
  final Int32List coords;
  final Int32List offsets;

  ClipperData(this.coords, this.offsets);
}

class CachedAirspaceGeometry {
  final String id;
  final String name;
  final int typeCode;
  final ClipperData clipperData;
  final Map<String, dynamic> properties;
  final DateTime fetchTime;
  final String geometryHash;
  final int compressedSize;
  final int uncompressedSize;

  CachedAirspaceGeometry({
    required this.id,
    required this.name,
    required this.typeCode,
    required this.clipperData,
    required this.properties,
    required this.fetchTime,
    required this.geometryHash,
    required this.compressedSize,
    required this.uncompressedSize,
  });
}

// Simple logging for benchmark
class LoggingService {
  static void info(String message) => print('[INFO] $message');
  static void error(String message, dynamic error, [StackTrace? stack]) =>
    print('[ERROR] $message: $error');
  static void structured(String type, Map<String, dynamic> data) =>
    print('[$type] ${data.entries.map((e) => '${e.key}=${e.value}').join(', ')}');
}

/// Database for benchmarking different indexing strategies on airspace queries
/// Uses the exact same schema as production AirspaceDiskCache
class BenchmarkDatabase {
  static const String _databaseName = 'airspace_benchmark.db';
  static const int _databaseVersion = 1;

  static const String _geometryTable = 'airspace_geometries';

  Database? _database;
  static BenchmarkDatabase? _instance;
  String? _databasePath;

  BenchmarkDatabase._internal();

  static BenchmarkDatabase get instance {
    _instance ??= BenchmarkDatabase._internal();
    return _instance!;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(Directory.current.path, 'benchmark', 'data', _databaseName);
    _databasePath = path;

    LoggingService.info('Initializing benchmark database at: $path');

    // Delete existing database to ensure clean state
    try {
      await deleteDatabase(path);
      LoggingService.info('Deleted existing benchmark database');
    } catch (e) {
      // Database doesn't exist yet, which is fine
    }

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onOpen: _onOpen,
    );
  }

  Future<void> _onOpen(Database db) async {
    // Configure database after opening
    try {
      await db.rawQuery('PRAGMA page_size = 4096');
      await db.rawQuery('PRAGMA cache_size = -2000'); // 2MB cache
      await db.rawQuery('PRAGMA journal_mode = WAL');
      await db.rawQuery('PRAGMA synchronous = NORMAL');
    } catch (e) {
      // If PRAGMA commands fail, continue anyway - they're optimizations
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    LoggingService.info('Creating benchmark airspace table with production schema');

    // Exact same schema as production AirspaceDiskCache
    await db.execute('''
      CREATE TABLE $_geometryTable (
        -- Core identifiers
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type_code INTEGER NOT NULL,

        -- Spatial data (binary for efficiency)
        coordinates_binary BLOB NOT NULL,  -- Int32 array (scaled by 10^7)
        polygon_offsets BLOB NOT NULL,     -- Int32 array of point indices
        bounds_west REAL NOT NULL,
        bounds_south REAL NOT NULL,
        bounds_east REAL NOT NULL,
        bounds_north REAL NOT NULL,

        -- Computed altitude fields (for fast filtering and sorting)
        lower_altitude_ft INTEGER,         -- Lower limit in feet (computed)
        upper_altitude_ft INTEGER,         -- Upper limit in feet (computed)

        -- Raw altitude components
        lower_value REAL,                  -- Raw lower value
        lower_unit INTEGER,                -- Unit code (1=ft, 2=m, 6=FL)
        lower_reference INTEGER,           -- Reference code (0=GND, 1=AMSL, 2=AGL)
        upper_value REAL,                  -- Raw upper value
        upper_unit INTEGER,                -- Unit code
        upper_reference INTEGER,           -- Reference code

        -- Classification fields
        icao_class INTEGER,                -- ICAO class code (extracted)
        activity INTEGER,                  -- Activity bitmask
        country TEXT,                      -- Country code

        -- Metadata
        fetch_time INTEGER NOT NULL,
        geometry_hash TEXT NOT NULL,
        coordinate_count INTEGER NOT NULL,
        polygon_count INTEGER NOT NULL,
        last_accessed INTEGER,

        -- Minimal JSON for rarely-used fields
        extra_properties TEXT              -- Remaining properties not extracted
      )
    ''');

    LoggingService.info('Benchmark database table created successfully');
  }

  /// Apply indexing strategy A: Spatial compound index only (current production)
  Future<void> applyIndexingStrategyA() async {
    final db = await database;

    LoggingService.info('Applying indexing strategy A: Spatial compound index only');

    // Drop all existing indexes
    await _dropAllIndexes();

    // Create spatial compound index (current production approach)
    await db.execute('CREATE INDEX idx_geometry_spatial ON $_geometryTable(bounds_west, bounds_east, bounds_south, bounds_north)');

    LoggingService.info('Strategy A indexes created');
  }

  /// Apply indexing strategy B: Spatial + separate indexes
  Future<void> applyIndexingStrategyB() async {
    final db = await database;

    LoggingService.info('Applying indexing strategy B: Spatial + separate indexes');

    // Drop all existing indexes
    await _dropAllIndexes();

    // Create spatial compound index
    await db.execute('CREATE INDEX idx_geometry_spatial ON $_geometryTable(bounds_west, bounds_east, bounds_south, bounds_north)');

    // Create separate indexes for filtering columns
    await db.execute('CREATE INDEX idx_geometry_type_code ON $_geometryTable(type_code)');
    await db.execute('CREATE INDEX idx_geometry_icao_class ON $_geometryTable(icao_class)');
    await db.execute('CREATE INDEX idx_geometry_lower_altitude ON $_geometryTable(lower_altitude_ft)');

    LoggingService.info('Strategy B indexes created');
  }

  /// Apply indexing strategy C: Single covering index
  Future<void> applyIndexingStrategyC() async {
    final db = await database;

    LoggingService.info('Applying indexing strategy C: Single covering index');

    // Drop all existing indexes
    await _dropAllIndexes();

    // Create single covering index with all commonly filtered columns
    await db.execute('''
      CREATE INDEX idx_geometry_covering ON $_geometryTable(
        bounds_west, bounds_east, bounds_south, bounds_north,
        type_code, icao_class, lower_altitude_ft
      )
    ''');

    LoggingService.info('Strategy C indexes created');
  }

  /// Drop all user-created indexes
  Future<void> _dropAllIndexes() async {
    final db = await database;

    // Get all user-created indexes (not automatic ones)
    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
    );

    for (final index in indexes) {
      final indexName = index['name'] as String;
      try {
        await db.execute('DROP INDEX IF EXISTS $indexName');
        LoggingService.info('Dropped index: $indexName');
      } catch (e) {
        LoggingService.error('Failed to drop index $indexName', e);
      }
    }
  }

  /// Execute query with EXPLAIN QUERY PLAN and return both results and plan
  Future<Map<String, dynamic>> executeQueryWithExplain({
    required double west,
    required double south,
    required double east,
    required double north,
    List<String>? countryCodes,
    int? typeCode,
    Set<int>? excludedTypes,
    Set<int>? excludedClasses,
    double? maxAltitudeFt,
    bool orderByAltitude = false,
  }) async {
    final db = await database;

    // Build the same query as production
    final conditions = <String>[];
    final args = <dynamic>[];

    // Spatial bounds conditions
    conditions.add('bounds_west <= ?');
    args.add(east);
    conditions.add('bounds_east >= ?');
    args.add(west);
    conditions.add('bounds_south <= ?');
    args.add(north);
    conditions.add('bounds_north >= ?');
    args.add(south);

    // Type filtering
    if (typeCode != null) {
      conditions.add('type_code = ?');
      args.add(typeCode);
    } else if (excludedTypes != null && excludedTypes.isNotEmpty) {
      conditions.add('type_code NOT IN (${excludedTypes.map((_) => '?').join(',')})');
      args.addAll(excludedTypes);
    }

    // ICAO class filtering
    if (excludedClasses != null && excludedClasses.isNotEmpty) {
      conditions.add('(icao_class IS NULL OR icao_class NOT IN (${excludedClasses.map((_) => '?').join(',')}))');
      args.addAll(excludedClasses);
    }

    // Altitude filtering
    if (maxAltitudeFt != null) {
      conditions.add('(lower_altitude_ft IS NULL OR lower_altitude_ft <= ?)');
      args.add(maxAltitudeFt);
    }

    // Build the query
    String query = '''
      SELECT * FROM $_geometryTable
      WHERE ${conditions.join(' AND ')}
    ''';

    // Add ORDER BY clause
    if (orderByAltitude) {
      query += ' ORDER BY lower_altitude_ft ASC NULLS LAST';
    }

    // Get EXPLAIN QUERY PLAN
    final explainQuery = 'EXPLAIN QUERY PLAN $query';
    final explainResults = await db.rawQuery(explainQuery, args);

    // Execute actual query and measure time
    final stopwatch = Stopwatch()..start();
    final results = await db.rawQuery(query, args);
    stopwatch.stop();

    return {
      'results': results,
      'resultCount': results.length,
      'durationMs': stopwatch.elapsedMilliseconds,
      'explainPlan': explainResults,
    };
  }

  /// Get database statistics
  Future<Map<String, dynamic>> getStatistics() async {
    final db = await database;

    // Get row count
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM $_geometryTable');
    final rowCount = countResult.first['count'] as int;

    // Get database file size
    final dbFile = File(_databasePath!);
    final sizeBytes = await dbFile.exists() ? await dbFile.length() : 0;

    // Get index information
    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
    );

    return {
      'rowCount': rowCount,
      'databaseSizeBytes': sizeBytes,
      'databaseSizeMB': sizeBytes / (1024 * 1024),
      'indexCount': indexes.length,
      'indexes': indexes.map((i) => i['name']).toList(),
    };
  }

  /// Insert airspace geometry using production format
  Future<void> insertGeometry(CachedAirspaceGeometry geometry) async {
    final db = await database;

    // Extract binary data directly from ClipperData (same as production)
    final coordinatesBinary = geometry.clipperData.coords.buffer.asUint8List();
    final offsetsBinary = geometry.clipperData.offsets.buffer.asUint8List();

    // Calculate bounds from ClipperData (same as production)
    final bounds = _calculateBoundsFromClipperData(geometry.clipperData);

    // Extract altitude limits (same as production)
    final lowerLimit = geometry.properties['lowerLimit'] as Map<String, dynamic>?;
    final upperLimit = geometry.properties['upperLimit'] as Map<String, dynamic>?;

    // Extract altitude components
    final lowerValue = lowerLimit?['value'];
    final lowerUnit = lowerLimit?['unit'] as int?;
    final lowerReference = lowerLimit?['reference'] as int?;
    final upperValue = upperLimit?['value'];
    final upperUnit = upperLimit?['unit'] as int?;
    final upperReference = upperLimit?['reference'] as int?;

    // Compute altitude in feet for fast filtering (same as production)
    final lowerAltitudeFt = lowerLimit != null
        ? _computeAltitudeInFeet(lowerValue, lowerUnit, lowerReference)
        : null;
    final upperAltitudeFt = upperLimit != null
        ? _computeAltitudeInFeet(upperValue, upperUnit, upperReference)
        : null;

    // Extract classification fields
    final icaoClass = (geometry.properties['class'] ?? geometry.properties['icaoClass']) as int?;
    final activity = geometry.properties['activity'] as int?;
    final country = geometry.properties['country'] as String?;

    // Create extra properties (same as production)
    final extraProperties = Map<String, dynamic>.from(geometry.properties);
    extraProperties.remove('lowerLimit');
    extraProperties.remove('upperLimit');
    extraProperties.remove('class');
    extraProperties.remove('icaoClass');
    extraProperties.remove('activity');
    extraProperties.remove('country');

    // Count coordinates from ClipperData
    final coordinateCount = geometry.clipperData.coords.length ~/ 2;

    await db.insert(
      _geometryTable,
      {
        // Core identifiers
        'id': geometry.id,
        'name': geometry.name,
        'type_code': geometry.typeCode,

        // Spatial data
        'coordinates_binary': coordinatesBinary,
        'polygon_offsets': offsetsBinary,
        'bounds_west': bounds['west'],
        'bounds_south': bounds['south'],
        'bounds_east': bounds['east'],
        'bounds_north': bounds['north'],

        // Computed altitude fields
        'lower_altitude_ft': lowerAltitudeFt,
        'upper_altitude_ft': upperAltitudeFt,

        // Raw altitude components
        'lower_value': lowerValue is num ? lowerValue.toDouble() : null,
        'lower_unit': lowerUnit,
        'lower_reference': lowerReference,
        'upper_value': upperValue is num ? upperValue.toDouble() : null,
        'upper_unit': upperUnit,
        'upper_reference': upperReference,

        // Classification fields
        'icao_class': icaoClass,
        'activity': activity,
        'country': country,

        // Metadata
        'fetch_time': geometry.fetchTime.millisecondsSinceEpoch,
        'geometry_hash': geometry.geometryHash,
        'coordinate_count': coordinateCount,
        'polygon_count': geometry.clipperData.offsets.length,
        'last_accessed': DateTime.now().millisecondsSinceEpoch,

        // Minimal JSON for remaining properties
        'extra_properties': extraProperties.isNotEmpty ? jsonEncode(extraProperties) : null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Calculate bounds from ClipperData (copied from production)
  Map<String, double> _calculateBoundsFromClipperData(ClipperData clipperData) {
    double minLat = 90.0, maxLat = -90.0;
    double minLng = 180.0, maxLng = -180.0;

    // Iterate through coordinates (they're stored as lng,lat pairs in Int32)
    for (int i = 0; i < clipperData.coords.length; i += 2) {
      final lng = clipperData.coords[i] / 10000000.0;  // Convert back to degrees
      final lat = clipperData.coords[i + 1] / 10000000.0;

      minLat = lat < minLat ? lat : minLat;
      maxLat = lat > maxLat ? lat : maxLat;
      minLng = lng < minLng ? lng : minLng;
      maxLng = lng > maxLng ? lng : maxLng;
    }

    return {
      'west': minLng,
      'south': minLat,
      'east': maxLng,
      'north': maxLat,
    };
  }

  /// Compute altitude in feet from raw value, unit, and reference (copied from production)
  int _computeAltitudeInFeet(dynamic value, int? unit, int? reference) {
    // Handle special ground values or reference code 0 (GND)
    if (reference == 0 || (value is String && value.toLowerCase() == 'gnd')) {
      return 0;
    }

    // Handle numeric values with OpenAIP unit codes
    if (value is num) {
      // OpenAIP unit codes: 1=ft, 2=m, 6=FL
      if (unit == 6) {
        // Flight Level: FL090 = 9,000 feet
        return (value * 100).round();
      } else if (unit == 1) {
        // Feet (AMSL or AGL - treat both as feet for sorting)
        return value.round();
      } else if (unit == 2) {
        // Meters - convert to feet
        return (value * 3.28084).round();
      }
    }

    // Unknown altitude
    return 999999;
  }

  /// Clear all data from the database
  Future<void> clearAll() async {
    final db = await database;
    await db.delete(_geometryTable);
    LoggingService.info('Cleared all benchmark data');
  }

  /// Close the database
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}