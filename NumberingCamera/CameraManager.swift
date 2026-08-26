import Foundation
import AVFoundation
import Photos
import UIKit
import Combine
import CoreMotion

enum AspectRatioOption: String, CaseIterable, Identifiable {
    case ratio4_3 = "4:3"
    case ratio16_9 = "16:9"
    case ratio1_1 = "1:1"
    
    var id: String { self.rawValue }
    
    var ratioValue: CGFloat {
        switch self {
        case .ratio4_3: return 3.0 / 4.0
        case .ratio16_9: return 9.0 / 16.0
        case .ratio1_1: return 1.0 / 1.0
        }
    }
}

class CameraManager: NSObject, ObservableObject {
    @Published var currentNumber: Int = 1
    @Published var prefixText: String = "IMG" // 사진 접두사 (기본값: IMG)
    @Published var isReady: Bool = false
    @Published var zoomFactor: CGFloat = 1.0
    @Published var minZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 5.0
    @Published var isTorchOn: Bool = false
    @Published var selectedRatio: AspectRatioOption = .ratio4_3
    @Published var customOrientation: AVCaptureVideoOrientation = .portrait
    
    // MARK: - UserDefaults 키 정의 및 연동 키워드 프로퍼티
    private let shotKeywordKey = "SavedShotKeyword"
    private let blankKeywordKey = "SavedBlankKeyword"
    
    // SettingsView 및 SpeechManager 연동용 커스텀 키워드 프로퍼티 (didSet으로 자동 저장)
    @Published var shotKeyword: String = "샷" {
        didSet {
            UserDefaults.standard.set(shotKeyword, forKey: shotKeywordKey)
        }
    }
    @Published var blankKeyword: String = "공백" {
        didSet {
            UserDefaults.standard.set(blankKeyword, forKey: blankKeywordKey)
        }
    }
    
    // 볼륨 Down 버튼 감지 시 마이크 활성화를 위한 이벤트 퍼블리셔
    let volumeDownPressed = PassthroughSubject<Void, Never>()
    
    // UI 연동용 75도 기울기 감지 상태 변수
    @Published var isPitchValid: Bool = false
    @Published var currentPitchAngle: Double = 0.0
    
    // 촬영 대기 중인 음성 노트 저장용
    private var pendingVoiceNote: String = ""
    
    // 순정 1x 배율에 해당하는 줌 인덱스 오프셋
    private var default1xZoomFactor: CGFloat = 1.0
    
    private var isManualNumberSet: Bool = false
    private var cancellables = Set<AnyCancellable>()
    
    // 볼륨키 중복 제어 및 볼륨 Up/Down 판별용 변수
    private var previousVolume: Float = 0.5
    private var lastCaptureTime: Date = Date.distantPast
    
    // 비동기 사진 저장 동기화를 위한 메타데이터 큐
    private struct PhotoRequest {
        let number: Int
        let prefix: String
        let voiceNote: String
    }
    private var pendingRequests: [PhotoRequest] = []
    
    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var videoDevice: AVCaptureDevice?
    
    private let motionManager = CMMotionManager()
    
    override init() {
        super.init()
        
        // 앱 실행 시 UserDefaults에 저장된 키워드 로드
        if let savedShot = UserDefaults.standard.string(forKey: shotKeywordKey) {
            self.shotKeyword = savedShot
        }
        if let savedBlank = UserDefaults.standard.string(forKey: blankKeywordKey) {
            self.blankKeyword = savedBlank
        }
        
        setupSession()
        setupVolumeButtonHandler()
        startMotionUpdates()
    }
    
    deinit {
        motionManager.stopAccelerometerUpdates()
    }
    
    // MARK: - 75도 기울기 감지
    private func startMotionUpdates() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.1
        
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let data = data, error == nil else { return }
            self?.processAccelerometerData(data.acceleration)
        }
    }
    
    private func processAccelerometerData(_ acceleration: CMAcceleration) {
        let x = acceleration.x
        let y = acceleration.y
        let z = acceleration.z
        
        let threshold = sin(75.0 * .pi / 180.0) // 75도 (약 0.9659)
        
        var newOrientation: AVCaptureVideoOrientation?
        
        if y < -threshold {
            newOrientation = .portrait
        } else if y > threshold {
            newOrientation = .portraitUpsideDown
        } else if x < -threshold {
            newOrientation = .landscapeRight
        } else if x > threshold {
            newOrientation = .landscapeLeft
        }
        
        let pitchRadians = atan2(y, sqrt(x * x + z * z))
        let pitchDegrees = abs(pitchRadians * 180.0 / .pi)
        
        DispatchQueue.main.async {
            self.currentPitchAngle = pitchDegrees
            self.isPitchValid = abs(pitchDegrees - 75.0) <= 5.0
            
            if let newOrientation = newOrientation, newOrientation != self.customOrientation {
                self.customOrientation = newOrientation
            }
        }
    }
    
    // MARK: - 볼륨 버튼 감지 (이중 촬영 방지 보완)
    private func setupVolumeButtonHandler() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.ambient, options: .mixWithOthers)
        
        self.previousVolume = audioSession.outputVolume
        
        audioSession.publisher(for: \.outputVolume)
            .dropFirst()
            .sink { [weak self] newVolume in
                guard let self = self else { return }
                
                let now = Date()
                // 0.5초 이내 연쇄 이벤트 무시
                guard now.timeIntervalSince(self.lastCaptureTime) > 0.5 else { return }
                self.lastCaptureTime = now
                
                let isUp = newVolume > self.previousVolume
                self.previousVolume = newVolume
                
                DispatchQueue.main.async {
                    if !isUp {
                        // 🛑 [중요] 볼륨 DOWN인 경우에만 마이크 활성화 이벤트 전송
                        // 볼륨 UP 처리 시 직접 capturePhoto()를 호출하던 것을 제거하여 VolumeButtonHandlerView와의 중복 촬영을 차단함
                        self.volumeDownPressed.send()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            if !self.isManualNumberSet { self.fetchNextAvailableNumber() }
            self.startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    if !self.isManualNumberSet { self.fetchNextAvailableNumber() }
                    self.startSession()
                }
            }
        default:
            break
        }
    }
    
    func resumeSession() {
        startSession()
    }
    
    func setStartNumber(_ number: Int, prefix: String) {
        DispatchQueue.main.async {
            self.currentNumber = number
            self.prefixText = prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "IMG" : prefix
            self.isManualNumberSet = true
        }
    }
    
    private func fetchNextAvailableNumber() {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }
            
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            
            var maxNumber = 0
            let regex = try? NSRegularExpression(pattern: ".*_(\\d{4})", options: .caseInsensitive)
            
            let countToScan = min(fetchResult.count, 100)
            for i in 0..<countToScan {
                let asset = fetchResult.object(at: i)
                let resources = PHAssetResource.assetResources(for: asset)
                for resource in resources {
                    let filename = resource.originalFilename
                    let nsRange = NSRange(location: 0, length: filename.utf16.count)
                    if let match = regex?.firstMatch(in: filename, options: [], range: nsRange) {
                        if let range = Range(match.range(at: 1), in: filename) {
                            if let num = Int(filename[range]), num > maxNumber {
                                maxNumber = num
                            }
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                if !self.isManualNumberSet && maxNumber > 0 {
                    self.currentNumber = maxNumber + 1
                }
            }
        }
    }
    
    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInWideAngleCamera
        ]
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .back
        )
        
        guard let device = discoverySession.devices.first,
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        
        self.videoDevice = device
        self.videoDeviceInput = input
        
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        
        session.commitConfiguration()
        
        let switchFactors = device.virtualDeviceSwitchOverVideoZoomFactors
        if !switchFactors.isEmpty {
            self.default1xZoomFactor = CGFloat(truncating: switchFactors[0])
        } else {
            self.default1xZoomFactor = 1.0
        }
        
        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = min(10.0, device.maxAvailableVideoZoomFactor)
        
        DispatchQueue.main.async {
            self.minZoomFactor = minZoom
            self.maxZoomFactor = maxZoom
            self.setZoom(factor: self.default1xZoomFactor)
        }
    }
    
    private func startSession() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async {
                self?.isReady = true
            }
        }
    }
    
    func toggleTorch() {
        guard let device = videoDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if device.torchMode == .on {
                device.torchMode = .off
                self.isTorchOn = false
            } else {
                try device.setTorchModeOn(level: 1.0)
                self.isTorchOn = true
            }
            device.unlockForConfiguration()
        } catch {
            print("Torch error: \(error)")
        }
    }
    
    func cycleAspectRatio() {
        switch selectedRatio {
        case .ratio4_3: selectedRatio = .ratio16_9
        case .ratio16_9: selectedRatio = .ratio1_1
        case .ratio1_1: selectedRatio = .ratio4_3
        }
    }
    
    var displayZoomFactor: CGFloat {
        if default1xZoomFactor > 1.0 {
            return zoomFactor / default1xZoomFactor
        }
        return zoomFactor
    }
    
    func setDisplayZoom(displayFactor: CGFloat) {
        let targetZoom = displayFactor * default1xZoomFactor
        setZoom(factor: targetZoom)
    }
    
    func setZoom(factor: CGFloat) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            let clampedFactor = max(minZoomFactor, min(factor, maxZoomFactor))
            device.videoZoomFactor = clampedFactor
            self.zoomFactor = clampedFactor
            device.unlockForConfiguration()
        } catch {
            print("Zoom error: \(error)")
        }
    }
    
    func focus(at devicePoint: CGPoint) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .continuousAutoExposure
            }
            
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        } catch {
            print("Focus error: \(error)")
        }
    }
    
    // MARK: - 사진 캡처 (눌린 시점의 번호 즉시 증가 및 동기화)
    func capturePhoto(voiceNote: String = "") {
        let currentPrefix = self.prefixText.trimmingCharacters(in: .whitespacesAndNewlines)
        let validPrefix = currentPrefix.isEmpty ? "IMG" : currentPrefix
        let targetNumber = self.currentNumber
        
        // 셔터 누른 즉시 번호 1 증가 (UI 동기화 문제 해결)
        self.currentNumber += 1
        
        // 해당 촬영 요청건에 대한 메타데이터 큐에 등록
        let request = PhotoRequest(number: targetNumber, prefix: validPrefix, voiceNote: voiceNote)
        pendingRequests.append(request)
        
        let settings = AVCapturePhotoSettings()
        if let photoConnection = photoOutput.connection(with: .video) {
            photoConnection.videoOrientation = customOrientation
        }
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    private func cropImageToRatio(_ image: UIImage, ratio: AspectRatioOption) -> UIImage {
        guard ratio != .ratio4_3, let cgImage = image.cgImage else { return image }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        var targetWidth = width
        var targetHeight = height
        
        if ratio == .ratio1_1 {
            let minDim = min(width, height)
            targetWidth = minDim
            targetHeight = minDim
        } else if ratio == .ratio16_9 {
            if height > width {
                targetHeight = width * (16.0 / 9.0)
                if targetHeight > height {
                    targetHeight = height
                    targetWidth = height * (9.0 / 16.0)
                }
            } else {
                targetWidth = height * (16.0 / 9.0)
                if targetWidth > width {
                    targetWidth = width
                    targetHeight = width * (9.0 / 16.0)
                }
            }
        }
        
        let cropRect = CGRect(
            x: (width - targetWidth) / 2.0,
            y: (height - targetHeight) / 2.0,
            width: targetWidth,
            height: targetHeight
        )
        
        if let croppedCgImage = cgImage.cropping(to: cropRect) {
            return UIImage(cgImage: croppedCgImage, scale: image.scale, orientation: image.imageOrientation)
        }
        
        return image
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard !pendingRequests.isEmpty else { return }
        let request = pendingRequests.removeFirst()
        
        guard let imageData = photo.fileDataRepresentation(),
              let originalImage = UIImage(data: imageData) else { return }
        
        let note = request.voiceNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let croppedImage = self.cropImageToRatio(originalImage, ratio: self.selectedRatio)
        guard let finalImageData = croppedImage.jpegData(compressionQuality: 0.95) else { return }
        
        let formattedName: String
        if note.isEmpty {
            formattedName = String(format: "%@_%04d.jpg", request.prefix, request.number)
        } else {
            formattedName = String(format: "%@_%04d(%@).jpg", request.prefix, request.number, note)
        }
        
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempFileURL = tempDirectory.appendingPathComponent(formattedName)
        
        do {
            try finalImageData.write(to: tempFileURL)
            
            PHPhotoLibrary.shared().performChanges({
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = formattedName
                
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, fileURL: tempFileURL, options: options)
            }) { success, error in
                try? FileManager.default.removeItem(at: tempFileURL)
                
                if let error = error {
                    print("사진 저장 실패: \(error.localizedDescription)")
                } else {
                    print("사진 저장 성공: \(formattedName)")
                }
            }
        } catch {
            print("임시 파일 생성 실패: \(error)")
        }
    }
}
