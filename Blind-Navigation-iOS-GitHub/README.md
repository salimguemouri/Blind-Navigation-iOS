# Blind Navigation Assistance — iOS

An iOS accessibility-focused final-year engineering project exploring how voice interaction, pedestrian routing, and on-device object detection can support navigation in unfamiliar environments for people with visual impairments.

> **Academic prototype — not a certified mobility or safety aid.** Object detection and GPS can miss obstacles or provide inaccurate positioning. Do not rely on this application as a replacement for a white cane, guide dog, or other established mobility support.

## Overview

The application combines a spoken destination interface, walking directions, a live route map, and camera-based obstacle warnings. It was developed using Swift and SwiftUI, integrating Apple's MapKit, Core Location, Speech, AVFoundation, Vision and Core ML frameworks.

## Features

- **Voice destination input:** converts spoken place names or postcodes into text using Apple's Speech framework.
- **Walking route planning:** uses MapKit to find a pedestrian route and generate turn-by-turn steps.
- **Spoken guidance:** announces route instructions and supports voice commands such as *next*, *previous*, *repeat* and *stop*.
- **Live positioning:** uses Core Location to estimate distance to the current route step, with automatic step advancement near a waypoint (12 m threshold).
- **Live route map:** displays the route, destination, estimated travel time and user-following map.
- **Camera hazard scanning:** runs a YOLOv3 Tiny FP16 Core ML model through Vision to identify selected objects such as people, vehicles, furniture and bags.
- **Prioritised warnings:** filters detections using confidence, image area, position within forward-facing zones and temporal stability, then produces spoken warnings.

## Technology

| Area | Implementation |
| --- | --- |
| Language and UI | Swift, SwiftUI |
| Routing and mapping | MapKit |
| Location | Core Location |
| Voice input | Speech framework, AVAudioEngine |
| Voice output | AVSpeechSynthesizer |
| Camera | AVFoundation |
| Object recognition | Vision, Core ML, YOLOv3 Tiny FP16 |

## Project structure

```text
BlindNavigation.xcodeproj/          Xcode project configuration
BlindNavigation/
  BlindNavigationApp.swift          Application entry point
  ContentView.swift                 Navigation UI and route guidance
  LiveLocation.swift                GPS and permission handling
  SpeechDestination.swift           Speech-to-text destination input
  NavigationMapView.swift           MapKit route presentation
  HazardScannerView.swift           Camera scanner interface
  HazardCameraManager.swift         Camera capture and object detection
  HazardDetection.swift             Hazard data model
  PromptSpeaker.swift               Spoken hazard alerts
  YOLOv3TinyFP16.mlmodel            Core ML object-detection model
```

## Getting started

1. Clone or download this repository onto a Mac with a compatible version of Xcode.
2. Open `BlindNavigation.xcodeproj`.
3. Check the iOS deployment target in the project settings (the uploaded project specifies **iOS 26.2**) and use a compatible iPhone and Xcode version.
4. Check the project's signing team and bundle identifier, and set your own signing configuration if needed.
5. Confirm that `YOLOv3TinyFP16.mlmodel` is included in the app target and compiled into the app bundle.
6. Build and run on a **physical iPhone** for camera-based detection and meaningful GPS testing.
7. Grant camera, microphone, speech recognition and location permissions when requested.

The project settings already include purpose strings for those four permissions. The original upload did not include an asset catalog; if Xcode reports missing app-icon or accent-colour assets, add an `Assets.xcassets` catalog or adjust the asset settings.

**Build status:** This repository has been assembled from the supplied files, but has not been compiled or run in Xcode in this environment.

## How it works

**Navigation:** The user starts location tracking, speaks a destination and requests a walking route. MapKit returns route steps, which can be read aloud. Location updates are used to estimate the distance to the current step endpoint.

**Hazard detection:** Camera frames are analysed approximately every 0.12 seconds. Vision passes images to the Core ML model. The app filters object predictions using a minimum bounding-box area, confidence thresholds, overlap with forward-facing zones and a combined danger score. It applies short-term detection stabilisation and spoken-alert cooldowns to reduce repeated warnings.

## Testing and limitations

During project testing, recorded observations included:

| Test | Recorded result |
| --- | --- |
| Person detection | 10/10 trials |
| Car detection | 8/10 trials |
| Backpack detection | 9/10 trials |
| Cat detection | 9/10 trials |
| Stationary GPS variation | Approximately 3–5 m |
| Walking GPS variation | Approximately 10–15 m |

These are limited project-level observations, **not** evidence of generalised reliability or safe independent use. Performance depends on lighting, camera position, object type, occlusion, GPS conditions and device capabilities. The model cannot detect every physical hazard (for example, drop-offs or some transparent obstacles), and image-based detection does not establish real-world distance.

## Future improvements

- Test with a wider range of environments, lighting conditions and accessibility scenarios.
- Improve hazard-distance estimation and add additional sensor fusion where available.
- Refine audio-session coordination between voice recognition and spoken guidance.
- Improve recovery from missed GPS waypoints and route deviations.
- Conduct structured accessibility and usability evaluations with appropriate safety supervision.

## Author

Final-year Electrical and Electronic Engineering project. Developed as an academic prototype to explore accessible mobile navigation and embedded machine-learning techniques.

## Model and attribution

The repository includes the supplied `YOLOv3TinyFP16.mlmodel` model file. **Before publishing publicly, verify the model's source and redistribution licence**, and add the required attribution or replace it with a documented, redistributable model. No licence for the overall project is asserted here; add one only after deciding how you want others to reuse the code.
