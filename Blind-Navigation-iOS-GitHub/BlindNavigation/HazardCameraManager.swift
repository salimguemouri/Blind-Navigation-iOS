import Foundation
import AVFoundation
import Vision
import CoreML
import ImageIO
import Combine
import QuartzCore
 
final class HazardCameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
 
    @Published var session = AVCaptureSession()
    @Published var detections: [HazardDetection] = []
    @Published var primaryDetection: HazardDetection?
    @Published var statusText: String = "Point the camera ahead and move slowly."
    @Published var permissionDenied = false
    @Published var cameraUnavailable = false
    @Published var voiceWarningsEnabled = true
    @Published var latestAnnouncement = ""
 
    private let sessionQueue = DispatchQueue(label: "blindnavigation.camera.session", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
 
    private var visionRequest: VNCoreMLRequest?
    private var isConfigured = false
    private var isProcessingFrame = false
    private var lastAnalysisTime: CFTimeInterval = 0
 
    private var stableFrameCount = 0
    private var lastCandidateKey = ""
    private var lastStableDetection: HazardDetection?
    private var lastSeenObstacleTime = Date.distantPast
    private var lastAnnouncementText = ""
    private var lastAnnouncementTime = Date.distantPast
 
    // FIX 9: Slightly faster frame analysis (~8 fps) for better responsiveness
    private let analysisInterval: CFTimeInterval = 0.12
 
    // Zones are defined in Vision's normalised coordinate space (origin bottom-left,
    // so y=0 is the bottom of the image as captured before orientation correction).
    // The values below were tuned for portrait hold with the phone pointing forward.
 
    // Broad watch area – catches objects entering the scene from the sides
    private let focusZone    = CGRect(x: 0.05, y: 0.08, width: 0.90, height: 0.84)
 
    // Main forward path
    private let priorityZone = CGRect(x: 0.15, y: 0.12, width: 0.70, height: 0.76)
 
    // Immediate danger corridor directly ahead
    private let stopZone     = CGRect(x: 0.24, y: 0.15, width: 0.52, height: 0.68)
 
    // FIX 11: Extended hazard vocabulary – all 80-class COCO labels YOLOv3 knows
    private let supportedHazards: Set<String> = [
        // People / animals
        "person", "dog", "cat",
        // Furniture / indoor obstacles
        "chair", "couch", "sofa", "bench", "bed",
        "dining table", "table",
        // Carried / dropped items (common trip hazards)
        "backpack", "handbag", "suitcase",
        "umbrella", "sports ball", "skateboard",
        // Plants / fixtures
        "potted plant", "fire hydrant", "stop sign",
        // Vehicles (relevant near pavements)
        "bicycle", "motorcycle", "car", "bus", "truck",
        // Large indoors objects
        "tv", "refrigerator", "toilet", "sink"
    ]
 
    override init() {
        super.init()
        prepareVisionModel()
    }
 
    func requestCameraAccessAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartSession()
 
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { self.permissionDenied = !granted }
                if granted { self.configureAndStartSession() }
            }
 
        default:
            DispatchQueue.main.async { self.permissionDenied = true }
        }
    }
 
    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
 
    func testVoice() {
        publishAnnouncement("Hazard scan is active. Voice warnings are working.", cooldown: 0.0)
    }
 
    // MARK: - Vision / CoreML
 
    private func prepareVisionModel() {
        guard let modelURL = Bundle.main.url(forResource: "YOLOv3TinyFP16", withExtension: "mlmodelc") else {
            DispatchQueue.main.async {
                self.cameraUnavailable = true
                self.statusText = "YOLO model not found in the app bundle."
            }
            return
        }
 
        do {
            let model = try MLModel(contentsOf: modelURL)
            let visionModel = try VNCoreMLModel(for: model)
 
            let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
                self?.handleVisionResults(request: request, error: error)
            }
 
            // FIX 10: centerCrop feeds the model a clean square without black-bar padding,
            // which better matches the square images YOLOv3 was trained on.
            request.imageCropAndScaleOption = .centerCrop
            self.visionRequest = request
 
        } catch {
            DispatchQueue.main.async {
                self.cameraUnavailable = true
                self.statusText = "Failed to load the hazard detection model."
            }
        }
    }
 
    // MARK: - Camera Setup
 
    private func configureAndStartSession() {
        sessionQueue.async {
            if self.session.isRunning { return }
 
            if self.isConfigured {
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.cameraUnavailable = false
                    self.statusText = "Scanning... move slowly and keep the camera pointed ahead."
                }
                return
            }
 
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
 
            for input  in self.session.inputs  { self.session.removeInput(input) }
            for output in self.session.outputs { self.session.removeOutput(output) }
 
            do {
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                           for: .video,
                                                           position: .back) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.cameraUnavailable = true
                        self.statusText = "Back camera not available."
                    }
                    return
                }
 
                do {
                    try camera.lockForConfiguration()
                    if camera.isFocusModeSupported(.continuousAutoFocus) {
                        camera.focusMode = .continuousAutoFocus
                    }
                    if camera.isExposureModeSupported(.continuousAutoExposure) {
                        camera.exposureMode = .continuousAutoExposure
                    }
                    if camera.isLowLightBoostSupported {
                        camera.automaticallyEnablesLowLightBoostWhenAvailable = true
                    }
                    camera.unlockForConfiguration()
                } catch { /* non-fatal */ }
 
                let input = try AVCaptureDeviceInput(device: camera)
                guard self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.cameraUnavailable = true
                        self.statusText = "Could not add camera input."
                    }
                    return
                }
                self.session.addInput(input)
 
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
 
                guard self.session.canAddOutput(self.videoOutput) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.cameraUnavailable = true
                        self.statusText = "Could not add video output."
                    }
                    return
                }
                self.session.addOutput(self.videoOutput)
 
                if let connection = self.videoOutput.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                }
 
                self.isConfigured = true
                self.session.commitConfiguration()
                self.session.startRunning()
 
                DispatchQueue.main.async {
                    self.cameraUnavailable = false
                    self.statusText = "Scanning... move slowly and keep the camera pointed ahead."
                }
 
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.cameraUnavailable = true
                    self.statusText = "Camera setup failed: \(error.localizedDescription)"
                }
            }
        }
    }
 
    // MARK: - Frame Capture
 
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
 
        guard let request = visionRequest else { return }
 
        let now = CACurrentMediaTime()
        guard now - lastAnalysisTime >= analysisInterval else { return }
        guard !isProcessingFrame else { return }
 
        lastAnalysisTime = now
        isProcessingFrame = true
 
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isProcessingFrame = false
            return
        }
 
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right,
            options: [:]
        )
 
        do {
            try handler.perform([request])
        } catch {
            isProcessingFrame = false
        }
    }
 
    // MARK: - Detection Processing
 
    private func handleVisionResults(request: VNRequest, error: Error?) {
        defer { isProcessingFrame = false }
        guard error == nil else { return }
 
        let observations = (request.results as? [VNRecognizedObjectObservation]) ?? []
 
        var filtered: [HazardDetection] = []
 
        for observation in observations {
            guard let topLabel = observation.labels.first else { continue }
 
            let label      = normalizeLabel(topLabel.identifier)
            let confidence = Double(topLabel.confidence)
            let box        = observation.boundingBox.standardized
            let area       = box.width * box.height
 
            guard supportedHazards.contains(label) else { continue }
 
            // FIX 4: Lower minimum area — catches objects ~2–3 m away
            guard area >= 0.008 else { continue }
 
            // FIX 1: Lower confidence thresholds — YOLOv3Tiny routinely scores 0.10–0.18
            // for genuine objects. Large objects get a little more leniency.
            let requiredConfidence: Double = area >= 0.06 ? 0.10 : 0.15
            guard confidence >= requiredConfidence else { continue }
 
            let focusOverlap    = overlapRatio(box, focusZone)
            let priorityOverlap = overlapRatio(box, priorityZone)
            let stopOverlap     = overlapRatio(box, stopZone)
 
            let centerDistance = abs(box.midX - 0.5)
            let centerScore    = 1.0 - min(Double(centerDistance) / 0.5, 1.0)
            let areaScore      = min(Double(area) / 0.18, 1.0)
 
            // FIX 2: Relaxed "is this object in the forward path" check.
            // The original required fairly large zone overlaps; many valid detections
            // near the edge of the corridor were silently dropped.
            let isInFront =
                stopOverlap    >= 0.005 ||
                priorityOverlap >= 0.015 ||
                focusOverlap   >= 0.05  ||
                (centerScore   >= 0.35 && area >= 0.02)
 
            guard isInFront else { continue }
 
            let dangerScore =
                (Double(stopOverlap)    * 0.35) +
                (Double(priorityOverlap) * 0.25) +
                (areaScore              * 0.28) +
                (centerScore            * 0.12)
 
            // FIX 3: Lower overall danger-score gate so medium-range objects pass through
            guard dangerScore >= 0.08 else { continue }
 
            filtered.append(HazardDetection(
                label: label,
                confidence: confidence,
                boundingBox: box,
                dangerScore: dangerScore,
                isInFront: isInFront,
                area: area
            ))
        }
 
        filtered.sort {
            if abs($0.dangerScore - $1.dangerScore) > 0.001 {
                return $0.dangerScore > $1.dangerScore
            } else {
                return $0.confidence > $1.confidence
            }
        }
 
        let now = Date()
        var displayPrimary: HazardDetection?
 
        if let candidate = filtered.first {
            let candidateKey = signature(for: candidate)
 
            if candidateKey == lastCandidateKey {
                stableFrameCount += 1
            } else {
                lastCandidateKey = candidateKey
                stableFrameCount = 1
            }
 
            lastSeenObstacleTime = now
 
            // Large / high-confidence obstacles announce immediately;
            // smaller ones still need just 2 consistent frames.
            if candidate.area >= 0.10 || candidate.dangerScore >= 0.55 || candidate.confidence >= 0.45 {
                lastStableDetection = candidate
            } else if stableFrameCount >= 2 {
                lastStableDetection = candidate
            }
 
            displayPrimary = lastStableDetection ?? candidate
 
        } else {
            stableFrameCount = 0
            lastCandidateKey = ""
 
            // FIX 6: Hold the last detection for 2.0 s (was 1.2 s) so speech has
            // time to fire before the detection disappears from state.
            if now.timeIntervalSince(lastSeenObstacleTime) < 2.0 {
                displayPrimary = lastStableDetection
            } else {
                lastStableDetection = nil
                displayPrimary = nil
            }
        }
 
        DispatchQueue.main.async {
            self.detections = Array(filtered.prefix(4))
            self.primaryDetection = displayPrimary
            self.updateState(using: displayPrimary)
        }
    }
 
    // MARK: - State & Announcements
 
    private func updateState(using primary: HazardDetection?) {
        let now = Date()

        guard let primary else {
            // If no stable obstacle is detected, update the scanner status only
            if now.timeIntervalSince(lastSeenObstacleTime) > 1.0 {
                statusText = "No obstacle detected ahead."
            } else {
                statusText = "Scanning... keep the camera pointed ahead."
            }
            return
        }

        // Tier 1: highest danger level, used for large or high-scoring obstacles
        if primary.area >= 0.16 || primary.dangerScore >= 0.70 {
            statusText = "Obstacle directly ahead — stop!"
            publishAnnouncement("Stop. Obstacle directly ahead.", cooldown: 1.5)

        // Tier 2: medium danger level, used for closer obstacles ahead
        } else if primary.area >= 0.07 || primary.dangerScore >= 0.42 {
            statusText = "Obstacle ahead. Move carefully."
            publishAnnouncement("Caution. Obstacle ahead.", cooldown: 2.0)

        // Tier 3: lower warning level, used when an object is detected ahead
        } else {
            let name = primary.label == "person" ? "someone" : "an obstacle"
            statusText = "Detected \(primary.label) ahead."
            publishAnnouncement("Be careful. \(name.capitalized) detected ahead.", cooldown: 3.0)
        }
    }
 
    private func publishAnnouncement(_ text: String, cooldown: TimeInterval) {
        guard voiceWarningsEnabled else { return }
 
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
 
        let now = Date()
        if cleaned == lastAnnouncementText,
           now.timeIntervalSince(lastAnnouncementTime) < cooldown {
            return
        }
 
        lastAnnouncementText = cleaned
        lastAnnouncementTime = now
 
        DispatchQueue.main.async {
            self.latestAnnouncement = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                self.latestAnnouncement = cleaned
            }
        }
    }
 
    // MARK: - Helpers
 
    // FIX 5: Coarser signature grid (2 × 3 instead of 3 × 4) so minor camera
    // wobble does not reset the stability counter and block announcements.
    private func signature(for detection: HazardDetection) -> String {
        let xBin    = Int(detection.boundingBox.midX * 2.0)
        let yBin    = Int(detection.boundingBox.midY * 3.0)
        let areaBin = Int(detection.area * 15.0)
        return "\(detection.label)-\(xBin)-\(yBin)-\(areaBin)"
    }
 
    private func normalizeLabel(_ raw: String) -> String {
        let cleaned = raw
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
 
        switch cleaned {
        case "diningtable":   return "dining table"
        case "pottedplant":   return "potted plant"
        case "tvmonitor":     return "tv"
        case "sofa":          return "sofa"
        case "firehydrant":   return "fire hydrant"
        case "stopsign":      return "stop sign"
        default:              return cleaned
        }
    }
 
    private func overlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let aArea = a.width * a.height
        guard aArea > 0 else { return 0 }
        return intersectionArea / aArea
    }
}
