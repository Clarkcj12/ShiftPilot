# ShiftPilot — Product Requirements Document

**Platform:** iOS 27.2 / CarPlay
**Audience:** Independent contractors (DoorDash, Uber, Lyft, Instacart, Shipt, Spark, etc.)

## 1. Objective

Give gig drivers an automated, zero-friction tool to track their true earnings, log tax-deductible mileage and manage vehicle expenses. The app acts as an automated business manager for independent contractors.

## 2. User stories

1. As a driver, I want the app to start tracking my miles automatically when my phone connects to my car, so I don't forget to log my tax deductions.
2. As a driver, I want to see my actual earnings per hour (EPH) across multiple gig apps, so I know which app pays best at different times of day.
3. As a driver, I want to scan my toll and parking receipts so they're added to my tax write-offs automatically.
4. As a driver, I want a live dashboard on my CarPlay screen, so I can monitor my shift safely while driving.

## 3. Core features

| Feature | Requirement | Status |
| --- | --- | --- |
| **Auto-Drive Detection** | Detect the car connection and start logging background GPS immediately. | ✅ Shipped. Uses the audio route, an optional BLE accessory and motion; see note A. Manual start/stop is also shipped. |
| **CarPlay Dashboard** | Distraction-free view of shift time, active miles and live deduction estimate. | ⏳ Not started. Needs an Apple entitlement; see note B. |
| **Multi-App Shift Tracking** | Log gross payouts tagged by platform; compute True EPH from active tracking time. | ✅ Shipped. Shifts, payouts by platform, live True EPH on the dashboard, and an Insights screen with EPH by platform and time of day. Trips recorded during a shift link to it automatically. |
| **IRS Tax Calculator & Vault** | Deductions at the IRS standard mileage rate, rolled up into a Quarterly Tax Vault. | ✅ Shipped. Business trips × the rate in effect on each trip's date (2026: 72.5¢ Jan–Jun, 76¢ from Jul 1). Estimated self-employment and income tax per IRS period, due dates, and recorded payments. Trips are classified business/personal (automatic during a shift). See note C. |

## 4. Value-add features

| Feature | Requirement | Status |
| --- | --- | --- |
| **Net Profit Engine** | Gross earnings minus estimated fuel (local gas price × car MPG) and wear-and-tear = True Net Profit. | ✅ Shipped (v1). User-entered MPG or L/100 km, fuel price and optional wear per mile/km in Settings → Vehicle. Each trip captures its cost when recorded, so price changes don't rewrite past shifts. Net profit and net per hour on the shift card, shift screen, dashboard and Insights. Live gas prices still need a backend; see note D. |
| **AI Expense Scanner** | Photograph receipts (car wash, tolls, phone bill); Vision extracts the total and adds it to deductions. | ⏳ Not started |
| **Maintenance Alerts** | Tie tracked miles to a service schedule (e.g. "5,000 gig miles: schedule oil change"). | ⏳ Not started |
| **Dead Mile Triage** | Swipe a completed trip segment to flag it as a Dead Mile (returning with no order); visualize unprofitable return zones on a map. | ⏳ Not started |

Also shipped (not in the original PRD): a Miles/Kilometers display setting.

## 5. Technical stack

- **Frameworks:** SwiftUI, SwiftData, CoreLocation (background tracking), CoreBluetooth (optional accessory), AVFoundation (car audio route), CoreMotion, CarPlay, Vision (receipt OCR), MapKit (routes, dead-mile map)
- **External APIs:** a local gas price provider (see note D)

## 6. Technical notes and PRD adjustments

**A. CoreBluetooth can't detect the car's infotainment system.**
Car head units connect over Classic Bluetooth (HFP/A2DP) or CarPlay, and CoreBluetooth only sees Bluetooth Low Energy devices. The app detects the car in other ways:
- the audio route changing to CarPlay or the car's Bluetooth audio, which is the main trigger
- automotive motion activity, which is the backup trigger
- significant-location-change wake-ups

CoreBluetooth is still used, but only for an optional BLE accessory such as an OBD-II dongle. Bluetooth headphones and car stereos look identical to iOS, so the user marks their car once in Settings.

**B. CarPlay needs an entitlement from Apple.**
A mileage and shift tracker fits CarPlay's **Driving Task** app category. Apps in it can only use CarPlay's built-in templates, such as lists, grids and information panels, with no custom drawing. That's enough for shift time, miles and an End Shift button.

Apple has to approve the request (developer.apple.com/carplay) before it will run on a real car, and approval requires a paid Apple Developer Program membership; a free Personal Team can't get it. Development can start in Xcode's CarPlay Simulator once the entitlement is granted.

**C. IRS mileage rates are published once a year, not in real time.**
The IRS sets the standard mileage rate per tax year, and occasionally changes it mid-year. The rates belong in a bundled, versioned table keyed by date, applied to each trip based on when it happened. Quarterly estimated-tax due dates are also fixed per year. Results should be shown as estimates with a "not tax advice" disclaimer.

**D. There is no Apple gas price API.**
Live local prices need a third-party provider, which usually requires a paid API key. Shipping that key in the app would expose it, so a small backend proxy is needed. For v1, a user-entered price per gallon or liter, plus the car's MPG, gives the same calculation with no backend. Live prices can be added later.

**E. Dead Mile Triage needs trip segments.**
"Driving back with no order" is a part of a trip, not a whole trip. It means splitting trips into segments, either automatically at stops or by the user marking pickup and drop-off, and storing them in a `TripSegment` model with a dead-mile flag. Shift tracking should come first, since segments make the most sense inside a shift.

## 7. Suggested build order

1. ~~**Shifts and earnings.**~~ Done.
2. ~~**IRS Tax Calculator & Quarterly Vault**~~ Done. Rates live in `TaxTables.swift`; update it each December.
3. ~~**Net Profit Engine**~~ Done with user-entered gas price and MPG; live prices later.
4. **AI Expense Scanner** (Vision text recognition and an `Expense` model).
5. **Maintenance Alerts** (odometer offset, service intervals, local notifications).
6. **Dead Mile Triage** (trip segments and a MapKit visualization).
7. **CarPlay Dashboard.** The code can be written any time, but it can't run in a car until Apple grants the entitlement.
