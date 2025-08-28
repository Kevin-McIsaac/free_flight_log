// Cesium 3D Map Module - Refactored with idiomatic patterns
// Uses CustomDataSource, native time-dynamic properties, and efficient data management

// ============================================================================
// Backward Compatibility - cesiumLog shim
// ============================================================================

// Define cesiumLog for backward compatibility with Flutter-injected code
window.cesiumLog = {
    debug: (message) => {
        if (window.cesiumConfig?.debug) {
            console.log('[Cesium Debug] ' + message);
        }
    },
    info: (message) => console.log('[Cesium] ' + message),
    error: (message) => console.error('[Cesium Error] ' + message),
    warn: (message) => console.warn('[Cesium Warning] ' + message)
};

// ============================================================================
// Performance Reporting to Flutter
// ============================================================================

class PerformanceReporter {
    static report(metric, value) {
        // Log to console for visibility
        console.log(`[Performance] ${metric}: ${typeof value === 'number' ? value.toFixed(2) + 'ms' : value}`);
        
        // Also send to Flutter
        if (window.flutter_inappwebview?.callHandler) {
            window.flutter_inappwebview.callHandler('performanceMetric', { metric, value });
        }
    }
    
    static measureTime(operation, fn) {
        const start = performance.now();
        const result = fn();
        const duration = performance.now() - start;
        this.report(operation, duration);
        return result;
    }
}

// ============================================================================
// Cesium Performance Monitor - Detailed tracking for imagery provider switches
// ============================================================================

class CesiumPerformanceMonitor {
    constructor(viewer) {
        this.viewer = viewer;
        this.metrics = {
            providerSwitchStart: null,
            providerSwitchName: null,
            tilesRequested: 0,
            tilesLoaded: 0,
            tilesFailed: 0,
            frameDrops: 0,
            lastFrameTime: performance.now(),
            networkRequests: 0,
            memoryStart: 0,
            frameRateMonitor: null
        };
        
        this.isMonitoring = false;
        this.frameRateHistory = [];
        this.tileLoadListeners = [];
    }
    
    startProviderSwitch(providerName) {
        cesiumLog.info(`[PERF] Provider Switch Started: ${this.currentProvider || 'Unknown'} -> ${providerName}`);
        
        this.metrics.providerSwitchStart = performance.now();
        this.metrics.providerSwitchName = providerName;
        this.metrics.tilesRequested = 0;
        this.metrics.tilesLoaded = 0;
        this.metrics.tilesFailed = 0;
        this.metrics.frameDrops = 0;
        this.metrics.networkRequests = 0;
        this.frameRateHistory = [];
        
        // Capture pre-switch state
        this.metrics.memoryStart = this._getMemoryUsage();
        const cacheStats = this._getCacheStats();
        
        cesiumLog.info(`[PERF] Pre-switch: Memory: ${this.metrics.memoryStart}MB, Tiles cached: ${cacheStats.tileCount}`);
        
        // Start monitoring
        this.isMonitoring = true;
        this._startFrameRateMonitoring();
        this._startTileMonitoring();
        
        // Report to Flutter
        this._reportMetrics({
            event: 'providerSwitchStart',
            provider: providerName,
            memoryMB: this.metrics.memoryStart,
            cachedTiles: cacheStats.tileCount
        });
    }
    
    startTileFailureMonitoring(onTooManyFailures) {
        // Monitor tile load failures and trigger fallback if needed
        const checkFailureThreshold = () => {
            const failureRate = this.metrics.tilesRequested > 0 ? 
                (this.metrics.tilesFailed / this.metrics.tilesRequested) : 0;
            
            // If more than 50% of tiles fail and we've tried at least 10 tiles
            if (failureRate > 0.5 && this.metrics.tilesRequested >= 10) {
                cesiumLog.error(`[PERF] High tile failure rate detected: ${(failureRate * 100).toFixed(1)}% (${this.metrics.tilesFailed}/${this.metrics.tilesRequested})`);
                
                if (onTooManyFailures) {
                    onTooManyFailures(this.metrics.providerSwitchName, failureRate);
                }
                return true; // Stop monitoring
            }
            
            // Continue monitoring for up to 30 seconds
            const elapsed = performance.now() - this.metrics.providerSwitchStart;
            if (elapsed < 30000) {
                setTimeout(checkFailureThreshold, 2000); // Check every 2 seconds
            }
            
            return false;
        };
        
        // Start monitoring after a brief delay to allow initial tiles to load
        setTimeout(checkFailureThreshold, 3000);
    }
    
    endProviderSwitch() {
        if (!this.isMonitoring || !this.metrics.providerSwitchStart) return;
        
        const duration = performance.now() - this.metrics.providerSwitchStart;
        const memoryEnd = this._getMemoryUsage();
        const memoryDelta = memoryEnd - this.metrics.memoryStart;
        const cacheStats = this._getCacheStats();
        const avgFrameRate = this._calculateAverageFrameRate();
        
        cesiumLog.info(`[PERF] Provider Switch Complete: ${this.metrics.providerSwitchName}`);
        cesiumLog.info(`[PERF] Total Time: ${duration.toFixed(0)}ms`);
        cesiumLog.info(`[PERF] Tiles: ${this.metrics.tilesLoaded} loaded, ${this.metrics.tilesFailed} failed`);
        cesiumLog.info(`[PERF] Frame Drops: ${this.metrics.frameDrops}, Avg FPS: ${avgFrameRate.toFixed(1)}`);
        cesiumLog.info(`[PERF] Memory Delta: ${memoryDelta > 0 ? '+' : ''}${memoryDelta.toFixed(1)}MB`);
        cesiumLog.info(`[PERF] Post-switch: Tiles cached: ${cacheStats.tileCount}`);
        
        // Stop monitoring
        this.isMonitoring = false;
        this._stopFrameRateMonitoring();
        this._stopTileMonitoring();
        
        // Report comprehensive metrics to Flutter
        this._reportMetrics({
            event: 'providerSwitchComplete',
            provider: this.metrics.providerSwitchName,
            durationMs: duration,
            tilesLoaded: this.metrics.tilesLoaded,
            tilesFailed: this.metrics.tilesFailed,
            frameDrops: this.metrics.frameDrops,
            avgFrameRate: avgFrameRate,
            memoryDeltaMB: memoryDelta,
            finalCachedTiles: cacheStats.tileCount,
            networkRequests: this.metrics.networkRequests
        });
        
        // Reset for next measurement
        this.metrics.providerSwitchStart = null;
        this.currentProvider = this.metrics.providerSwitchName;
    }
    
    _startFrameRateMonitoring() {
        let frameCount = 0;
        let lastTime = performance.now();
        
        const monitorFrame = (currentTime) => {
            if (!this.isMonitoring) return;
            
            frameCount++;
            const deltaTime = currentTime - lastTime;
            
            // Calculate FPS every 100ms
            if (deltaTime >= 100) {
                const fps = (frameCount * 1000) / deltaTime;
                this.frameRateHistory.push(fps);
                
                // Detect frame drops (< 30 FPS is considered a drop)
                if (fps < 30) {
                    this.metrics.frameDrops++;
                }
                
                // Log severe drops
                if (fps < 10) {
                    cesiumLog.warn(`[PERF] Severe frame drop detected: ${fps.toFixed(1)} FPS`);
                }
                
                frameCount = 0;
                lastTime = currentTime;
                
                // Report periodic updates
                if (this.frameRateHistory.length % 10 === 0) {
                    const elapsed = performance.now() - this.metrics.providerSwitchStart;
                    cesiumLog.info(`[PERF] T+${elapsed.toFixed(0)}ms: FPS: ${fps.toFixed(1)}, Tiles: ${this.metrics.tilesLoaded}/${this.metrics.tilesRequested}`);
                }
            }
            
            requestAnimationFrame(monitorFrame);
        };
        
        requestAnimationFrame(monitorFrame);
    }
    
    _stopFrameRateMonitoring() {
        // Frame rate monitoring stops automatically when isMonitoring = false
    }
    
    _startTileMonitoring() {
        if (!this.viewer?.scene?.globe?.imageryLayers) return;
        
        // Hook into globe tile loading events
        const globe = this.viewer.scene.globe;
        
        // Monitor tile load progress
        this.tileLoadProgressListener = (queuedTileCount) => {
            if (!this.isMonitoring) return;
            
            const elapsed = performance.now() - this.metrics.providerSwitchStart;
            
            if (queuedTileCount > 0) {
                cesiumLog.debug(`[PERF] T+${elapsed.toFixed(0)}ms: ${queuedTileCount} tiles queued`);
            }
        };
        
        globe.tileLoadProgressEvent.addEventListener(this.tileLoadProgressListener);
        
        // Try to hook into imagery layer events if available
        try {
            if (globe.imageryLayers.length > 0) {
                const layer = globe.imageryLayers.get(0);
                if (layer.imageryProvider) {
                    this._hookImageryProviderEvents(layer.imageryProvider);
                }
            }
        } catch (e) {
            cesiumLog.debug(`[PERF] Could not hook imagery provider events: ${e.message}`);
        }
    }
    
    _stopTileMonitoring() {
        if (this.tileLoadProgressListener && this.viewer?.scene?.globe) {
            this.viewer.scene.globe.tileLoadProgressEvent.removeEventListener(this.tileLoadProgressListener);
        }
        
        // Clean up any hooked events
        this.tileLoadListeners.forEach(cleanup => {
            try { cleanup(); } catch (e) { /* ignore */ }
        });
        this.tileLoadListeners = [];
    }
    
    _hookImageryProviderEvents(provider) {
        // This is provider-specific and may not always be available
        // We'll do our best to monitor what we can
        
        if (provider.requestImage) {
            const originalRequestImage = provider.requestImage.bind(provider);
            provider.requestImage = (...args) => {
                if (this.isMonitoring) {
                    this.metrics.tilesRequested++;
                    this.metrics.networkRequests++;
                }
                
                const result = originalRequestImage(...args);
                
                if (result && typeof result.then === 'function') {
                    result.then(() => {
                        if (this.isMonitoring) {
                            this.metrics.tilesLoaded++;
                        }
                    }).catch(() => {
                        if (this.isMonitoring) {
                            this.metrics.tilesFailed++;
                        }
                    });
                }
                
                return result;
            };
            
            // Store cleanup function
            this.tileLoadListeners.push(() => {
                provider.requestImage = originalRequestImage;
            });
        }
    }
    
    _calculateAverageFrameRate() {
        if (this.frameRateHistory.length === 0) return 0;
        const sum = this.frameRateHistory.reduce((a, b) => a + b, 0);
        return sum / this.frameRateHistory.length;
    }
    
    _getMemoryUsage() {
        if (window.performance?.memory) {
            return Math.round(window.performance.memory.usedJSHeapSize / (1024 * 1024));
        }
        return 0;
    }
    
    _getCacheStats() {
        const globe = this.viewer?.scene?.globe;
        if (!globe) return { tileCount: 0 };
        
        return {
            tileCount: globe.tileCacheSize || 0
        };
    }
    
    _reportMetrics(data) {
        // Send to Flutter with detailed metrics
        if (window.flutter_inappwebview?.callHandler) {
            window.flutter_inappwebview.callHandler('cesiumPerformanceMetrics', data);
        }
        
        // Also use the general performance reporter
        if (data.event === 'providerSwitchComplete') {
            PerformanceReporter.report('providerSwitch', data.durationMs);
        }
    }
    
    // Public method to manually report current state
    reportCurrentState() {
        if (!this.isMonitoring) return;
        
        const elapsed = performance.now() - this.metrics.providerSwitchStart;
        const currentMemory = this._getMemoryUsage();
        const cacheStats = this._getCacheStats();
        
        cesiumLog.info(`[PERF] Current State - T+${elapsed.toFixed(0)}ms`);
        cesiumLog.info(`[PERF] Memory: ${currentMemory}MB, Tiles: ${this.metrics.tilesLoaded}/${this.metrics.tilesRequested}, Drops: ${this.metrics.frameDrops}`);
        
        return {
            elapsed: elapsed,
            memory: currentMemory,
            tilesLoaded: this.metrics.tilesLoaded,
            tilesRequested: this.metrics.tilesRequested,
            frameDrops: this.metrics.frameDrops,
            cachedTiles: cacheStats.tileCount
        };
    }
}

// ============================================================================
// Flight Data Source - Idiomatic Cesium CustomDataSource
// ============================================================================

class FlightDataSource extends Cesium.CustomDataSource {
    constructor(name, igcPoints, viewer) {
        super(name);
        
        // Store raw data and viewer reference
        this.igcPoints = igcPoints;
        this.viewer = viewer;
        this.positions = [];
        this.times = [];
        this.timezone = igcPoints[0]?.timezone || '+00:00';
        this.timezoneOffsetSeconds = this._parseTimezoneOffset(this.timezone);
        
        // Store original GPS altitudes for reverting terrain correction
        this.originalAltitudes = [];
        
        // Altitude correction data
        this.correctedAltitudes = [];
        this.altitudeCorrectionApplied = false;
        
        // Terrain state tracking - detect actual terrain state from viewer
        this._terrainEnabled = this._detectInitialTerrainState();
        
        // Process data - this will be async if terrain correction is applied
        this._initializeFlightData();
    }
    
    _detectInitialTerrainState() {
        // Check if viewer has actual terrain provider (not just ellipsoid)
        const viewerTerrainProvider = this.viewer?.terrainProvider;
        const globeTerrainProvider = this.viewer?.scene?.globe?.terrainProvider;
        
        // Use the globe terrain provider as it's the actual active one
        const activeTerrainProvider = globeTerrainProvider || viewerTerrainProvider;
        
        if (activeTerrainProvider) {
            const providerName = activeTerrainProvider.constructor.name;
            const isReady = activeTerrainProvider.ready;
            // Use capability-based detection instead of class name (minification-safe)
            const hasTerrainCapability = typeof activeTerrainProvider.requestTileGeometry === 'function';
            const isEllipsoid = providerName === 'EllipsoidTerrainProvider';
            const isTerrain = hasTerrainCapability && !isEllipsoid;
            
            cesiumLog.info(`FlightDataSource: Terrain check - provider: ${providerName}, ready: ${isReady}, isTerrain: ${isTerrain}`);
            
            if (isReady && isTerrain) {
                cesiumLog.info(`FlightDataSource: Detected terrain is enabled - provider: ${providerName}`);
                return true;
            } else if (isReady && providerName === 'EllipsoidTerrainProvider') {
                cesiumLog.info('FlightDataSource: Detected terrain is disabled - using ellipsoid terrain');
                return false;
            } else {
                // Provider exists but not ready yet - this shouldn't happen if we waited properly
                cesiumLog.warn(`FlightDataSource: Terrain provider not ready - provider: ${providerName}, ready: ${isReady}`);
                return isTerrain; // Return true if it's a terrain provider, even if not ready
            }
        } else {
            cesiumLog.info('FlightDataSource: No terrain provider found');
            return false;
        }
    }
    
    _parseTimezoneOffset(timezone) {
        const match = timezone.match(/^([+-])(\d{2}):(\d{2})$/);
        if (!match) return 0;
        
        const sign = match[1] === '+' ? 1 : -1;
        const hours = parseInt(match[2], 10);
        const minutes = parseInt(match[3], 10);
        return sign * ((hours * 3600) + (minutes * 60));
    }
    
    async _initializeFlightData() {
        // First, process basic flight data
        this._processBasicFlightData();
        
        // Store original GPS altitudes for later use
        this._storeOriginalAltitudes();
        
        // Start with GPS altitudes
        this._updatePositionsWithOriginalAltitudes();
        
        // Apply initial terrain correction if terrain is enabled
        if (this._terrainEnabled) {
            cesiumLog.info('FlightDataSource: Terrain detected during initialization - applying terrain correction');
            // Add delay to ensure terrain provider is fully ready
            setTimeout(async () => {
                const correctionApplied = await this.applyTerrainCorrection();
                if (!correctionApplied) {
                    cesiumLog.warn('FlightDataSource: Initial terrain correction failed - terrain may not be ready yet');
                }
            }, 1500); // Longer delay for terrain provider readiness
        } else {
            cesiumLog.info('FlightDataSource: No terrain detected - using original GPS altitudes');
        }
        
        // Create entities after positions are finalized
        this._createCurtainWall();
        this._createPilotEntity();
        
        // Initialize terrain button state after DOM is ready
        setTimeout(() => this._initializeTerrainButtonState(), 100);
    }
    
    async _correctAltitudesForTerrain() {
        // Enhanced debugging for terrain provider state - check both viewer and globe terrain providers
        const viewerTerrainProvider = this.viewer?.terrainProvider;
        const globeTerrainProvider = this.viewer?.scene?.globe?.terrainProvider;
        
        cesiumLog.info(`Terrain correction check - viewer: ${!!this.viewer}, viewerTerrainProvider: ${!!viewerTerrainProvider}, globeTerrainProvider: ${!!globeTerrainProvider}, points: ${this.igcPoints.length}`);
        
        // Use the globe terrain provider as it's the actual active one
        const activeTerrainProvider = globeTerrainProvider || viewerTerrainProvider;
        
        if (activeTerrainProvider) {
            cesiumLog.info(`Terrain provider type: ${activeTerrainProvider.constructor.name}`);
            cesiumLog.info(`Terrain provider ready: ${activeTerrainProvider.ready}`);
            cesiumLog.info(`Terrain provider is ellipsoid: ${activeTerrainProvider.constructor.name === 'EllipsoidTerrainProvider'}`);
        }
        
        // Check if we have a real terrain provider (not just ellipsoid) and sufficient points
        if (!activeTerrainProvider || activeTerrainProvider.constructor.name === 'EllipsoidTerrainProvider' || this.igcPoints.length < 2) {
            cesiumLog.info('Skipping terrain correction: no terrain provider or insufficient points');
            return;
        }
        
        // Need to consider the case when the vario is turn on in flight, i.e, velocity is zero
        const launchPoint = this.igcPoints[0];
        const landingPoint = this.igcPoints[this.igcPoints.length - 1];
        
        // Create Cartographic positions for launch and landing
        const positions = [
            Cesium.Cartographic.fromDegrees(launchPoint.longitude, launchPoint.latitude),
            Cesium.Cartographic.fromDegrees(landingPoint.longitude, landingPoint.latitude)
        ];
        
        cesiumLog.info('Sampling terrain at launch and landing points...');
        const sampledPositions = await Cesium.sampleTerrainMostDetailed(
            activeTerrainProvider, 
            positions
        );
        
        const launchTerrainHeight = sampledPositions[0].height;
        const landingTerrainHeight = sampledPositions[1].height;
        
        if (launchTerrainHeight === undefined || landingTerrainHeight === undefined) {
            throw new Error('Failed to sample terrain heights');
        }
        
        const launchGPSAltitude = launchPoint.gpsAltitude || launchPoint.altitude;
        const landingGPSAltitude = landingPoint.gpsAltitude || landingPoint.altitude;
        

        const slope = (launchTerrainHeight- landingTerrainHeight)/(launchGPSAltitude - landingGPSAltitude)
        const intercept = launchTerrainHeight - slope*launchGPSAltitude
        cesiumLog.info(`Slope: ${slope}, intercept: ${intercept}`)
        
        // Apply altitude-based linear interpolation to all points
        this.correctedAltitudes = new Array(this.igcPoints.length);
        
        for (let i = 0; i < this.igcPoints.length; i++) {
            const point = this.igcPoints[i];
            const gpsAltitude = point.gpsAltitude || point.altitude;
            
            this.correctedAltitudes[i] = slope * gpsAltitude + intercept;
        }
        
        this.altitudeCorrectionApplied = true;
        cesiumLog.info('Altitude correction applied successfully');
    }
    
    _processBasicFlightData() {
        const processStart = performance.now();
        
        // Build time array
        this.times = new Array(this.igcPoints.length);
        
        for (let i = 0; i < this.igcPoints.length; i++) {
            const point = this.igcPoints[i];
            this.times[i] = Cesium.JulianDate.fromIso8601(point.timestamp);
        }
        
        // Calculate time bounds
        this.startTime = this.times[0];
        this.stopTime = this.times[this.times.length - 1];
        this.totalDuration = Cesium.JulianDate.secondsDifference(this.stopTime, this.startTime);
        
        PerformanceReporter.report('basicDataProcessing', performance.now() - processStart);
    }
    
    _updatePositionsWithCorrectedAltitudes() {
        const processStart = performance.now();
        
        // Build positions array using corrected altitudes if available
        this.positions = new Array(this.igcPoints.length);
        
        for (let i = 0; i < this.igcPoints.length; i++) {
            const point = this.igcPoints[i];
            const altitude = this.altitudeCorrectionApplied ? 
                this.correctedAltitudes[i] : 
                (point.gpsAltitude || point.altitude);
                
            this.positions[i] = Cesium.Cartesian3.fromDegrees(
                point.longitude, 
                point.latitude, 
                altitude
            );
        }
        
        // Calculate bounding sphere for camera operations
        this.boundingSphere = Cesium.BoundingSphere.fromPoints(this.positions);
        
        PerformanceReporter.report('positionProcessing', performance.now() - processStart);
    }
    
    _storeOriginalAltitudes() {
        // Store original GPS altitudes for terrain correction reverting
        this.originalAltitudes = new Array(this.igcPoints.length);
        
        for (let i = 0; i < this.igcPoints.length; i++) {
            const point = this.igcPoints[i];
            this.originalAltitudes[i] = point.gpsAltitude || point.altitude;
        }
        
        cesiumLog.info(`Stored ${this.originalAltitudes.length} original GPS altitudes`);
    }
    
    _updatePositionsWithOriginalAltitudes() {
        const processStart = performance.now();
        
        // Build positions array using original GPS altitudes
        this.positions = new Array(this.igcPoints.length);
        
        for (let i = 0; i < this.igcPoints.length; i++) {
            const point = this.igcPoints[i];
            const altitude = this.originalAltitudes[i];
                
            this.positions[i] = Cesium.Cartesian3.fromDegrees(
                point.longitude, 
                point.latitude, 
                altitude
            );
        }
        
        // Calculate bounding sphere for camera operations
        this.boundingSphere = Cesium.BoundingSphere.fromPoints(this.positions);
        
        PerformanceReporter.report('originalPositionProcessing', performance.now() - processStart);
        cesiumLog.info('Updated positions with original GPS altitudes');
    }
    
    async applyTerrainCorrection() {
        // Dynamic terrain correction - can be called anytime when terrain is available
        cesiumLog.info('Applying terrain correction dynamically...');
        
        // Enhanced debugging for terrain provider state
        const viewerTerrainProvider = this.viewer?.terrainProvider;
        const globeTerrainProvider = this.viewer?.scene?.globe?.terrainProvider;
        
        cesiumLog.info(`Terrain correction check - viewer: ${!!this.viewer}, viewerTerrainProvider: ${!!viewerTerrainProvider}, globeTerrainProvider: ${!!globeTerrainProvider}, points: ${this.igcPoints.length}`);
        
        // Use the globe terrain provider as it's the actual active one
        const activeTerrainProvider = globeTerrainProvider || viewerTerrainProvider;
        
        if (activeTerrainProvider) {
            cesiumLog.info(`Terrain provider type: ${activeTerrainProvider.constructor.name}`);
            cesiumLog.info(`Terrain provider ready: ${activeTerrainProvider.ready}`);
        }
        
        // Check if we have a real terrain provider (not just ellipsoid) and sufficient points
        if (!activeTerrainProvider || activeTerrainProvider.constructor.name === 'EllipsoidTerrainProvider' || this.igcPoints.length < 2) {
            cesiumLog.info('Cannot apply terrain correction: no terrain provider or insufficient points');
            return false;
        }
        
        try {
            // Get launch and landing points
            const launchPoint = this.igcPoints[0];
            const landingPoint = this.igcPoints[this.igcPoints.length - 1];
            
            // Create Cartographic positions for launch and landing
            const positions = [
                Cesium.Cartographic.fromDegrees(launchPoint.longitude, launchPoint.latitude),
                Cesium.Cartographic.fromDegrees(landingPoint.longitude, landingPoint.latitude)
            ];
            
            cesiumLog.info('Sampling terrain at launch and landing points...');
            const sampledPositions = await Cesium.sampleTerrainMostDetailed(
                activeTerrainProvider, 
                positions
            );
            
            const launchTerrainHeight = sampledPositions[0].height;
            const landingTerrainHeight = sampledPositions[1].height;
            
            if (launchTerrainHeight === undefined || landingTerrainHeight === undefined) {
                throw new Error('Failed to sample terrain heights');
            }
            
            const launchGPSAltitude = this.originalAltitudes[0];
            const landingGPSAltitude = this.originalAltitudes[this.originalAltitudes.length - 1];
            
            const slope = (launchTerrainHeight - landingTerrainHeight) / (launchGPSAltitude - landingGPSAltitude);
            const intercept = launchTerrainHeight - slope * launchGPSAltitude;
            
            cesiumLog.info(`Slope: ${slope}, intercept: ${intercept}`);
            
            // Calculate corrected altitudes for all points
            this.correctedAltitudes = new Array(this.igcPoints.length);
            
            for (let i = 0; i < this.igcPoints.length; i++) {
                const gpsAltitude = this.originalAltitudes[i];
                this.correctedAltitudes[i] = slope * gpsAltitude + intercept;
            }
            
            // Update positions with corrected altitudes
            this._updatePositionsWithCorrectedAltitudes();
            
            // Update entities with new positions
            this._updateEntitiesWithNewPositions();
            
            this.altitudeCorrectionApplied = true;
            cesiumLog.info('Terrain correction applied successfully');
            return true;
            
        } catch (error) {
            cesiumLog.error(`Failed to apply terrain correction: ${error.message}`);
            return false;
        }
    }
    
    removeTerrainCorrection() {
        // Revert to original GPS altitudes
        cesiumLog.info('Removing terrain correction - reverting to GPS altitudes...');
        
        // Safety check - ensure we have the necessary data
        if (!this.originalGPSAltitudes || this.originalGPSAltitudes.length === 0) {
            cesiumLog.warn('No original GPS altitudes available - terrain correction removal skipped');
            return;
        }
        
        // Update positions with original GPS altitudes
        this._updatePositionsWithOriginalAltitudes();
        
        // Update entities with new positions
        this._updateEntitiesWithNewPositions();
        
        // Clear correction data
        this.correctedAltitudes = [];
        this.altitudeCorrectionApplied = false;
        
        cesiumLog.info('Terrain correction removed - using original GPS altitudes');
    }
    
    _updateEntitiesWithNewPositions() {
        // Update the pilot entity with new positions
        if (this.pilotEntity && this.pilotEntity.position instanceof Cesium.SampledPositionProperty) {
            // Validate data before creating new property
            if (!this.times || !this.positions || this.times.length === 0 || this.positions.length === 0) {
                cesiumLog.warn('Cannot update entities: missing or empty times/positions data');
                return;
            }
            
            // Create a new SampledPositionProperty with corrected positions
            const newPositionProperty = new Cesium.SampledPositionProperty();
            newPositionProperty.setInterpolationOptions({
                interpolationDegree: 1,  // Linear for velocity calculation
                interpolationAlgorithm: Cesium.LinearApproximation
            });
            newPositionProperty.forwardExtrapolationType = Cesium.ExtrapolationType.HOLD;
            newPositionProperty.backwardExtrapolationType = Cesium.ExtrapolationType.HOLD;
            
            // Add corrected samples
            newPositionProperty.addSamples(this.times, this.positions);
            
            // Replace the position property
            this.pilotEntity.position = newPositionProperty;
            
            // Update orientation to use the new position property (add safety check)
            if (newPositionProperty) {
                this.pilotEntity.orientation = new Cesium.VelocityOrientationProperty(newPositionProperty);
            }
        }
        
        // Update curtain wall if it exists
        if (this.curtainWallEntity && this.curtainWallEntity.wall) {
            this.curtainWallEntity.wall.positions = new Cesium.ConstantProperty(this.positions);
        }
        
        cesiumLog.debug('Updated entities with new positions');
    }
    
    _createPilotEntity() {
        // Create position property with bulk add
        const positionProperty = new Cesium.SampledPositionProperty();
        positionProperty.setInterpolationOptions({
            interpolationDegree: 1,  // Linear for velocity calculation
            interpolationAlgorithm: Cesium.LinearApproximation
        });
        positionProperty.forwardExtrapolationType = Cesium.ExtrapolationType.HOLD;
        positionProperty.backwardExtrapolationType = Cesium.ExtrapolationType.HOLD;
        
        // Add all samples at once
        const bulkAddStart = performance.now();
        positionProperty.addSamples(this.times, this.positions);
        PerformanceReporter.report('bulkPositionAdd', performance.now() - bulkAddStart);
        
        // Store position property for reuse
        this.positionProperty = positionProperty;
        
        // Create pilot entity
        this.pilotEntity = this.entities.add({
            id: 'pilot',
            name: 'Pilot',
            availability: new Cesium.TimeIntervalCollection([
                new Cesium.TimeInterval({
                    start: this.startTime,
                    stop: this.stopTime
                })
            ]),
            position: positionProperty,
            orientation: new Cesium.VelocityOrientationProperty(positionProperty),
            point: {
                pixelSize: 16,
                color: Cesium.Color.YELLOW,
                outlineColor: Cesium.Color.BLACK,
                outlineWidth: 3,
                heightReference: Cesium.HeightReference.NONE,
                disableDepthTestDistance: Number.POSITIVE_INFINITY,
                scaleByDistance: new Cesium.NearFarScalar(1000, 1.5, 100000, 0.5)
            },
            viewFrom: new Cesium.Cartesian3(0.0, -1000.0, 500.0)
        });
    }
    
    _createCurtainWall() {
        // Get altitudes for the wall - use corrected altitudes if available
        const wallAltitudes = this.altitudeCorrectionApplied ? 
            this.correctedAltitudes : 
            this.igcPoints.map(p => p.gpsAltitude || p.altitude);
            
        // Static curtain wall
        this.staticCurtainEntity = this.entities.add({
            id: 'static-curtain',
            name: 'Flight Track Curtain',
            show: true,
            wall: {
                positions: this.positions,
                maximumHeights: wallAltitudes,
                material: Cesium.Color.DODGERBLUE.withAlpha(0.2),
                outline: false
            }
        });
        
        // Dynamic curtain wall for ribbon mode
        this.dynamicCurtainEntity = this.entities.add({
            id: 'dynamic-curtain',
            name: 'Dynamic Flight Curtain',
            show: false,
            wall: {
                positions: new Cesium.CallbackProperty((time) => {
                    if (!this._ribbonEnabled) return [];
                    return this._getTrailPositions(time);
                }, false),
                maximumHeights: new Cesium.CallbackProperty((time) => {
                    if (!this._ribbonEnabled) return [];
                    return this._getTrailAltitudes(time);
                }, false),
                material: Cesium.Color.DODGERBLUE.withAlpha(0.2),
                outline: false
            }
        });
        
        this._ribbonEnabled = false;
        this._ribbonSeconds = 3.0;
    }
    
    enableRibbonMode(enabled) {
        this._ribbonEnabled = enabled;
        this.staticCurtainEntity.show = !enabled;
        this.dynamicCurtainEntity.show = enabled;
    }
    
    _getTrailPositions(currentTime) {
        const index = this._findTimeIndex(currentTime);
        if (index < 0) return [];
        
        const windowSize = this._calculateRibbonWindow();
        const startIdx = Math.max(0, index - windowSize + 1);
        return this.positions.slice(startIdx, index + 1);
    }
    
    _getTrailAltitudes(currentTime) {
        const index = this._findTimeIndex(currentTime);
        if (index < 0) return [];
        
        const windowSize = this._calculateRibbonWindow();
        const startIdx = Math.max(0, index - windowSize + 1);
        
        // Use corrected altitudes if available
        if (this.altitudeCorrectionApplied) {
            return this.correctedAltitudes.slice(startIdx, index + 1);
        } else {
            return this.igcPoints.slice(startIdx, index + 1).map(p => p.gpsAltitude || p.altitude);
        }
    }
    
    _calculateRibbonWindow() {
        const viewer = cesiumApp?.viewer;
        if (!viewer) return 100;
        
        const speedMultiplier = viewer.clock.multiplier || 1;
        const flightSeconds = this._ribbonSeconds * speedMultiplier;
        const pointsPerSecond = this.igcPoints.length / this.totalDuration;
        return Math.ceil(flightSeconds * pointsPerSecond);
    }
    
    _findTimeIndex(time) {
        // Binary search for efficiency
        let left = 0;
        let right = this.times.length - 1;
        
        while (left <= right) {
            const mid = Math.floor((left + right) / 2);
            const cmp = Cesium.JulianDate.compare(this.times[mid], time);
            
            if (cmp < 0) left = mid + 1;
            else if (cmp > 0) right = mid - 1;
            else return mid;
        }
        
        return Math.max(0, left - 1);
    }
    
    getStatisticsAt(time) {
        const index = this._findTimeIndex(time);
        if (index < 0 || index >= this.igcPoints.length) return null;
        
        const point = this.igcPoints[index];
        
        // Calculate speed if not provided
        let speed = point.groundSpeed || 0;
        if (!speed && index > 0) {
            const distance = Cesium.Cartesian3.distance(
                this.positions[index - 1],
                this.positions[index]
            );
            const timeDiff = Cesium.JulianDate.secondsDifference(
                this.times[index],
                this.times[index - 1]
            );
            if (timeDiff > 0) {
                speed = (distance / timeDiff) * 3.6; // m/s to km/h
            }
        }
        
        // Use corrected altitude for display if available, otherwise original GPS altitude
        const displayAltitude = this.altitudeCorrectionApplied ? 
            this.correctedAltitudes[index] : 
            (point.gpsAltitude || point.altitude || 0);
        
        return {
            altitude: displayAltitude,
            climbRate: point.climbRate || 0,
            speed: speed,
            time: this.times[index],
            localTime: this._toLocalTime(this.times[index]),
            elapsedSeconds: Cesium.JulianDate.secondsDifference(this.times[index], this.startTime)
        };
    }
    
    _toLocalTime(julianDate) {
        if (this.timezoneOffsetSeconds === 0) return julianDate;
        return Cesium.JulianDate.addSeconds(
            julianDate, 
            this.timezoneOffsetSeconds, 
            new Cesium.JulianDate()
        );
    }
    
    _initializeTerrainButtonState() {
        // Wait for button to exist in DOM with retry logic
        const checkButton = () => {
            const button = document.getElementById('terrainButton');
            if (button && this.viewer?.scene?.globe) {
                // Check if terrain is enabled (not undefined or ellipsoid)
                const terrainProvider = this.viewer.terrainProvider;
                const isTerrainEnabled = terrainProvider && 
                    terrainProvider.constructor.name !== 'EllipsoidTerrainProvider';
                
                // Update tracked state
                this._terrainEnabled = isTerrainEnabled;
                
                if (isTerrainEnabled) {
                    button.classList.add('active');
                    cesiumLog.debug('Terrain button initialized - terrain is enabled');
                } else {
                    button.classList.remove('active');
                    cesiumLog.debug('Terrain button initialized - terrain is disabled');
                }
            } else {
                // Retry if button or viewer not ready
                setTimeout(checkButton, 50);
            }
        };
        checkButton();
    }
    
    async toggleTerrain() {
        if (!this.viewer) {
            cesiumLog.warn('toggleTerrain: No viewer available');
            return;
        }
        
        const button = document.getElementById('terrainButton');
        cesiumLog.info(`toggleTerrain: Current terrain state: ${this._terrainEnabled}`);
        
        if (this._terrainEnabled) {
            // Disable terrain - use ellipsoid terrain provider instead of undefined
            cesiumLog.info('toggleTerrain: Attempting to disable terrain...');
            try {
                // Use ellipsoid terrain provider for clean disable
                this.viewer.scene.setTerrain(new Cesium.EllipsoidTerrainProvider());
                this._terrainEnabled = false;
                cesiumLog.info('Terrain disabled successfully');
                
                // Update button state
                if (button) {
                    button.classList.remove('active');
                }
                
                // Remove terrain correction and revert to GPS altitudes
                if (this.flightDataSource) {
                    this.flightDataSource.removeTerrainCorrection();
                } else {
                    cesiumLog.warn('No flight data source available for terrain correction removal');
                }
                
            } catch (error) {
                cesiumLog.error(`Failed to disable terrain: ${error.message}`);
                // Reset state on error - don't leave in inconsistent state
                this._terrainEnabled = this._detectInitialTerrainState();
                if (button) {
                    if (this._terrainEnabled) {
                        button.classList.add('active');
                    } else {
                        button.classList.remove('active');
                    }
                }
            }
        } else {
            // Enable Cesium World Terrain
            cesiumLog.info('toggleTerrain: Attempting to enable terrain...');
            try {
                this.viewer.scene.setTerrain(
                    Cesium.Terrain.fromWorldTerrain({
                        requestWaterMask: false,
                        requestVertexNormals: true
                    })
                );
                this._terrainEnabled = true;
                cesiumLog.info('Cesium World Terrain enabled successfully (asset ID 1)');
                
                // Update button state
                if (button) {
                    button.classList.add('active');
                }
                
                // Apply terrain correction with a delay to ensure terrain is ready
                setTimeout(async () => {
                    const correctionApplied = await this.applyTerrainCorrection();
                    if (!correctionApplied) {
                        cesiumLog.warn('Terrain correction could not be applied - terrain may not be ready');
                    }
                }, 1500);
                
            } catch (error) {
                cesiumLog.error(`Failed to enable Cesium World Terrain: ${error.message}`);
                cesiumLog.info('Terrain requires a valid Cesium Ion token with asset access');
                
                // Reset state on error
                this._terrainEnabled = false;
                if (button) {
                    button.classList.remove('active');
                }
            }
        }
        
        // Final state sync check
        setTimeout(() => {
            const actualTerrainState = this._detectInitialTerrainState();
            if (actualTerrainState !== this._terrainEnabled) {
                cesiumLog.warn(`toggleTerrain: State mismatch detected - correcting (actual: ${actualTerrainState}, tracked: ${this._terrainEnabled})`);
                this._terrainEnabled = actualTerrainState;
                if (button) {
                    if (this._terrainEnabled) {
                        button.classList.add('active');
                    } else {
                        button.classList.remove('active');
                    }
                }
            }
        }, 500);
    }
}

// ============================================================================
// Track Primitive Collection - Manages colored track primitives
// ============================================================================

class TrackPrimitiveCollection {
    constructor(viewer, flightData) {
        this.viewer = viewer;
        this.flightData = flightData;
        this.staticPrimitive = null;
        this.dynamicPrimitive = null;
        this._ribbonEnabled = false;
        this._lastDynamicWindow = { start: -1, end: -1 };
        
        // Create static track immediately
        this._createStaticTrack();
    }
    
    _createStaticTrack() {
        const start = performance.now();
        
        const positions = this.flightData.positions;
        const colors = this._generateColors(0, positions.length - 1);
        
        if (positions.length < 2) return;
        
        this.staticPrimitive = this.viewer.scene.primitives.add(
            new Cesium.Primitive({
                geometryInstances: new Cesium.GeometryInstance({
                    geometry: new Cesium.PolylineGeometry({
                        positions: positions,
                        width: 3.0,
                        vertexFormat: Cesium.PolylineColorAppearance.VERTEX_FORMAT,
                        colors: colors,
                        colorsPerVertex: true
                    })
                }),
                appearance: new Cesium.PolylineColorAppearance({
                    translucent: true
                }),
                asynchronous: false
            })
        );
        
        PerformanceReporter.report('staticTrackCreation', performance.now() - start);
    }
    
    _generateColors(startIdx, endIdx) {
        const colors = new Array(endIdx - startIdx + 1);
        const points = this.flightData.igcPoints;
        
        for (let i = startIdx; i <= endIdx; i++) {
            const climbRate = points[i].climbRate15s || points[i].climbRate || 0;
            colors[i - startIdx] = this._getClimbRateColor(climbRate).withAlpha(0.9);
        }
        
        return colors;
    }
    
    _getClimbRateColor(rate) {
        if (rate >= 0) return Cesium.Color.GREEN;
        if (rate > -1.5) return Cesium.Color.DODGERBLUE;
        return Cesium.Color.RED;
    }
    
    enableRibbonMode(enabled) {
        this._ribbonEnabled = enabled;
        this.staticPrimitive.show = !enabled;
        
        if (!enabled && this.dynamicPrimitive) {
            this.viewer.scene.primitives.remove(this.dynamicPrimitive);
            this.dynamicPrimitive = null;
            this._lastDynamicWindow = { start: -1, end: -1 };
        }
    }
    
    updateDynamicTrack(currentTime) {
        if (!this._ribbonEnabled) return;
        
        const currentIdx = this.flightData._findTimeIndex(currentTime);
        if (currentIdx < 0) return;
        
        const windowSize = this.flightData._calculateRibbonWindow();
        const startIdx = Math.max(0, currentIdx - windowSize + 1);
        
        // Skip if window hasn't changed
        if (startIdx === this._lastDynamicWindow.start && 
            currentIdx === this._lastDynamicWindow.end) {
            return;
        }
        
        // Create new primitive
        const positions = this.flightData.positions.slice(startIdx, currentIdx + 1);
        const colors = this._generateColors(startIdx, currentIdx);
        
        if (positions.length < 2) return;
        
        const newPrimitive = this.viewer.scene.primitives.add(
            new Cesium.Primitive({
                geometryInstances: new Cesium.GeometryInstance({
                    geometry: new Cesium.PolylineGeometry({
                        positions: positions,
                        width: 3.0,
                        vertexFormat: Cesium.PolylineColorAppearance.VERTEX_FORMAT,
                        colors: colors,
                        colorsPerVertex: true
                    })
                }),
                appearance: new Cesium.PolylineColorAppearance({
                    translucent: true
                }),
                asynchronous: false
            })
        );
        
        // Remove old primitive after adding new one (double buffering)
        if (this.dynamicPrimitive) {
            this.viewer.scene.primitives.remove(this.dynamicPrimitive);
        }
        
        this.dynamicPrimitive = newPrimitive;
        this._lastDynamicWindow = { start: startIdx, end: currentIdx };
    }
    
    destroy() {
        if (this.staticPrimitive) {
            this.viewer.scene.primitives.remove(this.staticPrimitive);
        }
        if (this.dynamicPrimitive) {
            this.viewer.scene.primitives.remove(this.dynamicPrimitive);
        }
    }
}

// ============================================================================
// Statistics Display Manager
// ============================================================================

class StatisticsDisplay {
    constructor(flightData) {
        this.flightData = flightData;
        this.container = document.getElementById('statsContainer');
    }
    
    initialize() {
        if (this.container) {
            this.container.innerHTML = '<span>Initializing...</span>';
        }
    }
    
    update(time) {
        if (!this.container) return;
        
        const stats = this.flightData.getStatisticsAt(time);
        if (!stats) return;
        
        // Format duration
        const elapsedSeconds = Math.floor(stats.elapsedSeconds);
        const hours = Math.floor(elapsedSeconds / 3600);
        const minutes = Math.floor((elapsedSeconds % 3600) / 60);
        const seconds = elapsedSeconds % 60;
        const durationStr = `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
        
        // Choose climb icon
        const climbIcon = stats.climbRate > 0.1 ? 'trending_up' : 
                         stats.climbRate < -0.1 ? 'trending_down' : 'trending_flat';
        const climbSign = stats.climbRate >= 0 ? '+' : '';
        
        // Update HTML
        this.container.innerHTML = `
            <div class="stat-item">
                <i class="material-icons">height</i>
                <div class="stat-value">${stats.altitude.toFixed(0)}m</div>
                <div class="stat-label">Altitude</div>
            </div>
            <div class="stat-item">
                <i class="material-icons">${climbIcon}</i>
                <div class="stat-value">${climbSign}${stats.climbRate.toFixed(1)}m/s</div>
                <div class="stat-label">Climb</div>
            </div>
            <div class="stat-item">
                <i class="material-icons">speed</i>
                <div class="stat-value">${stats.speed.toFixed(1)}km/h</div>
                <div class="stat-label">Speed</div>
            </div>
            <div class="stat-item">
                <i class="material-icons">timer</i>
                <div class="stat-value">${durationStr}</div>
                <div class="stat-label">Duration</div>
            </div>
        `;
    }
}

// ============================================================================
// Main Cesium Flight Application
// ============================================================================

class CesiumFlightApp {
    constructor() {
        this.viewer = null;
        this.flightDataSource = null;
        this.trackPrimitives = null;
        this.statisticsDisplay = null;
        this.performanceMonitor = null;
        this.cameraFollowing = false;
        this._ribbonModeAuto = true;
        this._updateThrottle = { lastUpdate: 0, interval: 100 };
        this._originalQualitySettings = null;
        this._qualityRestoreTimer = null;
        
        // Optimized Sentinel-2 color parameters
        this.colorTuningParams = {
            saturation: 0.55,
            hue: -0.09,
            contrast: 1.15,
            brightness: 0.95,
            gamma: 1.25
        };
        
    }
    
    initialize(config) {
        PerformanceReporter.measureTime('initialization', () => {
            this._createViewer(config);
            
            // Initialize performance monitor after viewer is created
            this.performanceMonitor = new CesiumPerformanceMonitor(this.viewer);
            cesiumLog.info('Performance monitor initialized');
            
            this._setupEventHandlers();
            
            // Load initial track if provided
            if (config.trackPoints?.length > 0) {
                setTimeout(() => this.loadFlightTrack(config.trackPoints), 100);
            }
        });
    }
    
    _createViewer(config) {
        // Essential imagery providers
        const imageryProviders = this._createImageryProviders(config);
        let selectedProvider;
        
        if (config.savedBaseMap) {
            selectedProvider = imageryProviders.find(vm => vm.name === config.savedBaseMap);
            
            // If saved provider not found, use default
            if (!selectedProvider) {
                selectedProvider = imageryProviders[0];
            }
        } else {
            selectedProvider = imageryProviders[0];
        }
        
        // Adaptive resolution scaling based on device capability and user preference
        const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
        
        // Default resolution: Performance mode for mobile, Quality for desktop
        const defaultResolution = isMobile ? 0.75 : 1.0;
        if (isMobile) {
            cesiumLog.info('Using Performance resolution (0.75x) - mobile device detected');
        }
        
        this.currentResolution = config.savedResolutionScale || defaultResolution;
        
        // Check if user has provided their own token for terrain
        const hasUserToken = config?.hasUserToken === true;
        
        // Prepare viewer options
        const viewerOptions = {
            requestRenderMode: true,
            maximumRenderTimeChange: Infinity,
            resolutionScale: this.currentResolution,  // Apply adaptive resolution scaling
            
            // UI controls
            baseLayerPicker: true,
            imageryProviderViewModels: imageryProviders,
            selectedImageryProviderViewModel: selectedProvider,
            geocoder: true,
            homeButton: true,
            sceneModePicker: true,
            navigationHelpButton: true,
            navigationInstructionsInitiallyVisible: config.savedNavigationHelpDialogOpen || false,
            animation: false,
            timeline: true,
            fullscreenButton: true,
            vrButton: false,
            shadows: false,
            shouldAnimate: false,
            creditContainer: document.getElementById('customCreditContainer')
        };
        
        // Only include terrain if user has their own token
        if (hasUserToken) {
            viewerOptions.terrain = Cesium.Terrain.fromWorldTerrain({
                requestWaterMask: false,
                requestVertexNormals: true
            });
            cesiumLog.info('Terrain enabled - user has provided Cesium Ion token');
        } else {
            cesiumLog.info('Terrain disabled - using app token, no terrain to prevent quota usage');
        }
        
        // Create viewer with conditional terrain
        this.viewer = new Cesium.Viewer("cesiumContainer", viewerOptions);
        
        this._configureScene();
        this._setupInitialView(config);
        
        // Apply dynamic lighting for initial provider (after viewer is fully initialized)
        setTimeout(() => {
            this._updateLightingForProvider(selectedProvider.name);
        }, 300);
        
        // Disable geocoder autocomplete to reduce quota usage
        if (this.viewer.geocoder?.viewModel) {
            this.viewer.geocoder.viewModel.autoComplete = false;
            cesiumLog.debug('Disabled geocoder autocomplete to reduce quota usage');
        }
        
        // Configure enhanced caching for better performance
        this._configureCaching();
        
        // Apply initial color adjustments for the selected provider
        setTimeout(() => {
            this._adjustImageryLayerColors(selectedProvider.name);
        }, 200); // Slightly longer delay to ensure viewer is fully initialized
        
        // Hide terrain options from baseLayerPicker - show only imagery choices
        if (this.viewer.baseLayerPicker && this.viewer.baseLayerPicker.viewModel) {
            this.viewer.baseLayerPicker.viewModel.terrainProviderViewModels = [];
            
            // Hide the "Imagery" category label whenever the picker is opened
            const hideImageryLabel = () => {
                const pickerContainer = document.querySelector('.cesium-baseLayerPicker-dropDown');
                if (pickerContainer) {
                    const categoryLabels = pickerContainer.querySelectorAll('.cesium-baseLayerPicker-sectionTitle');
                    categoryLabels.forEach(label => {
                        if (label.textContent === 'Imagery') {
                            label.style.display = 'none';
                        }
                    });
                }
            };
            
            // Watch for dropdown visibility changes
            const pickerButton = document.querySelector('.cesium-baseLayerPicker-selected');
            if (pickerButton) {
                pickerButton.addEventListener('click', () => {
                    setTimeout(hideImageryLabel, 10);
                });
            }
            
            // Also hide on initial load
            setTimeout(hideImageryLabel, 100);
        }
        
        // Set quality picker to current resolution
        const qualityPicker = document.getElementById('qualityPicker');
        if (qualityPicker) {
            qualityPicker.value = this.currentResolution.toFixed(this.currentResolution === 0.75 ? 2 : 1);
        }
    }
    
    _createImageryProviders(config) {
        // Base free providers (always available)
        const baseProviders = [
            new Cesium.ProviderViewModel({
                name: 'OpenStreetMap',
                iconUrl: Cesium.buildModuleUrl('Widgets/Images/ImageryProviders/openStreetMap.png'),
                tooltip: 'OpenStreetMap - Free, no quota usage',
                creationFunction: () => {
                    try {
                        return new Cesium.OpenStreetMapImageryProvider({
                            url: 'https://{s}.tile.openstreetmap.org/',
                            subdomains: ['a', 'b', 'c'],
                            maximumLevel: 18,
                            credit: new Cesium.Credit('© OpenStreetMap contributors', false)
                        });
                    } catch (error) {
                        cesiumLog.error('Failed to create OpenStreetMap provider:', error.message);
                        throw new Error('OpenStreetMap provider creation failed');
                    }
                }
            }),
            new Cesium.ProviderViewModel({
                name: 'Sentinel-2',
                iconUrl: Cesium.buildModuleUrl('Widgets/Images/ImageryProviders/sentinel-2.png'),
                tooltip: 'Sentinel-2 satellite imagery - 10m resolution',
                creationFunction: () => Cesium.IonImageryProvider.fromAssetId(3954)
            })
        ];
        
        // Premium providers (requires user's own Cesium Ion token)
        const premiumProviders = [
            new Cesium.ProviderViewModel({
                name: 'Bing Maps Aerial with Labels',
                iconUrl: Cesium.buildModuleUrl('Widgets/Images/ImageryProviders/bingAerialLabels.png'),
                tooltip: 'Bing Maps aerial imagery with labels - Premium (requires your Cesium Ion token)',
                creationFunction: () => Cesium.IonImageryProvider.fromAssetId(3)
            }),
            new Cesium.ProviderViewModel({
                name: 'Bing Maps Roads',
                iconUrl: Cesium.buildModuleUrl('Widgets/Images/ImageryProviders/bingRoads.png'),
                tooltip: 'Bing Maps road map - Premium (requires your Cesium Ion token)',
                creationFunction: () => Cesium.IonImageryProvider.fromAssetId(4)
            })
        ];
        
        // Check if user has provided their own token
        const hasUserToken = config?.hasUserToken === true;
        
        let availableProviders;
        if (hasUserToken) {
            // User has their own token - show ONLY premium providers
            availableProviders = premiumProviders;
            cesiumLog.info('Using user token - showing only premium Bing Maps providers');
        } else {
            // Using app token - only free providers to prevent quota usage
            availableProviders = baseProviders;
            cesiumLog.info('Using app token - free providers only to eliminate quota usage');
        }
        
        cesiumLog.info(`Available providers: ${availableProviders.map(p => p.name).join(', ')}`);
        return availableProviders;
    }
    
    _configureScene() {
        const scene = this.viewer.scene;
        const globe = scene.globe;
        
        // Dynamic lighting will be set separately after provider is fully loaded
        globe.showGroundAtmosphere = true;
        globe.depthTestAgainstTerrain = true;
        globe.terrainExaggeration = 1.0;
        
        // Use lighter base color for better visibility
        globe.baseColor = Cesium.Color.fromCssColorString('#505050');
        scene.backgroundColor = Cesium.Color.fromCssColorString('#505050');
        
        // Adjust fog for better depth perception and terrain visibility
        scene.fog.enabled = true;
        scene.fog.density = 0.000025;  // Slightly increased from 0.00002 for better depth cues
        scene.fog.screenSpaceErrorFactor = 3.5;  // Reduced from 4.0 for better near/far balance
        cesiumLog.info(`Fog configured - density: ${scene.fog.density}, errorFactor: ${scene.fog.screenSpaceErrorFactor}`);
        
        // Brightness and gamma adjustments
        scene.highDynamicRange = true;
        scene.fxaa = true;
        scene.msaaSamples = 8;
        
        // Increase overall scene brightness
        scene.gamma = 1.8;  // Brighten the overall scene
        
        // Adjust atmosphere brightness
        scene.skyAtmosphere.brightnessShift = 0.3;  // Brighten the atmosphere
        scene.skyAtmosphere.hueShift = 0.0;
        scene.skyAtmosphere.saturationShift = -0.1;  // Slightly desaturate for clarity
        
        // High-quality terrain settings
        globe.tileCacheSize = 500;  // Increased cache for smoother terrain
        globe.preloadSiblings = true;
        globe.preloadAncestors = true;
        globe.maximumMemoryUsage = 512;
        globe.maximumScreenSpaceError = 1.0;  // Reduced for higher quality terrain
        
        // Camera controls
        const controller = scene.screenSpaceCameraController;
        controller.enableCollisionDetection = true;
        controller.minimumZoomDistance = 10.0;
        controller.minimumCollisionTerrainHeight = 5000.0;
        controller.collisionDetectionHeightBuffer = 10.0;
    }
    
    _updateLightingForProvider(providerName) {
        if (!this.viewer?.scene?.globe) return;
        
        const globe = this.viewer.scene.globe;
        
        // Determine if provider needs lighting based on provider name
        // Flat/cartographic imagery benefits from terrain shadows to show relief
        const flatProviders = ['OpenStreetMap', 'Stamen Terrain'];
        const needsLighting = flatProviders.includes(providerName);
        
        globe.enableLighting = needsLighting;
        
        cesiumLog.info(`Dynamic lighting ${needsLighting ? 'enabled' : 'disabled'} for ${providerName}`);
        
        if (needsLighting) {
            cesiumLog.info('Terrain shadows enabled for flat cartographic imagery');
        } else {
            cesiumLog.info('Terrain lighting disabled for satellite/aerial imagery (has natural shadows)');
        }
    }
    
    _setupInitialView(config) {
        if (!config.trackPoints?.length) {
            this.viewer.camera.setView({
                destination: Cesium.Cartesian3.fromDegrees(config.lon, config.lat, config.altitude),
                orientation: {
                    heading: 0,
                    pitch: Cesium.Math.toRadians(-45),
                    roll: 0
                }
            });
        }
        
        // Apply saved scene mode
        if (config.savedSceneMode && config.savedSceneMode !== '3D') {
            const sceneMode = config.savedSceneMode === '2D' ? Cesium.SceneMode.SCENE2D :
                             config.savedSceneMode === 'Columbus' ? Cesium.SceneMode.COLUMBUS_VIEW :
                             Cesium.SceneMode.SCENE3D;
            this.viewer.scene.mode = sceneMode;
        }
    }
    
    _setupEventHandlers() {
        // Clock tick handler
        this.viewer.clock.onTick.addEventListener((clock) => this._onClockTick(clock));
        
        // Scene mode change handler
        this.viewer.scene.morphComplete.addEventListener(() => this._onSceneModeChange());
        
        // Home button override
        if (this.viewer.homeButton?.viewModel) {
            this.viewer.homeButton.viewModel.command.beforeExecute.addEventListener((commandInfo) => {
                if (this.flightDataSource?.boundingSphere) {
                    commandInfo.cancel = true;
                    this._flyToFlightTrack();
                }
            });
        }
        
        // Loading overlay
        this.viewer.scene.globe.tileLoadProgressEvent.addEventListener((queuedTileCount) => {
            if (queuedTileCount === 0) {
                document.getElementById('loadingOverlay').style.display = 'none';
            }
        });
        
        // Listen for base layer picker changes
        if (this.viewer.baseLayerPicker && this.viewer.baseLayerPicker.viewModel) {
            // Subscribe to imagery provider changes
            Cesium.knockout.getObservable(
                this.viewer.baseLayerPicker.viewModel, 
                'selectedImagery'
            ).subscribe((providerViewModel) => {
                if (providerViewModel) {
                    try {
                        // Start performance monitoring for provider switch
                        if (this.performanceMonitor) {
                            this.performanceMonitor.startProviderSwitch(providerViewModel.name);
                            
                            // Set up monitoring end conditions
                            let monitoringEnded = false;
                            const endMonitoring = () => {
                                if (!monitoringEnded) {
                                    monitoringEnded = true;
                                    this.performanceMonitor.endProviderSwitch();
                                }
                            };
                            
                            // End monitoring when tiles are loaded OR timeout
                            let tileCheckCount = 0;
                            const maxTileChecks = 100; // 10 seconds max (100 * 100ms)
                            
                            const checkTileCompletion = () => {
                                tileCheckCount++;
                                
                                // Get current tile queue count
                                const queuedTiles = this.viewer?.scene?.globe?.tilesWaitingForChildren?.length || 0;
                                const hasActiveRequests = queuedTiles > 0;
                                
                                // End monitoring if no active requests or timeout
                                if (!hasActiveRequests || tileCheckCount >= maxTileChecks) {
                                    endMonitoring();
                                } else {
                                    setTimeout(checkTileCompletion, 100); // Check every 100ms
                                }
                            };
                            
                            // Start checking after a brief delay
                            setTimeout(checkTileCompletion, 500);
                            
                            // Absolute timeout as fallback
                            setTimeout(endMonitoring, 10000); // 10 second absolute maximum
                            
                            // Start monitoring for tile load failures
                            this.performanceMonitor.startTileFailureMonitoring((failedProvider, failureRate) => {
                                cesiumLog.error(`Provider "${failedProvider}" has high failure rate: ${(failureRate * 100).toFixed(1)}%`);
                                
                                // Try fallback to OpenStreetMap
                                const fallbackProvider = this.viewer.baseLayerPicker.viewModel.imageryProviderViewModels
                                    .find(vm => vm.name === 'OpenStreetMap' && vm.name !== failedProvider);
                                
                                if (fallbackProvider) {
                                    cesiumLog.info(`Automatic fallback to ${fallbackProvider.name} due to tile failures`);
                                    setTimeout(() => {
                                        this.viewer.baseLayerPicker.viewModel.selectedImagery = fallbackProvider;
                                    }, 100);
                                }
                            });
                        }
                        
                        // Force refresh of globe to ensure tiles reload
                        if (this.viewer.scene?.globe) {
                            this.viewer.scene.requestRender();
                        }
                        
                        // Notify Flutter of the map change
                        if (window.flutter_inappwebview?.callHandler) {
                            window.flutter_inappwebview.callHandler(
                                'onImageryProviderChanged', 
                                providerViewModel.name
                            );
                        }
                        console.log('[Cesium] Imagery provider changed to:', providerViewModel.name);
                        
                        // Apply color adjustments and lighting for specific providers
                        setTimeout(() => {
                            this._adjustImageryLayerColors(providerViewModel.name);
                            this._updateLightingForProvider(providerViewModel.name);
                        }, 100); // Small delay to ensure provider is fully loaded
                        
                    } catch (error) {
                        cesiumLog.error(`Failed to switch to provider "${providerViewModel.name}": ${error.message}`);
                        console.error('[Cesium] Provider switch error:', error);
                        
                        // Fallback to OpenStreetMap if provider switch fails
                        const fallbackProvider = this.viewer.baseLayerPicker.viewModel.imageryProviderViewModels
                            .find(vm => vm.name === 'OpenStreetMap');
                        
                        if (fallbackProvider && fallbackProvider !== providerViewModel) {
                            cesiumLog.info('Falling back to OpenStreetMap provider');
                            setTimeout(() => {
                                this.viewer.baseLayerPicker.viewModel.selectedImagery = fallbackProvider;
                                // Apply color adjustments and lighting to fallback provider as well
                                setTimeout(() => {
                                    this._adjustImageryLayerColors(fallbackProvider.name);
                                    this._updateLightingForProvider(fallbackProvider.name);
                                }, 100);
                            }, 100);
                        }
                    }
                }
            });
        }
    }
    
    
    _adjustImageryLayerColors(providerName) {
        // Apply color corrections only to Sentinel-2 to reduce green tint
        if (!this.viewer?.imageryLayers || this.viewer.imageryLayers.length === 0) return;
        
        const layer = this.viewer.imageryLayers.get(0);
        
        // Reset to defaults first
        layer.brightness = 1.0;
        layer.contrast = 1.0;
        layer.saturation = 1.0;
        layer.hue = 0.0;
        layer.gamma = 1.0;
        
        if (providerName === 'Sentinel-2') {
            // Apply current tuning parameters for Sentinel-2
            layer.saturation = this.colorTuningParams.saturation;
            layer.hue = this.colorTuningParams.hue;
            layer.contrast = this.colorTuningParams.contrast;
            layer.brightness = this.colorTuningParams.brightness;
            layer.gamma = this.colorTuningParams.gamma;
            cesiumLog.info(`Applied Sentinel-2 color tuning: sat=${this.colorTuningParams.saturation}, hue=${this.colorTuningParams.hue}, cont=${this.colorTuningParams.contrast}, bright=${this.colorTuningParams.brightness}, gamma=${this.colorTuningParams.gamma}`);
        }
    }
    
    async _waitForTerrainReady(timeout = 5000) {
        // Wait for terrain provider to be fully loaded and ready
        const start = Date.now();
        cesiumLog.info('Waiting for terrain provider to be ready...');
        
        while (Date.now() - start < timeout) {
            const provider = this.viewer?.terrainProvider;
            
            if (provider) {
                const providerName = provider.constructor.name;
                const isReady = provider.ready;
                // Use capability-based detection instead of class name (minification-safe)
                const hasTerrainCapability = typeof provider.requestTileGeometry === 'function';
                const isEllipsoid = providerName === 'EllipsoidTerrainProvider';
                
                cesiumLog.debug(`Terrain check: provider=${providerName}, ready=${isReady}, hasCapability=${hasTerrainCapability}, isEllipsoid=${isEllipsoid}`);
                
                if (isReady && hasTerrainCapability && !isEllipsoid) {
                    cesiumLog.info(`Terrain provider ready with capability: ${providerName}`);
                    return provider;
                } else if (isReady && isEllipsoid) {
                    // Ellipsoid provider is ready - no terrain will be loaded
                    cesiumLog.info('Ellipsoid terrain provider ready - no terrain enabled');
                    return provider;
                }
            }
            
            // Wait a bit before checking again
            await new Promise(resolve => setTimeout(resolve, 100));
        }
        
        cesiumLog.warn(`Terrain provider not ready after ${timeout}ms timeout`);
        return this.viewer?.terrainProvider || null;
    }
    
    async loadFlightTrack(igcPoints) {
        if (!igcPoints?.length) return;
        
        const totalStart = performance.now();
        
        try {
            // Clear existing data
            this._clearAll();
            
            // Wait for terrain provider to be ready before creating flight data source
            // This prevents race conditions where terrain correction is skipped
            await this._waitForTerrainReady();
            
            // Create new flight data source (this is now async)
            this.flightDataSource = new FlightDataSource('Flight Track', igcPoints, this.viewer);
            
            // Wait for the flight data source to complete initialization (including terrain correction)
            // The FlightDataSource constructor calls _initializeFlightData() which is async
            // We need to wait for it to complete before proceeding
            while (!this.flightDataSource.positions || this.flightDataSource.positions.length === 0) {
                await new Promise(resolve => setTimeout(resolve, 10)); // Wait 10ms and check again
            }
            
            this.viewer.dataSources.add(this.flightDataSource);
            
            // Create track primitives
            this.trackPrimitives = new TrackPrimitiveCollection(this.viewer, this.flightDataSource);
            
            // Create statistics display
            this.statisticsDisplay = new StatisticsDisplay(this.flightDataSource);
            this.statisticsDisplay.initialize();
            
            // Configure clock
            this._configureClock();
            
            // Configure timeline for local time
            this._configureTimeline();
            
            // Zoom to track
            this._performInitialZoom();
            
            // Force resize after UI changes
            setTimeout(() => this.viewer.resize(), 350);
            
            PerformanceReporter.report('totalTrackLoad', performance.now() - totalStart);
            
        } catch (error) {
            cesiumLog.error(`Failed to load flight track: ${error.message}`);
            throw error;
        }
    }
    
    _configureClock() {
        const clock = this.viewer.clock;
        const data = this.flightDataSource;
        
        clock.startTime = data.startTime.clone();
        clock.stopTime = data.stopTime.clone();
        clock.currentTime = data.startTime.clone();
        clock.clockRange = Cesium.ClockRange.CLAMPED;
        clock.multiplier = 60;
        clock.shouldAnimate = false;
        
        if (this.viewer.timeline) {
            this.viewer.timeline.zoomTo(data.startTime, data.stopTime);
        }
    }
    
    _configureTimeline() {
        const data = this.flightDataSource;
        const offsetSeconds = data.timezoneOffsetSeconds;
        const timezone = data.timezone;
        
        if (this.viewer.timeline) {
            this.viewer.timeline.makeLabel = (date) => {
                const localDate = Cesium.JulianDate.addSeconds(date, offsetSeconds, new Cesium.JulianDate());
                const gregorian = Cesium.JulianDate.toGregorianDate(localDate);
                const hours = gregorian.hour.toString().padStart(2, '0');
                const minutes = gregorian.minute.toString().padStart(2, '0');
                const seconds = Math.floor(gregorian.second).toString().padStart(2, '0');
                return `${hours}:${minutes}:${seconds} ${timezone}`;
            };
            
            // Force timeline to redraw with new labels (idiomatic Cesium way)
            this.viewer.timeline.updateFromClock();
            this.viewer.timeline.zoomTo(
                this.viewer.clock.startTime,
                this.viewer.clock.stopTime
            );
        }
    }
    
    _performInitialZoom() {
        const data = this.flightDataSource;
        const launch = data.igcPoints[0];
        const boundingSphere = data.boundingSphere;
        
        // Step 1: High altitude view
        this.viewer.camera.setView({
            destination: Cesium.Cartesian3.fromDegrees(launch.longitude, launch.latitude, 30000000),
            orientation: {
                heading: 0,
                pitch: Cesium.Math.toRadians(-90),
                roll: 0
            }
        });
        
        // Step 2: Fly to bounding sphere
        setTimeout(() => {
            this.viewer.camera.flyToBoundingSphere(boundingSphere, {
                duration: 5.0,
                offset: new Cesium.HeadingPitchRange(
                    Cesium.Math.toRadians(0),
                    Cesium.Math.toRadians(-90),
                    boundingSphere.radius * 2.5
                ),
                complete: () => {
                    // Step 3: Final view angle
                    this.viewer.camera.flyToBoundingSphere(boundingSphere, {
                        duration: 3.0,
                        offset: new Cesium.HeadingPitchRange(
                            Cesium.Math.toRadians(0),
                            Cesium.Math.toRadians(-30),
                            boundingSphere.radius * 2.75
                        )
                    });
                }
            });
        }, 5000);
    }
    
    _flyToFlightTrack() {
        if (!this.flightDataSource) return;
        
        const boundingSphere = this.flightDataSource.boundingSphere;
        this.viewer.camera.flyToBoundingSphere(boundingSphere, {
            duration: 3.0,
            offset: new Cesium.HeadingPitchRange(
                Cesium.Math.toRadians(0),
                Cesium.Math.toRadians(-30),
                boundingSphere.radius * 2.75
            )
        });
    }
    
    _onClockTick(clock) {
        if (!this.flightDataSource) return;
        
        // Handle automatic ribbon mode
        this._updateRibbonMode(clock);
        
        // Update statistics
        this.statisticsDisplay?.update(clock.currentTime);
        
        // Update dynamic track (throttled)
        const now = Date.now();
        if (now - this._updateThrottle.lastUpdate > this._updateThrottle.interval) {
            this._updateThrottle.lastUpdate = now;
            this.trackPrimitives?.updateDynamicTrack(clock.currentTime);
        }
        
        // Handle play button state
        this._updatePlayButton();
        
        // Handle end of playback
        this._handlePlaybackEnd(clock);
        
        // Update render mode
        this._updateRenderMode(clock);
    }
    
    _updateRibbonMode(clock) {
        if (!this._ribbonModeAuto) return;
        
        const atStart = Cesium.JulianDate.secondsDifference(clock.currentTime, clock.startTime) < 0.5;
        const atEnd = Cesium.JulianDate.compare(clock.currentTime, clock.stopTime) >= 0;
        const isStopped = !clock.shouldAnimate;
        
        const shouldShowRibbon = !(isStopped && (atStart || atEnd));
        
        if (shouldShowRibbon !== this._currentRibbonState) {
            this.flightDataSource?.enableRibbonMode(shouldShowRibbon);
            this.trackPrimitives?.enableRibbonMode(shouldShowRibbon);
            this._currentRibbonState = shouldShowRibbon;
        }
    }
    
    _updatePlayButton() {
        const button = document.getElementById('playButton');
        if (!button) return;
        
        const icon = button.querySelector('.material-icons');
        if (!icon) return;
        
        const clock = this.viewer.clock;
        const atStart = Cesium.JulianDate.secondsDifference(clock.currentTime, clock.startTime) < 0.5;
        const atEnd = Cesium.JulianDate.compare(clock.currentTime, clock.stopTime) >= 0;
        
        icon.textContent = (!clock.shouldAnimate || atStart || atEnd) ? 'play_arrow' : 'pause';
    }
    
    _handlePlaybackEnd(clock) {
        // Track animation state
        if (!this._wasAnimating) {
            this._wasAnimating = false;
        }
        
        const atEnd = Cesium.JulianDate.compare(clock.currentTime, clock.stopTime) >= 0;
        const justStarted = clock.shouldAnimate && !this._wasAnimating;
        
        if (atEnd && justStarted) {
            clock.currentTime = clock.startTime.clone();
        }
        
        if (atEnd && clock.shouldAnimate && !justStarted) {
            clock.shouldAnimate = false;
            clock.currentTime = clock.startTime.clone();
        }
        
        this._wasAnimating = clock.shouldAnimate;
    }
    
    _updateRenderMode(clock) {
        const shouldContinuousRender = this._currentRibbonState && clock.shouldAnimate;
        
        if (shouldContinuousRender && this.viewer.scene.requestRenderMode) {
            this.viewer.scene.requestRenderMode = false;
        } else if (!shouldContinuousRender && !this.viewer.scene.requestRenderMode) {
            this.viewer.scene.requestRenderMode = true;
            this.viewer.scene.requestRender();
        }
    }
    
    _onSceneModeChange() {
        const modeString = this._getSceneModeString();
        
        if (window.flutter_inappwebview?.callHandler) {
            window.flutter_inappwebview.callHandler('onSceneModeChanged', modeString);
        }
        
        // Always disable follow mode on scene change (Cesium loses tracked entity anyway)
        if (this.cameraFollowing) {
            this.viewer.trackedEntity = undefined;
            this.cameraFollowing = false;
            const button = document.getElementById('followButton');
            if (button) button.style.backgroundColor = 'rgba(42, 42, 42, 0.8)';
        }
        
        // Update camera controls
        const controller = this.viewer.scene.screenSpaceCameraController;
        if (this.viewer.scene.mode === Cesium.SceneMode.SCENE2D) {
            controller.enableCollisionDetection = false;
            controller.enableRotate = false;
            controller.enableTilt = false;
        } else {
            controller.enableCollisionDetection = true;
            controller.enableRotate = true;
            controller.enableTilt = true;
        }
        
        // Restore view
        if (this.flightDataSource) {
            setTimeout(() => this._flyToFlightTrack(), 500);
        }
    }
    
    _getSceneModeString() {
        switch(this.viewer.scene.mode) {
            case Cesium.SceneMode.SCENE2D: return '2D';
            case Cesium.SceneMode.COLUMBUS_VIEW: return 'Columbus';
            default: return '3D';
        }
    }
    
    togglePlayback() {
        if (!this.viewer) return;
        this.viewer.clock.shouldAnimate = !this.viewer.clock.shouldAnimate;
    }
    
    changePlaybackSpeed(speed) {
        if (!this.viewer) return;
        const speedValue = parseFloat(speed);
        if (!isNaN(speedValue)) {
            this.viewer.clock.multiplier = speedValue;
            document.getElementById('speedPicker').value = speed;
        }
    }
    
    toggleCameraFollow() {
        if (!this.viewer || !this.flightDataSource) return;
        
        // Don't allow follow mode in 2D
        if (this.viewer.scene.mode === Cesium.SceneMode.SCENE2D) {
            console.log('Follow mode not available in 2D view');
            return;
        }
        
        const pilot = this.flightDataSource.pilotEntity;
        const button = document.getElementById('followButton');
        
        if (this.viewer.trackedEntity === pilot) {
            this.viewer.trackedEntity = undefined;
            this.cameraFollowing = false;
            if (button) button.style.backgroundColor = 'rgba(42, 42, 42, 0.8)';
        } else {
            this.viewer.trackedEntity = pilot;
            this.cameraFollowing = true;
            if (button) button.style.backgroundColor = 'rgba(76, 175, 80, 0.8)';
        }
    }
    
    _clearAll() {
        if (this.trackPrimitives) {
            this.trackPrimitives.destroy();
            this.trackPrimitives = null;
        }
        
        if (this.flightDataSource) {
            this.viewer.dataSources.remove(this.flightDataSource);
            this.flightDataSource = null;
        }
        
        this.viewer.entities.removeAll();
        this.viewer.scene.primitives.removeAll();
        
        this.statisticsDisplay?.hide();
    }
    
    cleanup() {
        this._clearAll();
        this.statisticsDisplay = null;
        
        if (this.viewer) {
            this.viewer.scene.requestRenderMode = true;
            this.viewer.destroy();
            this.viewer = null;
        }
    }
    
    handleMemoryPressure() {
        if (!this.viewer) return;
        
        PerformanceReporter.report('memoryPressureHandled', true);
        
        const globe = this.viewer.scene.globe;
        const scene = this.viewer.scene;
        
        // Store original settings on first memory pressure
        if (!this._originalQualitySettings) {
            this._originalQualitySettings = {
                tileCacheSize: globe.tileCacheSize,
                maximumMemoryUsage: globe.maximumMemoryUsage,
                maximumScreenSpaceError: globe.maximumScreenSpaceError,
                maximumTextureSize: scene.maximumTextureSize || 8192
            };
            console.log('[Cesium] Storing original quality settings:', this._originalQualitySettings);
        }
        
        // Clear tile cache
        if (globe?.tileCache) {
            globe.tileCache.reset();
        }
        
        // Apply gradual quality reduction (70% memory, 2x quality degradation)
        globe.tileCacheSize = Math.floor(this._originalQualitySettings.tileCacheSize * 0.7);
        globe.maximumMemoryUsage = Math.floor(this._originalQualitySettings.maximumMemoryUsage * 0.7);
        globe.maximumScreenSpaceError = Math.min(this._originalQualitySettings.maximumScreenSpaceError * 2, 4.0);
        scene.maximumTextureSize = 2048;
        
        console.log('[Cesium] Applied gradual quality reduction:', {
            tileCacheSize: globe.tileCacheSize,
            maximumMemoryUsage: globe.maximumMemoryUsage,
            maximumScreenSpaceError: globe.maximumScreenSpaceError
        });
        
        // Request render with reduced quality
        scene.requestRenderMode = true;
        scene.requestRender();
        
        // Clear any existing restore timer
        if (this._qualityRestoreTimer) {
            clearTimeout(this._qualityRestoreTimer);
        }
        
        // Schedule quality restoration after 30 seconds
        this._qualityRestoreTimer = setTimeout(() => {
            this.restoreQualitySettings();
        }, 30000);
        
        console.log('[Cesium] Quality will be restored in 30 seconds');
        
        // Trigger garbage collection if available
        if (window.gc) window.gc();
    }
    
    restoreQualitySettings() {
        if (!this.viewer || !this._originalQualitySettings) return;
        
        const globe = this.viewer.scene.globe;
        const scene = this.viewer.scene;
        
        console.log('[Cesium] Restoring original quality settings');
        
        // Restore original settings
        globe.tileCacheSize = this._originalQualitySettings.tileCacheSize;
        globe.maximumMemoryUsage = this._originalQualitySettings.maximumMemoryUsage;
        globe.maximumScreenSpaceError = this._originalQualitySettings.maximumScreenSpaceError;
        scene.maximumTextureSize = this._originalQualitySettings.maximumTextureSize;
        
        // Clear the restore timer
        if (this._qualityRestoreTimer) {
            clearTimeout(this._qualityRestoreTimer);
            this._qualityRestoreTimer = null;
        }
        
        // Request render with restored quality
        scene.requestRenderMode = false;
        scene.requestRender();
        
        console.log('[Cesium] Quality settings restored:', {
            tileCacheSize: globe.tileCacheSize,
            maximumMemoryUsage: globe.maximumMemoryUsage,
            maximumScreenSpaceError: globe.maximumScreenSpaceError
        });
        
        PerformanceReporter.report('qualityRestored', true);
    }
    
    changeRenderQuality(newScale) {
        const scale = parseFloat(newScale);
        if (isNaN(scale) || scale <= 0) return;
        
        this.currentResolution = scale;
        this.viewer.resolutionScale = scale;
        
        // Update quality picker to reflect current selection
        const qualityPicker = document.getElementById('qualityPicker');
        if (qualityPicker) {
            qualityPicker.value = scale.toFixed(scale === 0.75 ? 2 : 1);
        }
        
        // Force a render to apply the new resolution
        this.viewer.scene.requestRender();
        
        // Log the quality change
        const qualityNames = { '0.75': 'Performance', '1.0': 'Quality', '2.0': 'Ultra' };
        const qualityName = qualityNames[scale.toString()] || `${scale}x`;
        cesiumLog.info(`Render quality changed to ${qualityName} (${scale}x resolution)`);
        
        PerformanceReporter.report('qualityChanged', qualityName);
        
        // Save preference if Flutter webview is available
        if (window.flutter_inappwebview?.callHandler) {
            window.flutter_inappwebview.callHandler('saveResolutionScale', scale);
        }
    }
    
    
    
    
    
    _configureCaching() {
        const scene = this.viewer.scene;
        const globe = scene.globe;
        
        // Enable aggressive caching for tiles
        if (globe.imageryLayers?.length > 0) {
            globe.imageryLayers.get(0).alpha = 1.0; // Ensure full opacity for caching
        }
        
        // Configure terrain caching
        if (globe.terrainProvider) {
            globe.preloadAncestors = true;
            globe.preloadSiblings = true;
            globe.tileCacheSize = 300; // Optimized cache size
        }
        
        // Log caching configuration
        cesiumLog.info('Enhanced caching configured: terrain preloading enabled, optimized cache size set');
        
        // Report caching metrics if available
        if (window.performance?.memory) {
            PerformanceReporter.report('cachingEnabled', true);
        }
    }
}

// ============================================================================
// Global Instance and API
// ============================================================================

let cesiumApp = null;

// Initialize function called from HTML
function initializeCesium(config) {
    // Set Ion token
    Cesium.Ion.defaultAccessToken = config.token;
    
    // Create and initialize app
    cesiumApp = new CesiumFlightApp();
    cesiumApp.initialize(config);
    
    // Store globally for compatibility
    window.viewer = cesiumApp.viewer;
}

// Public API functions
async function createColoredFlightTrack(points) {
    if (cesiumApp) {
        await cesiumApp.loadFlightTrack(points);
    }
}

function togglePlayback() {
    cesiumApp?.togglePlayback();
}

function changePlaybackSpeed(speed) {
    cesiumApp?.changePlaybackSpeed(speed);
}

function toggleCameraFollow() {
    cesiumApp?.toggleCameraFollow();
}

function toggleTerrain() {
    cesiumApp?.flightDataSource?.toggleTerrain();
}

function changeRenderQuality(scale) {
    cesiumApp?.changeRenderQuality(scale);
}

function reportPerformanceState() {
    if (cesiumApp?.performanceMonitor) {
        return cesiumApp.performanceMonitor.reportCurrentState();
    }
    return null;
}

function cleanupCesium() {
    cesiumApp?.cleanup();
    cesiumApp = null;
    window.viewer = null;
}

function handleMemoryPressure() {
    cesiumApp?.handleMemoryPressure();
}

function restoreQualitySettings() {
    cesiumApp?.restoreQualitySettings();
}


function checkMemory() {
    if (window.performance?.memory) {
        const memory = window.performance.memory;
        return {
            used: Math.round(memory.usedJSHeapSize / 1048576),
            total: Math.round(memory.totalJSHeapSize / 1048576),
            limit: Math.round(memory.jsHeapSizeLimit / 1048576)
        };
    }
    return null;
}

// Cleanup on page unload
window.addEventListener('beforeunload', cleanupCesium);

// Handle visibility changes
document.addEventListener('visibilitychange', () => {
    if (cesiumApp?.viewer) {
        if (document.hidden) {
            cesiumApp.viewer.scene.requestRenderMode = true;
            cesiumApp.viewer.scene.maximumRenderTimeChange = Infinity;
        } else {
            cesiumApp.viewer.scene.requestRenderMode = false;
        }
    }
});

// Export public API
window.initializeCesium = initializeCesium;
window.createColoredFlightTrack = createColoredFlightTrack;
window.togglePlayback = togglePlayback;
window.changePlaybackSpeed = changePlaybackSpeed;
window.toggleCameraFollow = toggleCameraFollow;
window.toggleTerrain = toggleTerrain;
window.cleanupCesium = cleanupCesium;
window.handleMemoryPressure = handleMemoryPressure;
window.restoreQualitySettings = restoreQualitySettings;
window.checkMemory = checkMemory;

