import Foundation
import Speech
import AVFoundation
import Combine

class SpeechRecognizer: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private var audioEngine = AVAudioEngine()
    
    @Published var transcribedText: String = ""
    @Published var isRecording: Bool = false
    
    // MARK: - 사용자 정의 사전
    @Published var customDictionary: [String: String] = [:] {
        didSet {
            saveCustomDictionary()
        }
    }
    private let dictionaryKey = "SpeechCustomDictionary"
    
    override init() {
        super.init()
        self.speechRecognizer?.delegate = self
        loadCustomDictionary()
    }
    
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioApplication.requestRecordPermission { _ in }
    }
    
    func startRecording() {
        // 기존 작업 완전히 정지 및 초기화
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        audioEngine = AVAudioEngine()
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // 🛑 [수정 1] 카메라와 충돌하는 .videoRecording 대신 .playAndRecord 사용
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
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
        guard recordingFormat.sampleRate > 0 else {
            print("유효하지 않은 오디오 포맷 샘플 레이트입니다.")
            return
        }
        
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
            return
        }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result = result {
                let rawText = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self?.transcribedText = self?.processRecognizedText(rawText) ?? rawText
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
        
        // 🛑 [수정 2 - 핵심] 오디오 세션을 비활성화하여 카메라 시스템으로 권한 완전 반환
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("AudioSession 비활성화 실패: \(error)")
        }
        
        let finalText = transcribedText
        DispatchQueue.main.async {
            self.isRecording = false
            self.transcribedText = ""
        }
        
        completion(finalText)
    }
    
    // MARK: - 사용자 정의 사전 저장 및 로드
    private func saveCustomDictionary() {
        UserDefaults.standard.set(customDictionary, forKey: dictionaryKey)
    }
    
    private func loadCustomDictionary() {
        if let savedDict = UserDefaults.standard.dictionary(forKey: dictionaryKey) as? [String: String] {
            self.customDictionary = savedDict
        } else {
            self.customDictionary = [
                "블럭": "BL",
                "블록": "BL",
                "균백": "균열및백태"
            ]
        }
    }
    
    // MARK: - 현장 맞춤형 텍스트 후처리
    func processRecognizedText(_ rawText: String) -> String {
        var text = rawText
        
        for (key, value) in customDictionary {
            text = text.replacingOccurrences(of: key, with: value)
        }
        
        let complexAlphabetMapping: [String: String] = [
            "엑스원": "X1", "엑스투": "X2", "엑스쓰리": "X3",
            "와이원": "Y1", "와이투": "Y2"
        ]
        for (key, value) in complexAlphabetMapping {
            text = text.replacingOccurrences(of: key, with: value)
        }
        
        let alphabetMapping: [String: String] = [
            "에이": "A", "비": "B", "씨": "C", "디": "D", "이": "E",
            "에프": "F", "지": "G", "에이치": "H", "아이": "I", "제이": "J",
            "케이": "K", "엘": "L", "엠": "M", "엔": "N", "오": "O",
            "피": "P", "큐": "Q", "알": "R", "에스": "S", "티": "T",
            "유": "U", "브이": "V", "더블유": "W", "엑스": "X", "와이": "Y", "제트": "Z"
        ]
        for (key, value) in alphabetMapping {
            text = text.replacingOccurrences(of: key, with: value)
        }
        
        let numberMapping: [String: String] = [
            "원": "1", "투": "2", "쓰리": "3", "포": "4", "파이브": "5",
            "식스": "6", "세븐": "7", "에잇": "8", "나인": "9", "텐": "10",
            "일": "1", "이": "2", "삼": "3", "사": "4", "오": "5",
            "육": "6", "칠": "7", "팔": "8", "구": "9", "십": "10"
        ]
        for (key, value) in numberMapping {
            text = text.replacingOccurrences(of: key, with: value)
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
