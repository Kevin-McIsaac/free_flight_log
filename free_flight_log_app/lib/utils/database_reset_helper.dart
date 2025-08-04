import 'dart:io';
import '../data/datasources/database_helper.dart';

/// Helper class for resetting/clearing database data
/// Can be called from within the Flutter app
class DatabaseResetHelper {
  static final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  /// Reset the entire database - removes all data and recreates tables
  static Future<Map<String, dynamic>> resetDatabase() async {
    try {
      print('🗃️  Resetting database...');
      
      // Get current database info before reset
      final db = await _databaseHelper.database;
      final path = db.path;
      
      final flightCount = await _getTableCount('flights');
      final siteCount = await _getTableCount('sites');
      final wingCount = await _getTableCount('wings');
      
      print('Removing $flightCount flights, $siteCount sites, $wingCount wings');
      
      // Close the database connection
      await db.close();
      
      // Delete the database file
      final dbFile = File(path);
      if (await dbFile.exists()) {
        await dbFile.delete();
        print('✅ Database file deleted');
      }
      
      // Recreate the database (this will run the onCreate method)
      print('🔄 Recreating database with fresh schema...');
      await _databaseHelper.recreateDatabase();
      final newDb = await _databaseHelper.database;
      
      // Verify the new database is empty
      final newFlightCount = await _getTableCount('flights');
      final newSiteCount = await _getTableCount('sites');
      final newWingCount = await _getTableCount('wings');
      
      print('✅ Database reset complete!');
      print('New database: $newFlightCount flights, $newSiteCount sites, $newWingCount wings');
      
      return {
        'success': true,
        'message': 'Database reset successfully',
        'before': {
          'flights': flightCount,
          'sites': siteCount,
          'wings': wingCount,
          'total': flightCount + siteCount + wingCount,
        },
        'after': {
          'flights': newFlightCount,
          'sites': newSiteCount,
          'wings': newWingCount,
          'total': newFlightCount + newSiteCount + newWingCount,
        },
      };
      
    } catch (e) {
      print('❌ Error resetting database: $e');
      return {
        'success': false,
        'message': 'Error resetting database: $e',
      };
    }
  }
  
  /// Clear all flight data (keep sites and wings)
  static Future<Map<String, dynamic>> clearAllFlights() async {
    try {
      print('🗃️  Clearing all flights...');
      
      final db = await _databaseHelper.database;
      final flightCount = await _getTableCount('flights');
      
      if (flightCount == 0) {
        return {
          'success': true,
          'message': 'No flights to delete',
          'deleted': 0,
        };
      }
      
      // Delete all flights
      final deletedCount = await db.delete('flights');
      
      print('✅ Cleared $deletedCount flights');
      
      return {
        'success': true,
        'message': 'Cleared $deletedCount flights',
        'deleted': deletedCount,
      };
      
    } catch (e) {
      print('❌ Error clearing flights: $e');
      return {
        'success': false,
        'message': 'Error clearing flights: $e',
      };
    }
  }
  
  /// Clear all site data (may fail if referenced by flights)
  static Future<Map<String, dynamic>> clearAllSites() async {
    try {
      print('🗃️  Clearing all sites...');
      
      final db = await _databaseHelper.database;
      final siteCount = await _getTableCount('sites');
      
      if (siteCount == 0) {
        return {
          'success': true,
          'message': 'No sites to delete',
          'deleted': 0,
        };
      }
      
      try {
        final deletedCount = await db.delete('sites');
        print('✅ Cleared $deletedCount sites');
        
        return {
          'success': true,
          'message': 'Cleared $deletedCount sites',
          'deleted': deletedCount,
        };
      } catch (e) {
        return {
          'success': false,
          'message': 'Cannot delete sites - they are referenced by existing flights. Delete flights first.',
        };
      }
      
    } catch (e) {
      print('❌ Error clearing sites: $e');
      return {
        'success': false,
        'message': 'Error clearing sites: $e',
      };
    }
  }
  
  /// Clear all wing data (may fail if referenced by flights)
  static Future<Map<String, dynamic>> clearAllWings() async {
    try {
      print('🗃️  Clearing all wings...');
      
      final db = await _databaseHelper.database;
      final wingCount = await _getTableCount('wings');
      
      if (wingCount == 0) {
        return {
          'success': true,
          'message': 'No wings to delete',
          'deleted': 0,
        };
      }
      
      try {
        final deletedCount = await db.delete('wings');
        print('✅ Cleared $deletedCount wings');
        
        return {
          'success': true,
          'message': 'Cleared $deletedCount wings',
          'deleted': deletedCount,
        };
      } catch (e) {
        return {
          'success': false,
          'message': 'Cannot delete wings - they are referenced by existing flights. Delete flights first.',
        };
      }
      
    } catch (e) {
      print('❌ Error clearing wings: $e');
      return {
        'success': false,
        'message': 'Error clearing wings: $e',
      };
    }
  }
  
  /// Get database statistics
  static Future<Map<String, dynamic>> getDatabaseStats() async {
    try {
      final db = await _databaseHelper.database;
      
      final flightCount = await _getTableCount('flights');
      final siteCount = await _getTableCount('sites');
      final wingCount = await _getTableCount('wings');
      
      // Get database file size
      final dbFile = File(db.path);
      int sizeBytes = 0;
      if (await dbFile.exists()) {
        sizeBytes = await dbFile.length();
      }
      
      return {
        'path': db.path,
        'version': 3, // Current database version
        'flights': flightCount,
        'sites': siteCount,
        'wings': wingCount,
        'total_records': flightCount + siteCount + wingCount,
        'size_bytes': sizeBytes,
        'size_kb': (sizeBytes / 1024).toStringAsFixed(1),
      };
      
    } catch (e) {
      return {
        'error': 'Error getting database stats: $e',
      };
    }
  }
  
  /// Get count of records in a table
  static Future<int> _getTableCount(String tableName) async {
    try {
      final db = await _databaseHelper.database;
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM $tableName');
      return result.first['count'] as int;
    } catch (e) {
      return 0;
    }
  }
  
  /// Initialize a fresh database (call this after reset if needed)
  static Future<void> initializeFreshDatabase() async {
    try {
      print('🆕 Initializing fresh database...');
      
      // This will ensure the database is created with the latest schema
      final db = await _databaseHelper.database;
      const version = 3; // Current database version
      
      print('✅ Database initialized with version $version');
      
    } catch (e) {
      print('❌ Error initializing database: $e');
      rethrow;
    }
  }
}