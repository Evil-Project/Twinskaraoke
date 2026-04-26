#!/bin/bash
xcodebuild -project Twinskaraoke.xcodeproj -scheme Twinskaraoke -destination 'platform=iOS Simulator,name=iPhone 14' build | grep -i error
