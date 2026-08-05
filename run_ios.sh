#!/bin/bash
# Script to build and run iOS app on simulator
# This works around Flutter's code signing issue with Flutter.framework

cd "$(dirname "$0")"

echo "Building app with xcodebuild..."
cd ios
xcodebuild -workspace Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

if [ $? -eq 0 ]; then
  echo "Build succeeded! Installing and launching app..."
  
  # Find the built app
  APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Runner.app" -path "*/Debug-iphonesimulator/*" | head -1)
  
  if [ -n "$APP_PATH" ]; then
    echo "Found app at: $APP_PATH"
    
    # Boot simulator if needed
    xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || echo "Simulator already running"
    
    # Install app
    xcrun simctl install booted "$APP_PATH"
    
    # Launch app
    xcrun simctl launch booted com.buildahome.buildahome
    
    echo "App launched successfully!"
  else
    echo "Error: Could not find built app"
    exit 1
  fi
else
  echo "Build failed!"
  exit 1
fi


