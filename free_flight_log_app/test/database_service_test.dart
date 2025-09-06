import 'package:flutter_test/flutter_test.dart';
import 'package:free_flight_log_app/services/database_service.dart';
import 'package:free_flight_log_app/data/models/flight.dart';
import 'package:free_flight_log_app/data/models/site.dart';
import 'package:free_flight_log_app/data/models/wing.dart';
import 'package:free_flight_log_app/data/datasources/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'helpers/test_helpers.dart';

void main() {
  // Initialize database for testing
  setUpAll(() {
    TestHelpers.initializeDatabaseForTesting();
  });

  group('DatabaseService', () {
    late DatabaseService databaseService;
    late DatabaseHelper databaseHelper;

    setUp(() async {
      // Use an in-memory database for each test to ensure isolation
      databaseService = DatabaseService.instance;
      databaseHelper = DatabaseHelper.instance;
      
      // Clean the database before each test
      final db = await databaseHelper.database;
      await db.delete('flights');
      await db.delete('sites');
      await db.delete('wings');
      await db.delete('wing_aliases');
    });

    tearDown(() async {
      // Clean up after each test
      final db = await databaseHelper.database;
      await db.delete('flights');
      await db.delete('sites');
      await db.delete('wings');
      await db.delete('wing_aliases');
    });

    group('Flight CRUD Operations', () {
      test('should insert a new flight', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);
        
        final testFlight = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
        );

        // Act
        final result = await databaseService.insertFlight(testFlight);

        // Assert
        expect(result, isA<int>());
        expect(result, greaterThan(0));

        final retrievedFlight = await databaseService.getFlight(result);
        expect(retrievedFlight, isNotNull);
        expect(retrievedFlight!.launchSiteId, equals(siteId));
        expect(retrievedFlight.wingId, equals(wingId));
        expect(retrievedFlight.duration, equals(testFlight.duration));
      });

      test('should retrieve a flight by ID', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);
        
        final testFlight = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
          notes: 'Unique test flight',
        );
        final flightId = await databaseService.insertFlight(testFlight);

        // Act
        final retrievedFlight = await databaseService.getFlight(flightId);

        // Assert
        expect(retrievedFlight, isNotNull);
        expect(retrievedFlight!.id, equals(flightId));
        expect(retrievedFlight.notes, equals('Unique test flight'));
        expect(retrievedFlight.duration, equals(testFlight.duration));
      });

      test('should return null for non-existent flight ID', () async {
        // Act
        final result = await databaseService.getFlight(999);

        // Assert
        expect(result, isNull);
      });

      test('should update an existing flight', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);
        
        final testFlight = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
          notes: 'Original notes',
        );
        final flightId = await databaseService.insertFlight(testFlight);

        final updatedFlight = testFlight.copyWith(
          id: flightId,
          notes: 'Updated notes',
          duration: 180,
        );

        // Act
        final updateResult = await databaseService.updateFlight(updatedFlight);

        // Assert
        expect(updateResult, equals(1)); // One row updated

        final retrievedFlight = await databaseService.getFlight(flightId);
        expect(retrievedFlight, isNotNull);
        expect(retrievedFlight!.notes, equals('Updated notes'));
        expect(retrievedFlight.duration, equals(180));
      });

      test('should delete a flight', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);
        
        final testFlight = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
        );
        final flightId = await databaseService.insertFlight(testFlight);

        // Act
        final deleteResult = await databaseService.deleteFlight(flightId);

        // Assert
        expect(deleteResult, equals(1)); // One row deleted

        final retrievedFlight = await databaseService.getFlight(flightId);
        expect(retrievedFlight, isNull);
      });

      test('should get all flights ordered by date', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        final flight1 = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
          date: DateTime(2023, 1, 1),
          notes: 'First flight',
        );
        
        final flight2 = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
          date: DateTime(2023, 12, 31),
          notes: 'Last flight',
        );

        await databaseService.insertFlight(flight1);
        await databaseService.insertFlight(flight2);

        // Act
        final flights = await databaseService.getAllFlights();

        // Assert
        expect(flights, hasLength(2));
        expect(flights.first.notes, equals('Last flight')); // Most recent first
        expect(flights.last.notes, equals('First flight'));
      });

      test('should get flight count', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        for (int i = 0; i < 5; i++) {
          final testFlight = TestHelpers.createTestFlight(
            launchSiteId: siteId,
            wingId: wingId,
          );
          await databaseService.insertFlight(testFlight);
        }

        // Act
        final count = await databaseService.getFlightCount();

        // Assert
        expect(count, equals(5));
      });

      test('should handle insert flight with database error gracefully', () async {
        // Arrange
        final testFlight = TestHelpers.createTestFlight(
          launchSiteId: 999, // Non-existent site ID
          wingId: 999, // Non-existent wing ID
        );

        // Act & Assert
        expect(
          () => databaseService.insertFlight(testFlight),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('Site Management Operations', () {
      test('should insert a new site', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite(name: 'Test Launch Site');

        // Act
        final result = await databaseService.insertSite(testSite);

        // Assert
        expect(result, isA<int>());
        expect(result, greaterThan(0));

        final retrievedSite = await databaseService.getSite(result);
        expect(retrievedSite, isNotNull);
        expect(retrievedSite!.name, equals('Test Launch Site'));
      });

      test('should get all sites ordered by name', () async {
        // Arrange
        final site1 = TestHelpers.createTestSite(name: 'Zebra Site');
        final site2 = TestHelpers.createTestSite(name: 'Alpha Site');
        
        await databaseService.insertSite(site1);
        await databaseService.insertSite(site2);

        // Act
        final sites = await databaseService.getAllSites();

        // Assert
        expect(sites, hasLength(2));
        expect(sites.first.name, equals('Alpha Site'));
        expect(sites.last.name, equals('Zebra Site'));
      });

      test('should update a site', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite(name: 'Original Name');
        final siteId = await databaseService.insertSite(testSite);
        
        final updatedSite = testSite.copyWith(
          id: siteId,
          name: 'Updated Name',
        );

        // Act
        final updateResult = await databaseService.updateSite(updatedSite);

        // Assert
        expect(updateResult, equals(1));

        final retrievedSite = await databaseService.getSite(siteId);
        expect(retrievedSite, isNotNull);
        expect(retrievedSite!.name, equals('Updated Name'));
      });

      test('should delete a site', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);

        // Act
        final deleteResult = await databaseService.deleteSite(siteId);

        // Assert
        expect(deleteResult, equals(1));

        final retrievedSite = await databaseService.getSite(siteId);
        expect(retrievedSite, isNull);
      });

      test('should search sites by name', () async {
        // Arrange
        final site1 = TestHelpers.createTestSite(name: 'Mountain Peak');
        final site2 = TestHelpers.createTestSite(name: 'Valley Launch');
        final site3 = TestHelpers.createTestSite(name: 'Coastal Peak');
        
        await databaseService.insertSite(site1);
        await databaseService.insertSite(site2);
        await databaseService.insertSite(site3);

        // Act
        final results = await databaseService.searchSites('Peak');

        // Assert
        expect(results, hasLength(2));
        expect(results.map((s) => s.name), containsAll(['Mountain Peak', 'Coastal Peak']));
      });

      test('should find site by coordinates', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite(
          latitude: 46.5197,
          longitude: 6.6323,
        );
        await databaseService.insertSite(testSite);

        // Act
        final found = await databaseService.findSiteByCoordinates(46.5197, 6.6323);

        // Assert
        expect(found, isNotNull);
        expect(found!.latitude, equals(46.5197));
        expect(found.longitude, equals(6.6323));
      });

      test('should find or create site', () async {
        // Act
        final site = await databaseService.findOrCreateSite(
          latitude: 47.0,
          longitude: 8.0,
          name: 'New Test Site',
          altitude: 1000.0,
          country: 'Switzerland',
        );

        // Assert
        expect(site.id, isNotNull);
        expect(site.name, equals('New Test Site'));
        expect(site.latitude, equals(47.0));
        expect(site.longitude, equals(8.0));

        // Verify it was actually inserted
        final retrieved = await databaseService.getSite(site.id!);
        expect(retrieved, isNotNull);
        expect(retrieved!.name, equals('New Test Site'));
      });

      test('should return existing site when coordinates match', () async {
        // Arrange
        final existingSite = TestHelpers.createTestSite(
          latitude: 47.0,
          longitude: 8.0,
          name: 'Existing Site',
        );
        await databaseService.insertSite(existingSite);

        // Act
        final site = await databaseService.findOrCreateSite(
          latitude: 47.0,
          longitude: 8.0,
          name: 'New Site Name',
        );

        // Assert
        expect(site.name, equals('Existing Site')); // Should return existing, not create new
      });
    });

    group('Wing Management Operations', () {
      test('should insert a new wing', () async {
        // Arrange
        final testWing = TestHelpers.createTestWing(name: 'Test Paraglider');

        // Act
        final result = await databaseService.insertWing(testWing);

        // Assert
        expect(result, isA<int>());
        expect(result, greaterThan(0));

        final retrievedWing = await databaseService.getWing(result);
        expect(retrievedWing, isNotNull);
        expect(retrievedWing!.name, equals('Test Paraglider'));
      });

      test('should get all wings ordered by active status then name', () async {
        // Arrange
        final wing1 = TestHelpers.createTestWing(name: 'Inactive Wing').copyWith(active: false);
        final wing2 = TestHelpers.createTestWing(name: 'Active Wing').copyWith(active: true);
        
        await databaseService.insertWing(wing1);
        await databaseService.insertWing(wing2);

        // Act
        final wings = await databaseService.getAllWings();

        // Assert
        expect(wings, hasLength(2));
        expect(wings.first.name, equals('Active Wing')); // Active wings first
        expect(wings.first.active, isTrue);
        expect(wings.last.name, equals('Inactive Wing'));
        expect(wings.last.active, isFalse);
      });

      test('should get only active wings', () async {
        // Arrange
        final activeWing = TestHelpers.createTestWing(name: 'Active Wing').copyWith(active: true);
        final inactiveWing = TestHelpers.createTestWing(name: 'Inactive Wing').copyWith(active: false);
        
        await databaseService.insertWing(activeWing);
        await databaseService.insertWing(inactiveWing);

        // Act
        final wings = await databaseService.getActiveWings();

        // Assert
        expect(wings, hasLength(1));
        expect(wings.first.name, equals('Active Wing'));
        expect(wings.first.active, isTrue);
      });

      test('should update a wing', () async {
        // Arrange
        final testWing = TestHelpers.createTestWing(name: 'Original Name');
        final wingId = await databaseService.insertWing(testWing);
        
        final updatedWing = testWing.copyWith(
          id: wingId,
          name: 'Updated Name',
        );

        // Act
        final updateResult = await databaseService.updateWing(updatedWing);

        // Assert
        expect(updateResult, equals(1));

        final retrievedWing = await databaseService.getWing(wingId);
        expect(retrievedWing, isNotNull);
        expect(retrievedWing!.name, equals('Updated Name'));
      });

      test('should delete a wing', () async {
        // Arrange
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        // Act
        final deleteResult = await databaseService.deleteWing(wingId);

        // Assert
        expect(deleteResult, equals(1));

        final retrievedWing = await databaseService.getWing(wingId);
        expect(retrievedWing, isNull);
      });

      test('should deactivate a wing', () async {
        // Arrange
        final testWing = TestHelpers.createTestWing().copyWith(active: true);
        final wingId = await databaseService.insertWing(testWing);

        // Act
        final deactivateResult = await databaseService.deactivateWing(wingId);

        // Assert
        expect(deactivateResult, equals(1));

        final retrievedWing = await databaseService.getWing(wingId);
        expect(retrievedWing, isNotNull);
        expect(retrievedWing!.active, isFalse);
      });

      test('should find or create wing', () async {
        // Act
        final wing = await databaseService.findOrCreateWing(
          manufacturer: 'Test Manufacturer',
          model: 'Test Model',
          size: 'L',
          color: 'Blue',
        );

        // Assert
        expect(wing.id, isNotNull);
        expect(wing.manufacturer, equals('Test Manufacturer'));
        expect(wing.name, equals('Test Model'));
        expect(wing.size, equals('L'));

        // Verify it was actually inserted
        final retrieved = await databaseService.getWing(wing.id!);
        expect(retrieved, isNotNull);
        expect(retrieved!.manufacturer, equals('Test Manufacturer'));
      });

      test('should return existing wing when manufacturer, model, and size match', () async {
        // Arrange
        final existingWing = TestHelpers.createTestWing(
          manufacturer: 'Test Manufacturer',
          name: 'Test Model',
          size: 'M',
        );
        await databaseService.insertWing(existingWing);

        // Act
        final wing = await databaseService.findOrCreateWing(
          manufacturer: 'Test Manufacturer',
          model: 'Test Model',
          size: 'M',
        );

        // Assert
        expect(wing.manufacturer, equals('Test Manufacturer'));
        expect(wing.name, equals('Test Model'));
        expect(wing.size, equals('M'));
        // Should return existing wing, not create a new one
      });
    });

    group('Wing Alias Operations', () {
      test('should add wing alias', () async {
        // Arrange
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        // Act
        await databaseService.addWingAlias(wingId, 'Alias Name');

        // Assert
        final aliases = await databaseService.getWingAliases(wingId);
        expect(aliases, contains('Alias Name'));
      });

      test('should get wing aliases', () async {
        // Arrange
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        await databaseService.addWingAlias(wingId, 'Alias 1');
        await databaseService.addWingAlias(wingId, 'Alias 2');

        // Act
        final aliases = await databaseService.getWingAliases(wingId);

        // Assert
        expect(aliases, hasLength(2));
        expect(aliases, containsAll(['Alias 1', 'Alias 2']));
      });

      test('should remove wing alias', () async {
        // Arrange
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        await databaseService.addWingAlias(wingId, 'Alias to Remove');
        await databaseService.addWingAlias(wingId, 'Alias to Keep');

        // Act
        await databaseService.removeWingAlias(wingId, 'Alias to Remove');

        // Assert
        final aliases = await databaseService.getWingAliases(wingId);
        expect(aliases, hasLength(1));
        expect(aliases, contains('Alias to Keep'));
        expect(aliases, isNot(contains('Alias to Remove')));
      });

      test('should find wing by name or alias', () async {
        // Arrange
        final testWing = TestHelpers.createTestWing(name: 'Original Name');
        final wingId = await databaseService.insertWing(testWing);
        await databaseService.addWingAlias(wingId, 'Test Alias');

        // Act & Assert
        final foundByName = await databaseService.findWingByNameOrAlias('Original Name');
        expect(foundByName, isNotNull);
        expect(foundByName!.id, equals(wingId));

        final foundByAlias = await databaseService.findWingByNameOrAlias('Test Alias');
        expect(foundByAlias, isNotNull);
        expect(foundByAlias!.id, equals(wingId));

        final notFound = await databaseService.findWingByNameOrAlias('Non-existent');
        expect(notFound, isNull);
      });
    });

    group('Flight Statistics Operations', () {
      test('should get overall statistics', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        // Insert test flights with known values
        final flight1 = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
          duration: 120, // 2 hours
          maxAltitude: 2000.0,
        );
        final flight2 = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
          duration: 180, // 3 hours
          maxAltitude: 2500.0,
        );

        await databaseService.insertFlight(flight1);
        await databaseService.insertFlight(flight2);

        // Act
        final stats = await databaseService.getOverallStatistics();

        // Assert
        expect(stats['totalFlights'], equals(2));
        expect(stats['totalDuration'], equals(300)); // 120 + 180
        expect(stats['highestAltitude'], equals(2500.0));
        expect(stats['averageDuration'], equals(150.0)); // 300 / 2
        expect(stats['averageAltitude'], equals(2250.0)); // (2000 + 2500) / 2
      });

      test('should get yearly statistics', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        // Insert flights in different years
        final flight2022 = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
          date: DateTime(2022, 6, 1),
          duration: 120,
          maxAltitude: 2000.0,
        );
        final flight2023 = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
          date: DateTime(2023, 6, 1),
          duration: 180,
          maxAltitude: 2500.0,
        );

        await databaseService.insertFlight(flight2022);
        await databaseService.insertFlight(flight2023);

        // Act
        final stats = await databaseService.getYearlyStatistics();

        // Assert
        expect(stats, hasLength(2));
        
        // Find 2023 stats (should be first due to DESC order)
        final stats2023 = stats.firstWhere((s) => s['year'] == 2023);
        expect(stats2023['flight_count'], equals(1));
        expect(stats2023['total_hours'], equals(3.0)); // 180 minutes / 60
        expect(stats2023['max_altitude'], equals(2500.0));

        final stats2022 = stats.firstWhere((s) => s['year'] == 2022);
        expect(stats2022['flight_count'], equals(1));
        expect(stats2022['total_hours'], equals(2.0)); // 120 minutes / 60
        expect(stats2022['max_altitude'], equals(2000.0));
      });

      test('should get flight hours by year', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        final flight2023 = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
          date: DateTime(2023, 6, 1),
          duration: 240, // 4 hours
        );

        await databaseService.insertFlight(flight2023);

        // Act
        final hoursByYear = await databaseService.getFlightHoursByYear();

        // Assert
        expect(hoursByYear, containsPair(2023, 4.0));
      });

      test('should get site statistics', () async {
        // Arrange
        final site1 = TestHelpers.createTestSite(name: 'Popular Site');
        final site2 = TestHelpers.createTestSite(name: 'Less Popular Site');
        final site1Id = await databaseService.insertSite(site1);
        final site2Id = await databaseService.insertSite(site2);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        // More flights from site1
        for (int i = 0; i < 3; i++) {
          final flight = TestHelpers.createTestFlight(
            launchSiteId: site1Id,
            wingId: wingId,
            duration: 120,
          );
          await databaseService.insertFlight(flight);
        }

        // One flight from site2
        final flight2 = TestHelpers.createTestFlight(
          launchSiteId: site2Id,
          wingId: wingId,
          duration: 60,
        );
        await databaseService.insertFlight(flight2);

        // Act
        final siteStats = await databaseService.getSiteStatistics();

        // Assert
        expect(siteStats, hasLength(2));
        
        // Should be ordered by flight_count DESC
        final popularSiteStats = siteStats.first;
        expect(popularSiteStats['name'], equals('Popular Site'));
        expect(popularSiteStats['flight_count'], equals(3));
        expect(popularSiteStats['total_hours'], equals(6.0)); // 3 * 120 minutes / 60

        final lesserSiteStats = siteStats.last;
        expect(lesserSiteStats['name'], equals('Less Popular Site'));
        expect(lesserSiteStats['flight_count'], equals(1));
        expect(lesserSiteStats['total_hours'], equals(1.0)); // 60 minutes / 60
      });

      test('should get wing statistics', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);
        
        final wing1 = TestHelpers.createTestWing(
          manufacturer: 'Manufacturer A',
          name: 'Model X',
          size: 'M',
        ).copyWith(active: true);
        final wing2 = TestHelpers.createTestWing(
          manufacturer: 'Manufacturer B',
          name: 'Model Y',
          size: 'L',
        ).copyWith(active: true);
        
        final wing1Id = await databaseService.insertWing(wing1);
        final wing2Id = await databaseService.insertWing(wing2);

        // More flights with wing1
        for (int i = 0; i < 2; i++) {
          final flight = TestHelpers.createTestFlight(
            launchSiteId: siteId,
            wingId: wing1Id,
            duration: 150,
          );
          await databaseService.insertFlight(flight);
        }

        // One flight with wing2
        final flight2 = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wing2Id,
          duration: 90,
        );
        await databaseService.insertFlight(flight2);

        // Act
        final wingStats = await databaseService.getWingStatistics();

        // Assert
        expect(wingStats, hasLength(2));
        
        // Should be ordered by flight_count DESC
        final popularWingStats = wingStats.first;
        expect(popularWingStats['manufacturer'], equals('Manufacturer A'));
        expect(popularWingStats['model'], equals('Model X'));
        expect(popularWingStats['flight_count'], equals(2));
        expect(popularWingStats['total_hours'], equals(5.0)); // 2 * 150 minutes / 60

        final lesserWingStats = wingStats.last;
        expect(lesserWingStats['manufacturer'], equals('Manufacturer B'));
        expect(lesserWingStats['model'], equals('Model Y'));
        expect(lesserWingStats['flight_count'], equals(1));
        expect(lesserWingStats['total_hours'], equals(1.5)); // 90 minutes / 60
      });
    });

    group('Flight Query Operations', () {
      test('should get flights by date range', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        final flight1 = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
          date: DateTime(2023, 6, 1),
          notes: 'Flight in range',
        );
        final flight2 = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
          date: DateTime(2023, 12, 1),
          notes: 'Flight out of range',
        );

        await databaseService.insertFlight(flight1);
        await databaseService.insertFlight(flight2);

        // Act
        final flights = await databaseService.getFlightsByDateRange(
          DateTime(2023, 5, 1),
          DateTime(2023, 7, 1),
        );

        // Assert
        expect(flights, hasLength(1));
        expect(flights.first.notes, equals('Flight in range'));
      });

      test('should get flights by site', () async {
        // Arrange
        final site1 = TestHelpers.createTestSite(name: 'Site 1');
        final site2 = TestHelpers.createTestSite(name: 'Site 2');
        final site1Id = await databaseService.insertSite(site1);
        final site2Id = await databaseService.insertSite(site2);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        final flight1 = TestHelpers.createTestFlight(
          launchSiteId: site1Id,
          wingId: wingId,
          notes: 'Flight from site 1',
        );
        final flight2 = TestHelpers.createTestFlight(
          launchSiteId: site2Id,
          wingId: wingId,
          notes: 'Flight from site 2',
        );

        await databaseService.insertFlight(flight1);
        await databaseService.insertFlight(flight2);

        // Act
        final flights = await databaseService.getFlightsBySite(site1Id);

        // Assert
        expect(flights, hasLength(1));
        expect(flights.first.notes, equals('Flight from site 1'));
        expect(flights.first.launchSiteName, equals('Site 1'));
      });

      test('should get flights by wing', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);
        
        final wing1 = TestHelpers.createTestWing(name: 'Wing 1');
        final wing2 = TestHelpers.createTestWing(name: 'Wing 2');
        final wing1Id = await databaseService.insertWing(wing1);
        final wing2Id = await databaseService.insertWing(wing2);

        final flight1 = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wing1Id,
          notes: 'Flight with wing 1',
        );
        final flight2 = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wing2Id,
          notes: 'Flight with wing 2',
        );

        await databaseService.insertFlight(flight1);
        await databaseService.insertFlight(flight2);

        // Act
        final flights = await databaseService.getFlightsByWing(wing1Id);

        // Assert
        expect(flights, hasLength(1));
        expect(flights.first.notes, equals('Flight with wing 1'));
      });

      test('should find flight by filename', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        final flight = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
        ).copyWith(originalFilename: 'test_flight.igc');

        await databaseService.insertFlight(flight);

        // Act
        final found = await databaseService.findFlightByFilename('test_flight.igc');

        // Assert
        expect(found, isNotNull);
        expect(found!.originalFilename, equals('test_flight.igc'));
      });

      test('should find flight by date and time', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        final flight = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
          date: DateTime(2023, 6, 1),
          launchTime: '10:30',
        );

        await databaseService.insertFlight(flight);

        // Act
        final found = await databaseService.findFlightByDateTime(
          DateTime(2023, 6, 1),
          '10:30',
        );

        // Assert
        expect(found, isNotNull);
        expect(found!.date, equals(DateTime(2023, 6, 1)));
        expect(found.launchTime, equals('10:30'));
      });

      test('should search flights by query', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite(name: 'Mountain Site');
        final siteId = await databaseService.insertSite(testSite);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        final flight1 = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
          notes: 'Great thermal conditions today',
        );
        final flight2 = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wingId,
          notes: 'Windy day at the mountain',
        );

        await databaseService.insertFlight(flight1);
        await databaseService.insertFlight(flight2);

        // Act
        final thermalResults = await databaseService.searchFlights('thermal');
        final mountainResults = await databaseService.searchFlights('mountain');

        // Assert
        expect(thermalResults, hasLength(1));
        expect(thermalResults.first.notes, contains('thermal'));

        expect(mountainResults, hasLength(2)); // One in notes, one in site name
      });
    });

    group('Error Handling and Constraints', () {
      test('should handle concurrent operations safely', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        // Act - Simulate concurrent inserts
        final futures = <Future<int>>[];
        for (int i = 0; i < 5; i++) {
          final flight = TestHelpers.createTestFlight(
            launchSiteId: siteId,
            wingId: wingId,
            notes: 'Concurrent flight $i',
          );
          futures.add(databaseService.insertFlight(flight));
        }

        final results = await Future.wait(futures);

        // Assert
        expect(results, hasLength(5));
        expect(results.every((id) => id > 0), isTrue);

        final count = await databaseService.getFlightCount();
        expect(count, equals(5));
      });

      test('should handle foreign key constraint violations gracefully', () async {
        // Arrange
        final invalidFlight = TestHelpers.createTestFlight(
          launchSiteId: 999, // Non-existent site
          wingId: 999, // Non-existent wing
        );

        // Act & Assert
        expect(
          () => databaseService.insertFlight(invalidFlight),
          throwsA(isA<Exception>()),
        );
      });

      test('should handle empty query results correctly', () async {
        // Act
        final flights = await databaseService.getAllFlights();
        final sites = await databaseService.getAllSites();
        final wings = await databaseService.getAllWings();

        // Assert
        expect(flights, isEmpty);
        expect(sites, isEmpty);
        expect(wings, isEmpty);
      });

      test('should handle edge cases in statistics calculations', () async {
        // Act - Get statistics with no data
        final stats = await databaseService.getOverallStatistics();

        // Assert
        expect(stats['totalFlights'], equals(0));
        expect(stats['totalDuration'], equals(0));
        expect(stats['highestAltitude'], equals(0.0));
        expect(stats['averageDuration'], equals(0.0));
        expect(stats['averageAltitude'], equals(0.0));
      });
    });

    group('Site Relationship Operations', () {
      test('should get flight count for site', () async {
        // Arrange
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        // Add multiple flights to the site
        for (int i = 0; i < 3; i++) {
          final flight = TestHelpers.createTestFlight(
            launchSiteId: siteId,
            wingId: wingId,
          );
          await databaseService.insertFlight(flight);
        }

        // Act
        final count = await databaseService.getFlightCountForSite(siteId);

        // Assert
        expect(count, equals(3));
      });

      test('should reassign flights between sites', () async {
        // Arrange
        final site1 = TestHelpers.createTestSite(name: 'Site 1');
        final site2 = TestHelpers.createTestSite(name: 'Site 2');
        final site1Id = await databaseService.insertSite(site1);
        final site2Id = await databaseService.insertSite(site2);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        // Add flights to site1
        for (int i = 0; i < 3; i++) {
          final flight = TestHelpers.createTestFlight(
            launchSiteId: site1Id,
            wingId: wingId,
          );
          await databaseService.insertFlight(flight);
        }

        // Act
        final reassignedCount = await databaseService.reassignFlights(site1Id, site2Id);

        // Assert
        expect(reassignedCount, equals(3));

        final site1Count = await databaseService.getFlightCountForSite(site1Id);
        final site2Count = await databaseService.getFlightCountForSite(site2Id);
        
        expect(site1Count, equals(0));
        expect(site2Count, equals(3));
      });

      test('should check if site can be deleted', () async {
        // Arrange
        final site1 = TestHelpers.createTestSite(name: 'Site with flights');
        final site2 = TestHelpers.createTestSite(name: 'Empty site');
        final site1Id = await databaseService.insertSite(site1);
        final site2Id = await databaseService.insertSite(site2);
        
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);

        // Add a flight to site1
        final flight = TestHelpers.createTestFlight(
          launchSiteId: site1Id,
          wingId: wingId,
        );
        await databaseService.insertFlight(flight);

        // Act & Assert
        final canDeleteSite1 = await databaseService.canDeleteSite(site1Id);
        final canDeleteSite2 = await databaseService.canDeleteSite(site2Id);

        expect(canDeleteSite1, isFalse);
        expect(canDeleteSite2, isTrue);
      });
    });

    group('Wing Relationship Operations', () {
      test('should check if wing can be deleted', () async {
        // Arrange
        final wing1 = TestHelpers.createTestWing(name: 'Wing with flights');
        final wing2 = TestHelpers.createTestWing(name: 'Unused wing');
        final wing1Id = await databaseService.insertWing(wing1);
        final wing2Id = await databaseService.insertWing(wing2);
        
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);

        // Add a flight with wing1
        final flight = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: wing1Id,
        );
        await databaseService.insertFlight(flight);

        // Act & Assert
        final canDeleteWing1 = await databaseService.canDeleteWing(wing1Id);
        final canDeleteWing2 = await databaseService.canDeleteWing(wing2Id);

        expect(canDeleteWing1, isFalse);
        expect(canDeleteWing2, isTrue);
      });

      test('should get wing statistics by ID', () async {
        // Arrange
        final testWing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(testWing);
        
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);

        // Add flights with known durations
        for (int i = 0; i < 3; i++) {
          final flight = TestHelpers.createTestFlight(
            launchSiteId: siteId,
            wingId: wingId,
            duration: 120, // 2 hours each
          );
          await databaseService.insertFlight(flight);
        }

        // Act
        final stats = await databaseService.getWingStatisticsById(wingId);

        // Assert
        expect(stats['totalFlights'], equals(3));
        expect(stats['totalDuration'], equals(360)); // 3 * 120 minutes
      });

      test('should merge multiple wings', () async {
        // Arrange
        final primaryWing = TestHelpers.createTestWing(name: 'Primary Wing');
        final duplicateWing1 = TestHelpers.createTestWing(name: 'Duplicate 1');
        final duplicateWing2 = TestHelpers.createTestWing(name: 'Duplicate 2');
        
        final primaryWingId = await databaseService.insertWing(primaryWing);
        final duplicate1Id = await databaseService.insertWing(duplicateWing1);
        final duplicate2Id = await databaseService.insertWing(duplicateWing2);
        
        final testSite = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(testSite);

        // Add flights to duplicate wings
        final flight1 = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: duplicate1Id,
          notes: 'Flight with duplicate 1',
        );
        final flight2 = TestHelpers.createTestFlight(
          launchSiteId: siteId,
          wingId: duplicate2Id,
          notes: 'Flight with duplicate 2',
        );

        await databaseService.insertFlight(flight1);
        await databaseService.insertFlight(flight2);

        // Add aliases to duplicate wings
        await databaseService.addWingAlias(duplicate1Id, 'Alias 1');

        // Act
        await databaseService.mergeWings(primaryWingId, [duplicate1Id, duplicate2Id]);

        // Assert
        // Check that flights are now assigned to primary wing
        final flightsWithPrimaryWing = await databaseService.getFlightsByWing(primaryWingId);
        expect(flightsWithPrimaryWing, hasLength(2));

        // Check that duplicate wings no longer exist
        final duplicate1 = await databaseService.getWing(duplicate1Id);
        final duplicate2 = await databaseService.getWing(duplicate2Id);
        expect(duplicate1, isNull);
        expect(duplicate2, isNull);

        // Check that wing names were added as aliases
        final aliases = await databaseService.getWingAliases(primaryWingId);
        expect(aliases, containsAll(['Duplicate 1', 'Duplicate 2', 'Alias 1']));
      });

      test('should find potential duplicate wings', () async {
        // Arrange
        final wing1 = TestHelpers.createTestWing(
          name: 'Test Wing',
          manufacturer: 'Test Manufacturer',
        );
        final wing2 = TestHelpers.createTestWing(
          name: 'Test-Wing', // Similar name with hyphen
          manufacturer: 'Test Manufacturer',
        );
        final wing3 = TestHelpers.createTestWing(
          name: 'Different Wing',
          manufacturer: 'Different Manufacturer',
        );

        await databaseService.insertWing(wing1);
        await databaseService.insertWing(wing2);
        await databaseService.insertWing(wing3);

        // Act
        final potentialDuplicates = await databaseService.findPotentialDuplicateWings();

        // Assert
        expect(potentialDuplicates, isNotEmpty);
        // Should group wings with similar names
        final duplicateGroups = potentialDuplicates.values.where((group) => group.length > 1);
        expect(duplicateGroups, isNotEmpty);
      });
    });
  });
}