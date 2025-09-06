import 'package:flutter_test/flutter_test.dart';
import 'package:free_flight_log_app/services/database_service.dart';
import 'package:free_flight_log_app/data/models/flight.dart';
import 'package:free_flight_log_app/data/models/site.dart';
import 'package:free_flight_log_app/data/models/wing.dart';
import 'helpers/test_helpers.dart';

void main() {
  group('DatabaseService Tests', () {
    late DatabaseService databaseService;

    setUpAll(() {
      TestHelpers.initializeDatabaseForTesting();
    });

    setUp(() {
      databaseService = DatabaseService.instance;
    });

    group('Flight CRUD Operations', () {
      test('should insert a flight successfully', () async {
        final flight = TestHelpers.createTestFlight();
        final id = await databaseService.insertFlight(flight);
        
        expect(id, greaterThan(0));
      });

      test('should retrieve a flight by id', () async {
        final flight = TestHelpers.createTestFlight();
        final id = await databaseService.insertFlight(flight);
        
        final retrieved = await databaseService.getFlight(id);
        
        expect(retrieved, isNotNull);
        expect(retrieved!.id, equals(id));
        expect(retrieved.duration, equals(flight.duration));
      });

      test('should update a flight successfully', () async {
        final flight = TestHelpers.createTestFlight();
        final id = await databaseService.insertFlight(flight);
        
        final updatedFlight = flight.copyWith(
          id: id,
          duration: 180,
          notes: 'Updated test flight',
        );
        
        final result = await databaseService.updateFlight(updatedFlight);
        expect(result, equals(1));
        
        final retrieved = await databaseService.getFlight(id);
        expect(retrieved!.duration, equals(180));
        expect(retrieved.notes, equals('Updated test flight'));
      });

      test('should delete a flight successfully', () async {
        final flight = TestHelpers.createTestFlight();
        final id = await databaseService.insertFlight(flight);
        
        final result = await databaseService.deleteFlight(id);
        expect(result, equals(1));
        
        final retrieved = await databaseService.getFlight(id);
        expect(retrieved, isNull);
      });

      test('should get all flights ordered by date', () async {
        final flight1 = TestHelpers.createTestFlight(
          date: DateTime.now().subtract(Duration(days: 1)),
          duration: 120,
        );
        final flight2 = TestHelpers.createTestFlight(
          date: DateTime.now(),
          duration: 180,
        );
        
        await databaseService.insertFlight(flight1);
        await databaseService.insertFlight(flight2);
        
        final flights = await databaseService.getAllFlights();
        
        expect(flights.length, greaterThanOrEqualTo(2));
        // Most recent first
        expect(flights.first.date.isAfter(flights[1].date) || 
               flights.first.date.isAtSameMomentAs(flights[1].date), isTrue);
      });

      test('should get flight count correctly', () async {
        final initialCount = await databaseService.getFlightCount();
        
        final flight = TestHelpers.createTestFlight();
        await databaseService.insertFlight(flight);
        
        final newCount = await databaseService.getFlightCount();
        expect(newCount, equals(initialCount + 1));
      });

      test('should handle flight insertion error gracefully', () async {
        final flight = Flight(
          // Invalid flight with missing required fields to trigger constraint error
          id: null,
          date: DateTime.now(),
          launchTime: '',
          landingTime: '',
          duration: -1, // Invalid duration
          launchSiteId: null,
          maxAltitude: 0,
          maxClimbRate: 0,
          maxSinkRate: 0,
          distance: 0,
          straightDistance: 0,
          wingId: null,
          notes: '',
          source: 'test',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(
          () async => await databaseService.insertFlight(flight),
          throwsA(isA<Exception>()),
        );
      });

      test('should return null for non-existent flight', () async {
        final retrieved = await databaseService.getFlight(99999);
        expect(retrieved, isNull);
      });
    });

    group('Site Management Operations', () {
      test('should insert a site successfully', () async {
        final site = TestHelpers.createTestSite();
        final id = await databaseService.insertSite(site);
        
        expect(id, greaterThan(0));
      });

      test('should retrieve a site by id', () async {
        final site = TestHelpers.createTestSite();
        final id = await databaseService.insertSite(site);
        
        final retrieved = await databaseService.getSite(id);
        
        expect(retrieved, isNotNull);
        expect(retrieved!.id, equals(id));
        expect(retrieved.name, equals(site.name));
      });

      test('should update a site successfully', () async {
        final site = TestHelpers.createTestSite();
        final id = await databaseService.insertSite(site);
        
        final updatedSite = site.copyWith(
          id: id,
          name: 'Updated Test Site',
          altitude: 2000.0,
        );
        
        final result = await databaseService.updateSite(updatedSite);
        expect(result, equals(1));
        
        final retrieved = await databaseService.getSite(id);
        expect(retrieved!.name, equals('Updated Test Site'));
        expect(retrieved.altitude, equals(2000.0));
      });

      test('should delete a site successfully', () async {
        final site = TestHelpers.createTestSite();
        final id = await databaseService.insertSite(site);
        
        final result = await databaseService.deleteSite(id);
        expect(result, equals(1));
        
        final retrieved = await databaseService.getSite(id);
        expect(retrieved, isNull);
      });

      test('should get all sites ordered by name', () async {
        final site1 = TestHelpers.createTestSite(name: 'B Site');
        final site2 = TestHelpers.createTestSite(name: 'A Site');
        
        await databaseService.insertSite(site1);
        await databaseService.insertSite(site2);
        
        final sites = await databaseService.getAllSites();
        
        expect(sites.length, greaterThanOrEqualTo(2));
        // Should be ordered by name ASC
        bool isSorted = true;
        for (int i = 0; i < sites.length - 1; i++) {
          if (sites[i].name.compareTo(sites[i + 1].name) > 0) {
            isSorted = false;
            break;
          }
        }
        expect(isSorted, isTrue);
      });

      test('should find site by coordinates', () async {
        final site = TestHelpers.createTestSite(
          latitude: 46.5197,
          longitude: 6.6323,
        );
        final id = await databaseService.insertSite(site);
        
        final found = await databaseService.findSiteByCoordinates(
          46.5197,
          6.6323,
          tolerance: 0.001,
        );
        
        expect(found, isNotNull);
        expect(found!.id, equals(id));
      });

      test('should search sites by name', () async {
        final site = TestHelpers.createTestSite(name: 'Mont Blanc Launch');
        await databaseService.insertSite(site);
        
        final results = await databaseService.searchSites('Mont');
        
        expect(results.isNotEmpty, isTrue);
        expect(results.any((s) => s.name.contains('Mont')), isTrue);
      });

      test('should find or create site', () async {
        // First call should create new site
        final site1 = await databaseService.findOrCreateSite(
          latitude: 47.0,
          longitude: 8.0,
          name: 'New Test Site',
        );
        
        expect(site1.id, isNotNull);
        expect(site1.name, equals('New Test Site'));
        
        // Second call with same coordinates should return existing site
        final site2 = await databaseService.findOrCreateSite(
          latitude: 47.0,
          longitude: 8.0,
          name: 'Different Name',
        );
        
        expect(site2.id, equals(site1.id));
        expect(site2.name, equals('New Test Site')); // Original name preserved
      });

      test('should get sites within bounds', () async {
        final site = TestHelpers.createTestSite(
          latitude: 46.0,
          longitude: 6.0,
        );
        await databaseService.insertSite(site);
        
        final sites = await databaseService.getSitesInBounds(
          north: 47.0,
          south: 45.0,
          east: 7.0,
          west: 5.0,
        );
        
        expect(sites.any((s) => s.latitude == 46.0 && s.longitude == 6.0), isTrue);
      });
    });

    group('Wing Management Operations', () {
      test('should insert a wing successfully', () async {
        final wing = TestHelpers.createTestWing();
        final id = await databaseService.insertWing(wing);
        
        expect(id, greaterThan(0));
      });

      test('should retrieve a wing by id', () async {
        final wing = TestHelpers.createTestWing();
        final id = await databaseService.insertWing(wing);
        
        final retrieved = await databaseService.getWing(id);
        
        expect(retrieved, isNotNull);
        expect(retrieved!.id, equals(id));
        expect(retrieved.name, equals(wing.name));
      });

      test('should update a wing successfully', () async {
        final wing = TestHelpers.createTestWing();
        final id = await databaseService.insertWing(wing);
        
        final updatedWing = wing.copyWith(
          id: id,
          name: 'Updated Wing',
          size: 'L',
        );
        
        final result = await databaseService.updateWing(updatedWing);
        expect(result, equals(1));
        
        final retrieved = await databaseService.getWing(id);
        expect(retrieved!.name, equals('Updated Wing'));
        expect(retrieved.size, equals('L'));
      });

      test('should delete a wing successfully', () async {
        final wing = TestHelpers.createTestWing();
        final id = await databaseService.insertWing(wing);
        
        final result = await databaseService.deleteWing(id);
        expect(result, equals(1));
        
        final retrieved = await databaseService.getWing(id);
        expect(retrieved, isNull);
      });

      test('should get active wings only', () async {
        final activeWing = TestHelpers.createTestWing(name: 'Active Wing');
        final inactiveWing = TestHelpers.createTestWing(name: 'Inactive Wing').copyWith(active: false);
        
        await databaseService.insertWing(activeWing);
        final inactiveId = await databaseService.insertWing(inactiveWing);
        await databaseService.deactivateWing(inactiveId);
        
        final activeWings = await databaseService.getActiveWings();
        
        expect(activeWings.every((w) => w.active), isTrue);
      });

      test('should deactivate wing', () async {
        final wing = TestHelpers.createTestWing();
        final id = await databaseService.insertWing(wing);
        
        final result = await databaseService.deactivateWing(id);
        expect(result, equals(1));
        
        final retrieved = await databaseService.getWing(id);
        expect(retrieved!.active, isFalse);
      });

      test('should find or create wing', () async {
        final wing1 = await databaseService.findOrCreateWing(
          manufacturer: 'Test Manufacturer',
          model: 'Test Model',
          size: 'M',
        );
        
        expect(wing1.id, isNotNull);
        expect(wing1.manufacturer, equals('Test Manufacturer'));
        
        // Second call should return existing wing
        final wing2 = await databaseService.findOrCreateWing(
          manufacturer: 'Test Manufacturer',
          model: 'Test Model',
          size: 'M',
        );
        
        expect(wing2.id, equals(wing1.id));
      });
    });

    group('Wing Alias Operations', () {
      test('should add and get wing aliases', () async {
        final wing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(wing);
        
        await databaseService.addWingAlias(wingId, 'Test Alias 1');
        await databaseService.addWingAlias(wingId, 'Test Alias 2');
        
        final aliases = await databaseService.getWingAliases(wingId);
        
        expect(aliases.length, equals(2));
        expect(aliases.contains('Test Alias 1'), isTrue);
        expect(aliases.contains('Test Alias 2'), isTrue);
      });

      test('should remove wing alias', () async {
        final wing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(wing);
        
        await databaseService.addWingAlias(wingId, 'Test Alias');
        
        var aliases = await databaseService.getWingAliases(wingId);
        expect(aliases.length, equals(1));
        
        await databaseService.removeWingAlias(wingId, 'Test Alias');
        
        aliases = await databaseService.getWingAliases(wingId);
        expect(aliases.length, equals(0));
      });

      test('should find wing by name or alias', () async {
        final wing = TestHelpers.createTestWing(name: 'Primary Wing Name');
        final wingId = await databaseService.insertWing(wing);
        
        await databaseService.addWingAlias(wingId, 'Wing Alias');
        
        // Find by primary name
        final foundByName = await databaseService.findWingByNameOrAlias('Primary Wing Name');
        expect(foundByName, isNotNull);
        expect(foundByName!.id, equals(wingId));
        
        // Find by alias
        final foundByAlias = await databaseService.findWingByNameOrAlias('Wing Alias');
        expect(foundByAlias, isNotNull);
        expect(foundByAlias!.id, equals(wingId));
      });

      test('should return null when wing not found by name or alias', () async {
        final result = await databaseService.findWingByNameOrAlias('Non-existent Wing');
        expect(result, isNull);
      });
    });

    group('Flight Statistics Operations', () {
      test('should get overall statistics', () async {
        final flight = TestHelpers.createTestFlight(duration: 120, maxAltitude: 2000.0);
        await databaseService.insertFlight(flight);
        
        final stats = await databaseService.getOverallStatistics();
        
        expect(stats['totalFlights'], greaterThanOrEqualTo(1));
        expect(stats['totalDuration'], greaterThanOrEqualTo(120));
        expect(stats['highestAltitude'], greaterThanOrEqualTo(2000.0));
      });

      test('should get yearly statistics', () async {
        final flight = TestHelpers.createTestFlight(
          date: DateTime(2023, 6, 15),
          duration: 120,
        );
        await databaseService.insertFlight(flight);
        
        final yearlyStats = await databaseService.getYearlyStatistics();
        
        expect(yearlyStats.isNotEmpty, isTrue);
        final stats2023 = yearlyStats.firstWhere(
          (stat) => stat['year'] == 2023,
          orElse: () => <String, dynamic>{},
        );
        expect(stats2023.isNotEmpty, isTrue);
        expect(stats2023['flight_count'], greaterThanOrEqualTo(1));
      });

      test('should get flight hours by year', () async {
        final flight = TestHelpers.createTestFlight(
          date: DateTime(2023, 6, 15),
          duration: 120, // 2 hours
        );
        await databaseService.insertFlight(flight);
        
        final hoursByYear = await databaseService.getFlightHoursByYear();
        
        expect(hoursByYear.containsKey(2023), isTrue);
        expect(hoursByYear[2023], greaterThanOrEqualTo(2.0));
      });

      test('should get wing statistics', () async {
        final wing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(wing);
        
        final flight = TestHelpers.createTestFlight(wingId: wingId, duration: 120);
        await databaseService.insertFlight(flight);
        
        final wingStats = await databaseService.getWingStatistics();
        
        expect(wingStats.isNotEmpty, isTrue);
        final wingStat = wingStats.firstWhere(
          (stat) => stat['name'] == wing.name,
          orElse: () => <String, dynamic>{},
        );
        expect(wingStat.isNotEmpty, isTrue);
        expect(wingStat['flight_count'], greaterThanOrEqualTo(1));
      });

      test('should get site statistics', () async {
        final site = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(site);
        
        final flight = TestHelpers.createTestFlight(launchSiteId: siteId, duration: 120);
        await databaseService.insertFlight(flight);
        
        final siteStats = await databaseService.getSiteStatistics();
        
        expect(siteStats.isNotEmpty, isTrue);
        final siteStat = siteStats.firstWhere(
          (stat) => stat['name'] == site.name,
          orElse: () => <String, dynamic>{},
        );
        expect(siteStat.isNotEmpty, isTrue);
        expect(siteStat['flight_count'], greaterThanOrEqualTo(1));
      });

      test('should get wing statistics by id', () async {
        final wing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(wing);
        
        final flight = TestHelpers.createTestFlight(wingId: wingId, duration: 120);
        await databaseService.insertFlight(flight);
        
        final stats = await databaseService.getWingStatisticsById(wingId);
        
        expect(stats['totalFlights'], greaterThanOrEqualTo(1));
        expect(stats['totalDuration'], greaterThanOrEqualTo(120));
      });
    });

    group('Flight Query Operations', () {
      test('should get flights by date range', () async {
        final startDate = DateTime(2023, 6, 1);
        final endDate = DateTime(2023, 6, 30);
        final withinRange = TestHelpers.createTestFlight(date: DateTime(2023, 6, 15));
        final outsideRange = TestHelpers.createTestFlight(date: DateTime(2023, 7, 15));
        
        await databaseService.insertFlight(withinRange);
        await databaseService.insertFlight(outsideRange);
        
        final flights = await databaseService.getFlightsByDateRange(startDate, endDate);
        
        expect(flights.any((f) => f.date.month == 6), isTrue);
        expect(flights.every((f) => f.date.isAfter(startDate.subtract(Duration(days: 1))) && 
                                    f.date.isBefore(endDate.add(Duration(days: 1)))), isTrue);
      });

      test('should get flights by site', () async {
        final site = TestHelpers.createTestSite(name: 'Test Launch Site');
        final siteId = await databaseService.insertSite(site);
        
        final flight = TestHelpers.createTestFlight(launchSiteId: siteId);
        await databaseService.insertFlight(flight);
        
        final flights = await databaseService.getFlightsBySite(siteId);
        
        expect(flights.isNotEmpty, isTrue);
        expect(flights.every((f) => f.launchSiteId == siteId), isTrue);
      });

      test('should get flights by wing', () async {
        final wing = TestHelpers.createTestWing(name: 'Test Wing');
        final wingId = await databaseService.insertWing(wing);
        
        final flight = TestHelpers.createTestFlight(wingId: wingId);
        await databaseService.insertFlight(flight);
        
        final flights = await databaseService.getFlightsByWing(wingId);
        
        expect(flights.isNotEmpty, isTrue);
        expect(flights.every((f) => f.wingId == wingId), isTrue);
      });

      test('should find flight by filename', () async {
        final flight = TestHelpers.createTestFlight().copyWith(
          originalFilename: 'test_flight.igc',
        );
        await databaseService.insertFlight(flight);
        
        final found = await databaseService.findFlightByFilename('test_flight.igc');
        
        expect(found, isNotNull);
        expect(found!.originalFilename, equals('test_flight.igc'));
      });

      test('should find flight by date and time', () async {
        final flightDate = DateTime(2023, 6, 15);
        final launchTime = '10:30';
        
        final flight = TestHelpers.createTestFlight(
          date: flightDate,
          launchTime: launchTime,
        );
        await databaseService.insertFlight(flight);
        
        final found = await databaseService.findFlightByDateTime(flightDate, launchTime);
        
        expect(found, isNotNull);
        expect(found!.launchTime, equals(launchTime));
      });

      test('should search flights by text', () async {
        final flight = TestHelpers.createTestFlight(notes: 'Great thermal flight');
        await databaseService.insertFlight(flight);
        
        final results = await databaseService.searchFlights('thermal');
        
        expect(results.isNotEmpty, isTrue);
        expect(results.any((f) => f.notes!.contains('thermal')), isTrue);
      });

      test('should get flights with launch coordinates in bounds', () async {
        final flight = TestHelpers.createTestFlight().copyWith(
          launchLatitude: 46.0,
          launchLongitude: 6.0,
        );
        await databaseService.insertFlight(flight);
        
        final flights = await databaseService.getAllLaunchesInBounds(
          north: 47.0,
          south: 45.0,
          east: 7.0,
          west: 5.0,
        );
        
        expect(flights.any((f) => f.launchLatitude == 46.0 && f.launchLongitude == 6.0), isTrue);
      });
    });

    group('Error Handling & Constraints', () {
      test('should handle concurrent operations safely', () async {
        final flight1 = TestHelpers.createTestFlight(notes: 'Flight 1');
        final flight2 = TestHelpers.createTestFlight(notes: 'Flight 2');
        
        // Perform concurrent inserts
        final futures = [
          databaseService.insertFlight(flight1),
          databaseService.insertFlight(flight2),
        ];
        
        final results = await Future.wait(futures);
        
        expect(results.length, equals(2));
        expect(results.every((id) => id > 0), isTrue);
        expect(results[0] != results[1], isTrue); // Different IDs
      });

      test('should check site deletion constraints', () async {
        final site = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(site);
        
        // Site with no flights should be deletable
        final canDeleteEmpty = await databaseService.canDeleteSite(siteId);
        expect(canDeleteEmpty, isTrue);
        
        // Add a flight to the site
        final flight = TestHelpers.createTestFlight(launchSiteId: siteId);
        await databaseService.insertFlight(flight);
        
        // Site with flights should not be deletable
        final canDeleteWithFlights = await databaseService.canDeleteSite(siteId);
        expect(canDeleteWithFlights, isFalse);
      });

      test('should check wing deletion constraints', () async {
        final wing = TestHelpers.createTestWing();
        final wingId = await databaseService.insertWing(wing);
        
        // Wing with no flights should be deletable
        final canDeleteEmpty = await databaseService.canDeleteWing(wingId);
        expect(canDeleteEmpty, isTrue);
        
        // Add a flight with the wing
        final flight = TestHelpers.createTestFlight(wingId: wingId);
        await databaseService.insertFlight(flight);
        
        // Wing with flights should not be deletable
        final canDeleteWithFlights = await databaseService.canDeleteWing(wingId);
        expect(canDeleteWithFlights, isFalse);
      });

      test('should handle empty search results', () async {
        final flights = await databaseService.searchFlights('nonexistent search term xyz');
        expect(flights, isEmpty);
        
        final sites = await databaseService.searchSites('nonexistent site name xyz');
        expect(sites, isEmpty);
      });
    });

    group('Site Relationship Operations', () {
      test('should count flights for site', () async {
        final site = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(site);
        
        final initialCount = await databaseService.getFlightCountForSite(siteId);
        expect(initialCount, equals(0));
        
        final flight = TestHelpers.createTestFlight(launchSiteId: siteId);
        await databaseService.insertFlight(flight);
        
        final newCount = await databaseService.getFlightCountForSite(siteId);
        expect(newCount, equals(1));
      });

      test('should reassign flights between sites', () async {
        final site1 = TestHelpers.createTestSite(name: 'Site 1');
        final site2 = TestHelpers.createTestSite(name: 'Site 2');
        final site1Id = await databaseService.insertSite(site1);
        final site2Id = await databaseService.insertSite(site2);
        
        final flight1 = TestHelpers.createTestFlight(launchSiteId: site1Id);
        final flight2 = TestHelpers.createTestFlight(launchSiteId: site1Id);
        await databaseService.insertFlight(flight1);
        await databaseService.insertFlight(flight2);
        
        final reassignedCount = await databaseService.reassignFlights(site1Id, site2Id);
        expect(reassignedCount, equals(2));
        
        final site1Count = await databaseService.getFlightCountForSite(site1Id);
        final site2Count = await databaseService.getFlightCountForSite(site2Id);
        expect(site1Count, equals(0));
        expect(site2Count, equals(2));
      });

      test('should get sites with flight counts', () async {
        final site = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(site);
        
        final flight = TestHelpers.createTestFlight(launchSiteId: siteId);
        await databaseService.insertFlight(flight);
        
        final sitesWithCounts = await databaseService.getSitesWithFlightCounts();
        
        expect(sitesWithCounts.isNotEmpty, isTrue);
        // Test that we get valid Site objects (the flight count is a transient property)
        expect(sitesWithCounts.every((s) => s.name.isNotEmpty), isTrue);
      });
    });

    group('Wing Relationship Operations', () {
      test('should handle wing merging operation', () async {
        final wing1 = TestHelpers.createTestWing(name: 'Wing 1');
        final wing2 = TestHelpers.createTestWing(name: 'Wing 2');
        final wing1Id = await databaseService.insertWing(wing1);
        final wing2Id = await databaseService.insertWing(wing2);
        
        // Add flights to wings
        final flight1 = TestHelpers.createTestFlight(wingId: wing1Id);
        final flight2 = TestHelpers.createTestFlight(wingId: wing2Id);
        await databaseService.insertFlight(flight1);
        await databaseService.insertFlight(flight2);
        
        // Merge wing2 into wing1
        await databaseService.mergeWings(wing1Id, [wing2Id]);
        
        // Verify flights were reassigned
        final wing1Flights = await databaseService.getFlightsByWing(wing1Id);
        expect(wing1Flights.length, equals(2));
        
        // Verify wing2 no longer exists
        final wing2Retrieved = await databaseService.getWing(wing2Id);
        expect(wing2Retrieved, isNull);
        
        // Verify wing2 name was added as alias
        final aliases = await databaseService.getWingAliases(wing1Id);
        expect(aliases.contains('Wing 2'), isTrue);
      });

      test('should find potential duplicate wings', () async {
        final wing1 = TestHelpers.createTestWing(
          manufacturer: 'Ozone',
          name: 'Rush 5',
        );
        final wing2 = TestHelpers.createTestWing(
          manufacturer: 'Ozone',
          name: 'Rush 5',
        );
        
        await databaseService.insertWing(wing1);
        await databaseService.insertWing(wing2);
        
        final duplicates = await databaseService.findPotentialDuplicateWings();
        
        expect(duplicates.isNotEmpty, isTrue);
        // Should find at least one group with multiple wings
        expect(duplicates.values.any((wings) => wings.length > 1), isTrue);
      });

      test('should get sites used in flights', () async {
        final site = TestHelpers.createTestSite();
        final siteId = await databaseService.insertSite(site);
        
        final flight = TestHelpers.createTestFlight(launchSiteId: siteId);
        await databaseService.insertFlight(flight);
        
        final usedSites = await databaseService.getSitesUsedInFlights();
        
        expect(usedSites.isNotEmpty, isTrue);
        expect(usedSites.any((s) => s.id == siteId), isTrue);
      });

      test('should bulk update flight sites', () async {
        final site1 = TestHelpers.createTestSite(name: 'Site 1');
        final site2 = TestHelpers.createTestSite(name: 'Site 2');
        final site1Id = await databaseService.insertSite(site1);
        final site2Id = await databaseService.insertSite(site2);
        
        final flight1 = TestHelpers.createTestFlight(launchSiteId: site1Id);
        final flight2 = TestHelpers.createTestFlight(launchSiteId: site1Id);
        final flight1Id = await databaseService.insertFlight(flight1);
        final flight2Id = await databaseService.insertFlight(flight2);
        
        await databaseService.bulkUpdateFlightSites([flight1Id, flight2Id], site2Id);
        
        final updatedFlight1 = await databaseService.getFlight(flight1Id);
        final updatedFlight2 = await databaseService.getFlight(flight2Id);
        
        expect(updatedFlight1!.launchSiteId, equals(site2Id));
        expect(updatedFlight2!.launchSiteId, equals(site2Id));
      });
    });
  });
}