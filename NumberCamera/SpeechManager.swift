import Foundation
import Speech
import AVFoundation
import Combine

class SpeechRecognizer: NSObject, ObservableObject {
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    @Published var transcribedText: String = ""
    @Published var isRecording: Bool = false
    
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioApplication.requestRecordPermission { _ in }
    }
    
    func startRecording() {
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // 카메라 비디오 세션과 마이크 충돌을 방지하기 위해 mixWithOthers 옵션 사용
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .mixWithOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("AudioSession 설정 실패: \(error)")
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // 기존 Tap 안전 제거 후 재등록
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.transcribedText = ""
                self.isRecording = true
            }
        } catch {
            print("AudioEngine 시작 실패: \(error)")
        }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result = result {
                DispatchQueue.main.async {
                    self?.transcribedText = result.bestTranscription.formattedString
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                self?.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self?.recognitionRequest = nil
                self?.recognitionTask = nil
            }
        }
    }
    
    func stopRecording(completion: @escaping (String) -> Void) {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        
        let finalText = transcribedText
        DispatchQueue.main.async {
            self.isRecording = false
            self.transcribedText = ""
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        // 세션 비활성화 시 다른 기능(카메라 등)에 알림을 주어 정상 복구 유도
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        
        completion(finalText)
    }
}
