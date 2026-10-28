# ShiftPilot

Mileage logging for gig drivers. ShiftPilot notices when you get in your car and records GPS mileage in the background, with no taps needed.

See [docs/PRD.md](docs/PRD.md) for the product requirements, feature status and roadmap.

- iOS 27.2+, SwiftUI, SwiftData, Swift 6 strict concurrency
- Project generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Getting started

```sh
brew install xcodegen   # once
xcodegen generate
open ShiftPilot.xcodeproj
```

The `.xcodeproj` is generated and git-ignored. Edit `project.yml` instead, and re-run `xcodegen generate` after adding or removing files.

Run the tests:

```sh
xcodebuild test -scheme ShiftPilot -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Architecture

```
ShiftPilot/
  App/          ShiftPilotApp, AppDelegate (background relaunch entry point), AppEnvironment (DI)
  Core/         Permissions, Persistence (SwiftData Trip/TripPoint, KnownDevicesStore), Logging
  Features/
    AutoDrive/  AutoDriveDetectionManager, DriveDetector (pure state machine), Signals/
    Mileage/    MileageTracker (background GPS), TripRecorder (SwiftData writes)
    Dashboard/  Dashboard + trip list
    Settings/   Permissions, car devices, BLE accessory pairing
```

## Auto-Drive Detection

### Why not CoreBluetooth for the car?

Car infotainment systems connect to iPhones over **Classic Bluetooth** (HFP for calls, A2DP for audio) or **CarPlay**. CoreBluetooth only talks to **Bluetooth Low Energy** devices, and iOS doesn't expose Classic connections to it, so CoreBluetooth can't see the car connect.

ShiftPilot combines several signals instead:

| Signal | Source | Role |
| --- | --- | --- |
| CarPlay / car Bluetooth audio | `AVAudioSession` route (`.carAudio`, `.bluetoothA2DP`, `.bluetoothHFP`, `.bluetoothLE`) | Main trigger. Starts a trip immediately. |
| BLE accessory (OBD-II dongle) | CoreBluetooth with state restoration | Optional trigger. iOS relaunches the app when it connects. |
| Automotive motion | `CMMotionActivityManager` | Backup trigger for cars with no Bluetooth. Confirmed by GPS speed. |
| Significant location change | `CLLocationManager` | Wakes or relaunches the app so the signals above get re-checked. |

Bluetooth headphones and car head units look the same to the audio route API. A Bluetooth audio device therefore only counts as a car after the user marks it in **Settings → Car Bluetooth**. CarPlay is always treated as a car.

### State machine

`DriveDetector.reduce` is a pure function, so it can be unit-tested without hardware:

```
idle ──car connected─────────────────────────────▶ driving
idle ──automotive motion──▶ candidate ──≥15 mph for 60 s──▶ driving
candidate ──5 min without reaching speed──▶ idle (trip discarded)
driving ──car + motion signals lost──▶ ending ──parked ≥3 min──▶ idle (trip saved)
ending ──car reconnects / automotive again──▶ driving
```

All thresholds are in `DetectionConfig`.

**Manual override.** The dashboard has a **Start trip** / **End trip** button:
- A manually started trip only ends when you tap **End trip**.
- **End trip** works on any trip. After it, auto-start is held off until the car disconnects and motion stops, so a car that's still connected doesn't immediately start a new trip.

### Background GPS

`MileageTracker` opens a `CLBackgroundActivitySession` and iterates `CLLocationUpdate.liveUpdates(.automotiveNavigation)`. Before summing distance it filters out three kinds of point:
- poor accuracy (more than 50 m)
- impossible jumps (more than about 155 mph)
- jitter (steps under 10 m)

A motion-only trip stays in memory until it's confirmed, so false starts never reach the database.

### Info.plist

| Key | Why |
| --- | --- |
| `NSLocationWhenInUseUsageDescription` / `NSLocationAlwaysAndWhenInUseUsageDescription` | GPS mileage. Always is needed for background relaunch. |
| `NSBluetoothAlwaysUsageDescription` | Optional BLE accessory. Only prompted when the user pairs one. |
| `NSMotionUsageDescription` | Automotive activity detection |
| `UIBackgroundModes`: `location`, `bluetooth-central` | Background GPS sessions and BLE state restoration |

## Testing on a device

The simulator can't test Bluetooth or CarPlay routes, or motion activity, so use a real device:

1. Grant **Always** location and Motion. Connect to the car's Bluetooth, then go to **Settings** and mark it as your car.
2. Lock the phone and drive. A trip should start within seconds, and the blue location indicator should appear.
3. Park and turn the car off. The trip should end about 3 minutes later.
4. Force-quit the app and drive again. The significant-change relaunch should pick the drive up after roughly 500 m.

Logs: Console.app, filtered to `subsystem:com.shiftpilot`.
