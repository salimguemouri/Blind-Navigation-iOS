//
//  SpeechDestination.swift
//  BlindNavigation
//
//  Created by Salim Guemouri on 21/12/2025.
//

import Foundation
import Speech
import AVFoundation
import Combine

final class SpeechDestination: NSObject, ObservableObject {
    @Published var transcript: String = ""
    @Published var isListening: Bool = false
    @Published var status: String = "Idle"

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
    private let audioEngine = AVAudioEngine()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var onFinal: ((String) -> Void)?

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                completion(authStatus == .authorized)
            }
        }
    }

    func startListening(onFinal: @escaping (String) -> Void) {
        guard !isListening else { return }
        transcript = ""
        status = "Starting…"
        self.onFinal = onFinal

        task?.cancel()
        task = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            status = "Audio session error: \(error.localizedDescription)"
            return
        }

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request = request else {
            status = "Could not create request"
            return
        }
        request.shouldReportPartialResults = true

        guard let recognizer = recognizer, recognizer.isAvailable else {
            status = "Speech recognizer not available"
            return
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            status = "Audio engine error: \(error.localizedDescription)"
            return
        }

        isListening = true
        status = "Listening…"

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result = result {
                DispatchQueue.main.async {
                    self.transcript = result.bestTranscription.formattedString
                }
                if result.isFinal {
                    self.finish()
                }
            }

            if error != nil {
                self.finish()
            }
        }
    }

    func stopListening() {
        guard isListening else { return }
        finish()
    }

    private func finish() {
        let finalText = transcript

        isListening = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        request?.endAudio()
        request = nil
        task = nil

        status = finalText.isEmpty ? "Stopped (no speech detected)" : "Stopped"

        DispatchQueue.main.async { [finalText] in
            self.onFinal?(finalText)
            self.onFinal = nil
        }
    }
}



