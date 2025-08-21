# Makefile for Free Flight Log Flutter App
# Optimized build commands for development

.PHONY: help clean build-fast run-fast analyze test profile

help:
	@echo "Available commands:"
	@echo "  make run-fast    - Fast debug build and run"
	@echo "  make build-fast  - Fast debug build only"
	@echo "  make clean       - Clean all build artifacts"
	@echo "  make analyze     - Run Flutter analyze"
	@echo "  make test        - Run tests"
	@echo "  make profile     - Build with profiling"

# Fast run for development (Pixel device)
run-fast:
	@flutter run -d Pixel \
		--debug \
		--no-tree-shake-icons \
		--target-platform=android-arm64 \
		--dart-define=FLUTTER_BUILD_MODE=debug

# Fast run for emulator
run-emulator:
	@flutter run -d emulator-5554 \
		--debug \
		--no-tree-shake-icons \
		--target-platform=android-arm64 \
		--dart-define=FLUTTER_BUILD_MODE=debug

# Fast build without running
build-fast:
	@flutter build apk \
		--debug \
		--no-tree-shake-icons \
		--target-platform=android-arm64 \
		--split-per-abi

# Clean everything
clean:
	@echo "Cleaning Flutter build artifacts..."
	@flutter clean
	@echo "Cleaning Gradle cache..."
	@cd android && ./gradlew clean && ./gradlew cleanBuildCache
	@echo "Clean complete!"

# Analyze code
analyze:
	@flutter analyze

# Run tests
test:
	@flutter test

# Profile build
profile:
	@flutter run --profile \
		--target-platform=android-arm64 \
		--dart-define=FLUTTER_BUILD_MODE=profile

# Warm up Gradle for faster subsequent builds
warmup:
	@echo "Warming up Gradle daemon..."
	@cd android && ./gradlew --daemon
	@flutter pub get
	@echo "Warmup complete!"

# Check build time
benchmark:
	@echo "Benchmarking build time..."
	@time flutter build apk \
		--debug \
		--no-tree-shake-icons \
		--target-platform=android-arm64 \
		--split-per-abi