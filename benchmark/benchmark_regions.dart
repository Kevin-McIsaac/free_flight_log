import '../free_flight_log_app/lib/services/logging_service.dart';

/// Test region definition
class TestRegion {
  final String name;
  final String description;
  final double west;
  final double south;
  final double east;
  final double north;
  final List<String>? countryCodes;

  const TestRegion({
    required this.name,
    required this.description,
    required this.west,
    required this.south,
    required this.east,
    required this.north,
    this.countryCodes,
  });

  /// Get bounding box area in square degrees
  double get area => (east - west) * (north - south);

  /// Get center point
  Map<String, double> get center => {
    'lat': (north + south) / 2,
    'lng': (east + west) / 2,
  };

  @override
  String toString() => '$name: $description (${area.toStringAsFixed(2)} sq deg)';
}

/// Test region definitions for airspace query benchmarking
class BenchmarkRegions {

  /// Perth metropolitan area - small focused region
  static const TestRegion perth = TestRegion(
    name: 'Perth',
    description: 'Perth metropolitan area, Western Australia',
    west: 115.6,    // ~40km west of Perth CBD
    south: -32.1,   // ~40km south of Perth CBD
    east: 116.2,    // ~40km east of Perth CBD
    north: -31.7,   // ~40km north of Perth CBD
    countryCodes: ['AU'],
  );

  /// Continental Australia - large region covering most of the continent
  static const TestRegion continentalAustralia = TestRegion(
    name: 'Continental Australia',
    description: 'Australian mainland excluding Tasmania and remote territories',
    west: 112.9,    // Western Australia coast
    south: -39.2,   // Victoria/South Australia border
    east: 153.6,    // Queensland/NSW coast
    north: -10.7,   // Northern Territory/Queensland north
    countryCodes: ['AU'],
  );

  /// All of France - medium sized European country
  static const TestRegion france = TestRegion(
    name: 'France',
    description: 'Metropolitan France including Corsica',
    west: -5.2,     // Western coast (Brest area)
    south: 41.3,    // Corsica southern tip
    east: 9.6,      // Eastern border (Alps/Rhine)
    north: 51.1,    // Northern border (near Belgium)
    countryCodes: ['FR'],
  );

  /// Get all test regions
  static List<TestRegion> get allRegions => [perth, continentalAustralia, france];

  /// Get region by name
  static TestRegion? getRegion(String name) {
    try {
      return allRegions.firstWhere((r) => r.name.toLowerCase() == name.toLowerCase());
    } catch (e) {
      return null;
    }
  }

  /// Log region information
  static void logRegionInfo() {
    LoggingService.info('Benchmark test regions:');
    for (final region in allRegions) {
      LoggingService.info('  ${region.toString()}');
      LoggingService.info('    Bounds: W=${region.west}, S=${region.south}, E=${region.east}, N=${region.north}');
      LoggingService.info('    Center: ${region.center['lat']}, ${region.center['lng']}');
      LoggingService.info('    Countries: ${region.countryCodes?.join(', ') ?? 'All'}');
    }
  }

  /// Validate that regions have reasonable bounds
  static bool validateRegions() {
    for (final region in allRegions) {
      // Check basic coordinate validity
      if (region.west >= region.east) {
        LoggingService.error('Invalid region ${region.name}: west >= east');
        return false;
      }
      if (region.south >= region.north) {
        LoggingService.error('Invalid region ${region.name}: south >= north');
        return false;
      }

      // Check latitude bounds
      if (region.south < -90 || region.north > 90) {
        LoggingService.error('Invalid region ${region.name}: latitude out of range');
        return false;
      }

      // Check longitude bounds
      if (region.west < -180 || region.east > 180) {
        LoggingService.error('Invalid region ${region.name}: longitude out of range');
        return false;
      }

      // Check minimum size (should be at least 0.1 degrees in each direction)
      if ((region.east - region.west) < 0.1 || (region.north - region.south) < 0.1) {
        LoggingService.error('Invalid region ${region.name}: region too small');
        return false;
      }
    }

    LoggingService.info('All benchmark regions validated successfully');
    return true;
  }

  /// Get typical query parameters for each region
  static Map<String, dynamic> getTypicalQueryParams(TestRegion region) {
    switch (region.name) {
      case 'Perth':
        return {
          'maxAltitudeFt': 10000.0, // Focus on lower airspace around populated area
          'excludedTypes': <int>{}, // Include all types
          'excludedClasses': <int>{}, // Include all classes
        };

      case 'Continental Australia':
        return {
          'maxAltitudeFt': 20000.0, // Include more high-altitude airspace
          'excludedTypes': <int>{}, // Include all types for comprehensive test
          'excludedClasses': <int>{}, // Include all classes
        };

      case 'France':
        return {
          'maxAltitudeFt': 15000.0, // European airspace typically well-defined up to FL150
          'excludedTypes': <int>{}, // Include all types
          'excludedClasses': <int>{}, // Include all classes
        };

      default:
        return {
          'maxAltitudeFt': null, // No altitude limit
          'excludedTypes': <int>{}, // Include all types
          'excludedClasses': <int>{}, // Include all classes
        };
    }
  }

  /// Get expected result size categories for analysis
  static String getExpectedResultCategory(TestRegion region) {
    switch (region.name) {
      case 'Perth':
        return 'Small (local area)';
      case 'Continental Australia':
        return 'Large (continental)';
      case 'France':
        return 'Medium (country)';
      default:
        return 'Unknown';
    }
  }
}