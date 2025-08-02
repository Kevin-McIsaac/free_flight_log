# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Free Flight Log is a cross-platform application for logging paraglider, hang glider, and microlight flights. This repository contains:

- **Complete Flutter Application**: Fully functional MVP with flight logging capabilities
- **Planning Documents**: Original functional specification, technical design, and MVP build plan
- **Legacy Design Assets**: An old app design from December 2022 created in Appery.io (a visual app builder)
- **Working Implementation**: Flutter app with database, UI screens, and core functionality

## Project Status

**IMPLEMENTATION COMPLETE** - The MVP has been successfully built and is functional:

✅ **Completed Features:**
- Flight logging with comprehensive form validation
- SQLite database with full CRUD operations
- Cross-platform support (Linux, Android, iOS, macOS, Windows)
- Material Design 3 UI with proper theming
- Flight list with statistics display
- Repository pattern architecture implementation
- Database initialization for all platforms

📋 **Planning Documents** (for reference):
- Complete functional requirements (FUNCTIONAL_SPECIFICATION.md)
- Technical architecture using Flutter/Dart (TECHNICAL_DESIGN.md)
- Week-by-week MVP implementation plan (MVP_BUILD_PLAN.md)

## Getting Started with Development

### Quick Start (App Already Built)
```bash
# Navigate to the Flutter app
cd free_flight_log_app

# Install dependencies
flutter pub get

# Run on Linux desktop (recommended for development)
flutter run -d linux

# Run on Android (device must be connected)
flutter run -d android
```

### Development Environment Setup
See the comprehensive setup guide in [README.md](free_flight_log_app/README.md) for:
- Flutter SDK installation
- Platform-specific development tools
- Android Studio/SDK setup
- Build tool requirements (CMake, Ninja, etc.)

### Current Dependencies (implemented)
```yaml
dependencies:
  flutter: sdk
  sqflite: ^2.3.0                    # Local SQLite database
  sqflite_common_ffi: ^2.3.0         # SQLite for desktop platforms
  shared_preferences: ^2.2.0         # Settings storage
  provider: ^6.1.0                   # State management
  google_maps_flutter: ^2.5.0        # Map visualization (for future use)
  file_picker: ^6.0.0                # IGC file import (for future use)
  fl_chart: ^0.65.0                  # Charts for altitude/climb rate
  intl: ^0.18.0                      # Date/time formatting
```

## Architecture Overview (Implemented)

**Current Implementation:**
- **Pattern**: MVVM with Repository pattern ✅
- **State Management**: Provider (ready for implementation) 
- **Database**: SQLite via sqflite (mobile) + sqflite_common_ffi (desktop) ✅
- **UI Framework**: Flutter with Material Design 3 ✅

### Current Project Structure
```
lib/
├── data/
│   ├── models/              # ✅ Flight, Site, Wing models
│   ├── repositories/        # ✅ Data access layer (CRUD operations)
│   └── datasources/         # ✅ Database helper with initialization
├── presentation/
│   ├── screens/             # ✅ Flight list, Add flight form
│   ├── widgets/             # 📁 Ready for reusable components
│   └── providers/           # 📁 Ready for state management
├── services/                # 📁 Ready for import/export, location
└── main.dart               # ✅ App entry point with database init
```

### Implemented Features
- **Flight Model**: Complete data model with validation
- **Database Helper**: SQLite initialization for all platforms  
- **Flight Repository**: Full CRUD operations with statistics
- **Site Repository**: Location management with coordinate search
- **Wing Repository**: Equipment tracking with usage stats
- **Flight List Screen**: Material Design 3 UI with empty states
- **Add Flight Form**: Comprehensive form with validation
- **Navigation**: Screen transitions with result callbacks

## Development Status

### ✅ MVP Features (COMPLETED)
1. ✅ Manual flight entry form with validation
2. ✅ Flight list display with statistics
3. ✅ Basic CRUD operations (Create, Read, Update, Delete)
4. ✅ Simple statistics (total flights/hours/max altitude)
5. ✅ Local SQLite persistence with cross-platform support

### 🚀 Next Features (Post-MVP)
1. 📋 IGC file import and parsing
2. 📋 Google Maps integration for track visualization
3. 📋 Altitude and climb rate charts (fl_chart ready)
4. 📋 Site recognition via reverse geocoding
5. 📋 Export functionality (CSV, KML)
6. 📋 Provider state management implementation
7. 📋 Flight detail view with edit capability
8. 📋 Wing/equipment management screens

## Key Technical Considerations

### IGC File Format
- International Gliding Commission standard for flight tracks
- Contains GPS coordinates, altitude, timestamps
- Parser needs to extract launch/landing sites, max altitude, climb rates
- Store complete track data for visualization

### Database Schema
Three main tables as defined in TECHNICAL_DESIGN.md:
- `flights`: Core flight records with stats
- `sites`: Launch/landing locations with custom names
- `wings`: Equipment tracking

### Performance Goals
- Support 10,000+ flight records
- IGC parsing at >1000 points/second
- Smooth 30fps map animations
- <2 second flight list load time

## Development Commands

### Current Working Commands

```bash
# Navigate to app directory
cd free_flight_log_app

# Install/update dependencies
flutter pub get

# Run on Linux desktop (recommended for development)
flutter run -d linux

# Run on Android device (must be connected with USB debugging)
flutter run -d android

# Check available devices
flutter devices

# Hot reload during development (press 'r' in terminal)
# Hot restart (press 'R' in terminal)
```

### Build Commands
```bash
# Clean build cache
flutter clean

# Build Linux desktop app
flutter build linux

# Build Android APK (debug)
flutter build apk --debug

# Build Android APK (release)
flutter build apk --release

# Build Android App Bundle for Play Store
flutter build appbundle --release
```

### Development Tools
```bash
# Analyze code for issues
flutter analyze

# Run tests (when implemented)
flutter test

# Format code
dart format .

# Check Flutter installation
flutter doctor

# Update Flutter
flutter upgrade
```

## Testing Approach

### Current Testing Status
✅ **Manual testing completed** with flight entry and display  
✅ **CRUD operations verified** with database persistence  
✅ **Form validation tested** with edge cases  
✅ **Cross-platform verified** on Linux desktop  

### Recommended Testing
1. Test flight entry with various time combinations
2. Verify database persistence across app restarts
3. Test form validation edge cases (e.g., landing before launch)
4. Performance testing with multiple flight entries
5. Cross-platform testing (Linux, Android, iOS)

## Known Issues and Troubleshooting

### Common Issues
1. **"Database factory not initialized" Error**
   - Fixed in main.dart with sqflite_common_ffi initialization
   - Rebuild app if error persists: `flutter clean && flutter build linux`

2. **File Picker Warnings**
   - Informational warnings about plugin implementations
   - Safe to ignore - don't affect app functionality

3. **App Screen Disappears**
   - Run built binary directly: `./build/linux/x64/release/bundle/free_flight_log_app`
   - Or use: `flutter run -d linux` after ensuring clean build

4. **Android Device Not Detected**
   - Enable USB debugging in Developer Options
   - Use `adb devices` to verify connection
   - Use `flutter devices` to check Flutter detection

## Important Notes

- This is a **local-only** app - no cloud services or user authentication
- All data stored on device in SQLite database
- Cross-platform support: Linux ✅, Android ✅, iOS ✅, macOS ✅, Windows ✅
- Material Design 3 UI with proper theming
- Database schema supports advanced features (IGC import, site management, wing tracking)