import Foundation
import AVFoundation
import Photos
import UIKit
import Combine

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
    @Published var isReady: Bool = false
    @Published var zoomFactor: CGFloat = 1.0
    @Published var isTorchOn: Bool = false
    @Published var selectedRatio: AspectRatioOption = .ratio4_3
    
    // 수동으로 번호를 설정했는지 여부 체크
    private var isManualNumberSet: Bool = false
    
    // Combine 구독 저장용
    private var cancellables = Set<AnyCancellable>()
    
    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var videoDevice: AVCaptureDevice?
    
    override init() {
        super.init()
        setupSession()
        setupVolumeButtonHandler() // 볼륨 버튼 셔터 감지 설정
    }
    
    // MARK: - 볼륨 버튼 셔터 핸들러
    private func setupVolumeButtonHandler() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("AudioSession activation error: \(error)")
        }
        
        // 볼륨 키 변경 이벤트 수신
        audioSession.publisher(for: \.outputVolume)
            .dropFirst() // 앱 진입 시 초기값 반응 방지
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
            if !isManualNumberSet {
                self.fetchNextAvailableNumber()
            }
            self.startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    if !self.isManualNumberSet {
                        self.fetchNextAvailableNumber()
                    }
                    self.startSession()
                }
            }
        default:
            break
        }
    }
    
    // 사용자가 설정에서 시작 번호를 변경할 때 호출하는 메서드
    func setStartNumber(_ number: Int) {
        DispatchQueue.main.async {
            self.currentNumber = number
            self.isManualNumberSet = true // 수동 설정 상태로 변경 (앨범 자동 스캔으로 덮어쓰기 방지)
        }
    }
    
    private func fetchNextAvailableNumber() {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }
            
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            
            var maxNumber = 0
            let regex = try? NSRegularExpression(pattern: "IMG_(\\d{4})", options: .caseInsensitive)
            
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
                // 사용자가 수동으로 설정한 적이 없을 때만 앨범 기반 번호 설정
                if !self.isManualNumberSet && maxNumber > 0 {
                    self.currentNumber = maxNumber + 1
                }
            }
        }
    }
    
    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        
        self.videoDevice = device
        self.videoDeviceInput = input
        
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        
        session.commitConfiguration()
    }
    
    private func startSession() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async { self?.isReady = true }
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
    
    func setZoom(factor: CGFloat) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            let clampedFactor = max(1.0, min(factor, device.activeFormat.videoMaxZoomFactor))
            device.videoZoomFactor = clampedFactor
            self.zoomFactor = clampedFactor
            device.unlockForConfiguration()
        } catch {
            print("Zoom error: \(error)")
        }
    }
    
    // 지정한 화면 좌표(0.0 ~ 1.0)로 초점 및 노출 변경
    func focus(at devicePoint: CGPoint) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            
            // 초점(Focus) 설정
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            
            // 노출(Exposure) 설정
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
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        
        if let photoConnection = photoOutput.connection(with: .video) {
            let deviceOrientation = UIDevice.current.orientation
            if let videoOrientation = videoOrientationFrom(deviceOrientation) {
                photoConnection.videoOrientation = videoOrientation
            }
        }
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    private func videoOrientationFrom(_ deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation? {
        switch deviceOrientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return nil
        }
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
        
        // 1. 현재 번호를 즉시 가져오고, UI 상의 currentNumber는 딜레이 없이 즉각 +1 올려줍니다.
        let photoNumber = self.currentNumber
        DispatchQueue.main.async {
            self.currentNumber += 1
        }
        
        // 2. 백그라운드 이미지 크롭 및 저장 로직 진행
        let croppedImage = self.cropImageToRatio(originalImage, ratio: self.selectedRatio)
        guard let finalImageData = croppedImage.jpegData(compressionQuality: 0.95) else { return }
        
        let formattedName = String(format: "IMG_%04d.jpg", photoNumber)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(formattedName)
        
        do {
            try finalImageData.write(to: tempURL)
            
            PHPhotoLibrary.shared().performChanges({
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = formattedName
                
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, fileURL: tempURL, options: options)
            }) { success, error in
                try? FileManager.default.removeItem(at: tempURL)
                
                if let error = error {
                    print("Photo library save error: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Photo save error: \(error)")
        }
    }
}
