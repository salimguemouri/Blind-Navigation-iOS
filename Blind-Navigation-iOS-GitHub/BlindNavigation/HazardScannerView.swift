import SwiftUI
import AVFoundation
 
struct HazardScannerView: View {
    @Environment(\.dismiss) private var dismiss
 
    @StateObject private var cameraManager = HazardCameraManager()
    @StateObject private var promptSpeaker = PromptSpeaker()
 
    var body: some View {
        ZStack {
            CameraPreview(session: cameraManager.session)
                .ignoresSafeArea()
 
            LinearGradient(
                colors: [
                    Color.black.opacity(0.25),
                    Color.clear,
                    Color.black.opacity(0.35)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
 
            VStack {
                topBar
                Spacer()
                bottomPanel
            }
            .padding()
        }
        .onAppear {
            cameraManager.requestCameraAccessAndStart()
            promptSpeaker.speak(
                "Hazard scan started. Point the camera ahead and move slowly.",
                interrupt: true,
                minimumGap: 0.0
            )
        }
        .onDisappear {
            cameraManager.stopSession()
            promptSpeaker.stop()
        }
        .onChange(of: cameraManager.latestAnnouncement) { newValue in
            guard !newValue.isEmpty else { return }
            // FIX: Reduced from 1.6 s to 1.0 s — the publishAnnouncement cooldowns
            // in HazardCameraManager already prevent spam, so the extra 1.6 s gap
            // here was causing the user to miss or receive warnings too late.
            promptSpeaker.speak(newValue, interrupt: false, minimumGap: 1.0)
        }
        .onChange(of: cameraManager.voiceWarningsEnabled) { newValue in
            promptSpeaker.setEnabled(newValue)
        }
        .alert("Camera access needed", isPresented: $cameraManager.permissionDenied) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please allow camera access in Settings so Hazard Scan can work.")
        }
    }
 
    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }
 
            Spacer()
 
            Text("Hazard Scan")
                .font(.largeTitle.bold())
                .foregroundColor(.white)
 
            Spacer()
 
            Button {
                cameraManager.voiceWarningsEnabled.toggle()
            } label: {
                Image(systemName: cameraManager.voiceWarningsEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }
        }
        .padding(.top, 8)
    }
 
    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(cameraManager.voiceWarningsEnabled ? "Voice warnings on" : "Voice warnings off")
                    .font(.title2.bold())
                    .foregroundColor(.white)
 
                Spacer()
 
                Button(cameraManager.voiceWarningsEnabled ? "Pause Voice" : "Enable Voice") {
                    cameraManager.voiceWarningsEnabled.toggle()
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
            }
 
            Text("Scanning... move slowly and keep the camera pointed ahead.")
                .font(.title3)
                .foregroundColor(.white.opacity(0.92))
 
            Text(cameraManager.statusText)
                .font(.largeTitle.weight(.semibold))
                .foregroundColor(.white)
 
            if let primary = cameraManager.primaryDetection {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Detected: \(primary.label.capitalized)")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.95))
 
                    Text("Confidence: \(Int(primary.confidence * 100))%")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            } else {
                Text("No obstacle detected yet.")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.85))
            }
 
            Button("Test Voice") {
                cameraManager.testVoice()
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
 
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
 
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
 
    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}
 
final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }
 
    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
 
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
 
        if let connection = previewLayer.connection,
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
}
