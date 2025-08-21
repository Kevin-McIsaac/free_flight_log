#!/bin/bash

# Fast Flutter Build Script for Development
# Optimized for quick iteration during development

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Fast Flutter Build - Development Mode${NC}"

# Detect connected device
DEVICE=$(flutter devices | grep -E "^[^•].*•" | head -1 | awk '{print $1}')

if [ -z "$DEVICE" ]; then
    echo -e "${YELLOW}No device found. Please connect a device or start an emulator.${NC}"
    exit 1
fi

echo -e "${GREEN}Building for device: $DEVICE${NC}"

# Get device architecture
ARCH=$(adb -s $DEVICE shell getprop ro.product.cpu.abi)
echo -e "${GREEN}Device architecture: $ARCH${NC}"

# Set target platform based on architecture
if [[ "$ARCH" == "arm64-v8a" ]]; then
    TARGET_PLATFORM="android-arm64"
elif [[ "$ARCH" == "armeabi-v7a" ]]; then
    TARGET_PLATFORM="android-arm"
else
    TARGET_PLATFORM="android-arm64"  # Default
fi

# Build flags for maximum speed
BUILD_FLAGS=(
    "--debug"
    "--no-tree-shake-icons"
    "--target-platform=$TARGET_PLATFORM"
    "--no-android-gradle-daemon"
    "-v"
)

# Optional: Clear build cache if requested
if [ "$1" == "--clean" ]; then
    echo -e "${YELLOW}Cleaning build cache...${NC}"
    cd android
    ./gradlew clean
    ./gradlew cleanBuildCache
    cd ..
    flutter clean
fi

# Warm up Gradle daemon
echo -e "${GREEN}Warming up Gradle daemon...${NC}"
cd android
./gradlew --daemon
cd ..

# Pre-compile dependencies
echo -e "${GREEN}Pre-compiling dependencies...${NC}"
flutter pub get

# Build and run
echo -e "${GREEN}Building and running app...${NC}"
time flutter run -d $DEVICE ${BUILD_FLAGS[@]}