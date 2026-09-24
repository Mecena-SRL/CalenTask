import Foundation
import Speech
import AVFoundation
import Observation

/// Voice capture (S6/D66): dettatura on-device → testo nella cattura.
/// Italiano, offline quando il modello locale è disponibile.
@Observable @MainActor
final class SpeechCaptureService {
    static let shared = SpeechCaptureService()

    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var isAvailable = true

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private init() {}

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard status == .authorized else {
                    self?.isAvailable = false
                    return
                }
                self?.beginRecording()
            }
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognitionTask?.finish()
        recognitionTask = nil
        request = nil
        isRecording = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func beginRecording() {
        guard let recognizer, recognizer.isAvailable else {
            isAvailable = false
            return
        }
        transcript = ""

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device quando c'è: privacy e zero rete (anche sul set).
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stop()
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            stop()
            isAvailable = false
        }
    }
}
