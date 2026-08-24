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
    
    // [추가] UI 연동용 75도 기울기 감지 상태 변수
    @Published var isPitchValid: Bool = false
    @Published var currentPitchAngle: Double = 0.0
    
    // 촬영 대기 중인 음성 노트 저장용
    private var pendingVoiceNote: String = ""
    
    // 순정 1x 배율에 해당하는 줌 인덱스 오프셋
    private var default1xZoomFactor: CGFloat = 1.0
    
    private var isManualNumberSet: Bool = false
    private var cancellables = Set<AnyCancellable>()
    
    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var videoDevice: AVCaptureDevice?
    
    private let motionManager = CMMotionManager()
    
    override init() {
        super.init()
        // 1번 코드의 동기적 스레드 초기화 방식을 적용하여 모션 및 카메라 동기화 안정화
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
        
        // [추가 및 보완] 75도 기울기 각도 계산 및 UI 바인딩 변수 업데이트
        let pitchRadians = atan2(y, sqrt(x * x + z * z))
        let pitchDegrees = abs(pitchRadians * 180.0 / .pi)
        
        DispatchQueue.main.async {
            self.currentPitchAngle = pitchDegrees
            // 75도 오차범위 ±5도 이내 감지 (70도 ~ 80도 사이)
            self.isPitchValid = abs(pitchDegrees - 75.0) <= 5.0
            
            if let newOrientation = newOrientation, newOrientation != self.customOrientation {
                self.customOrientation = newOrientation
            }
        }
    }
    
    private func setupVolumeButtonHandler() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.ambient, options: .mixWithOthers)
        
        audioSession.publisher(for: \.outputVolume)
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.capturePhoto()
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
    
    // 백그라운드 진입 후 복귀 시 프리뷰 복구용
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
    
    // 음성 노트(voiceNote) 지원 매개변수를 추가한 캡처 함수
    func capturePhoto(voiceNote: String = "") {
        self.pendingVoiceNote = voiceNote
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
        guard let imageData = photo.fileDataRepresentation(),
              let originalImage = UIImage(data: imageData) else { return }
        
        // 1. 촬영 시점의 접두어, 번호, 음성노트 스냅샷
        let currentPrefix = self.prefixText.trimmingCharacters(in: .whitespacesAndNewlines)
        let validPrefix = currentPrefix.isEmpty ? "IMG" : currentPrefix
        let photoNumber = self.currentNumber
        let note = self.pendingVoiceNote.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 다음 번호 미리 증가 및 사용 완료한 음성노트 초기화
        DispatchQueue.main.async {
            self.currentNumber += 1
            self.pendingVoiceNote = ""
        }
        
        // 2. 이미지 크롭 처리
        let croppedImage = self.cropImageToRatio(originalImage, ratio: self.selectedRatio)
        guard let finalImageData = croppedImage.jpegData(compressionQuality: 0.95) else { return }
        
        // 3. 파일명 포맷 생성
        let formattedName: String
        if note.isEmpty {
            formattedName = String(format: "%@_%04d.jpg", validPrefix, photoNumber)
        } else {
            formattedName = String(format: "%@_%04d(%@).jpg", validPrefix, photoNumber, note)
        }
        
        // 4. 임시 디렉토리에 해당 파일명으로 저장
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempFileURL = tempDirectory.appendingPathComponent(formattedName)
        
        do {
            try finalImageData.write(to: tempFileURL)
            
            // 5. Photos 라이브러리에 원본 파일명 옵션 지정 후 저장
            PHPhotoLibrary.shared().performChanges({
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = formattedName
                
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, fileURL: tempFileURL, options: options)
            }) { success, error in
                // 저장 완료 후 임시 파일 삭제
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

