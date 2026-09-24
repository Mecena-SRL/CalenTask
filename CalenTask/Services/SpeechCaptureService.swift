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
        guard !isRecording else { return }
        SFSpeechRecognizer.requestAuthorization(Self.authorizationHandler { [weak self] authorized in
            guard let self else { return }
            guard authorized else {
                self.isAvailable = false
                return
            }
            self.beginRecording()
        })
    }

    // Le callback di Speech e AVAudioEngine arrivano su thread di sistema:
    // costruite fuori dal MainActor (l'isolamento di default dell'app) non
    // fanno scattare il controllo d'isolamento, e rientrano con un Task.

    private nonisolated static func authorizationHandler(
        _ onMain: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void {
        { status in
            let authorized = status == .authorized
            Task { @MainActor in onMain(authorized) }
        }
    }

    private nonisolated static func tapBlock(
        feeding request: SFSpeechAudioBufferRecognitionRequest
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    private nonisolated static func resultHandler(
        _ onMain: @escaping @MainActor @Sendable (String?, Bool) -> Void
    ) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let finished = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in onMain(text, finished) }
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
        // Mac senza microfono (mini, Studio) o permesso negato: formato a
        // 0 Hz / 0 canali → installTap solleva un'eccezione e l'app crasha.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            self.request = nil
            isAvailable = false
            return
        }
        // Un tap rimasto da una sessione precedente → eccezione al secondo.
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format,
                             block: Self.tapBlock(feeding: request))

        recognitionTask = recognizer.recognitionTask(
            with: request,
            resultHandler: Self.resultHandler { [weak self] text, finished in
                guard let self else { return }
                if let text { self.transcript = text }
                if finished { self.stop() }
            }
        )

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
