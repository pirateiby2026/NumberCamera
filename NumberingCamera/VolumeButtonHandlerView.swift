import SwiftUI
import MediaPlayer
import AVFoundation

struct VolumeButtonHandlerView: UIViewRepresentable {
    var onVolumeDownPressed: () -> Void
    var onVolumeUpPressed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onVolumeDownPressed: onVolumeDownPressed, onVolumeUpPressed: onVolumeUpPressed)
    }

    func makeUIView(context: Context) -> UIView {
        // iOS가 미사용 뷰로 오인하지 않도록 2x2 크기의 투명 컨테이너 생성
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        containerView.backgroundColor = .clear

        let volumeView = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        volumeView.alpha = 0.05
        volumeView.isUserInteractionEnabled = false
        
        containerView.addSubview(volumeView)

        // 내부 UISlider 감지 및 이벤트 등록
        if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            context.coordinator.setupSlider(slider)
        }

        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    // MARK: - Coordinator
    class Coordinator: NSObject {
        var onVolumeDownPressed: () -> Void
        var onVolumeUpPressed: () -> Void
        
        weak var slider: UISlider?
        private var isProcessing = false
        private var initialVolume: Float = 0.5
        private var lastTriggerTime = Date.distantPast

        init(onVolumeDownPressed: @escaping () -> Void, onVolumeUpPressed: @escaping () -> Void) {
            self.onVolumeDownPressed = onVolumeDownPressed
            self.onVolumeUpPressed = onVolumeUpPressed
            super.init()
        }

        func setupSlider(_ slider: UISlider) {
            self.slider = slider
            
            // 오디오 세션 카테고리 설정 (SpeechRecognizer와 옵션 통합)
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
                try session.setActive(true)
            } catch {
                print("AudioSession Setup Error: \(error)")
            }

            // 슬라이더 기준값(0.5) 고정
            slider.setValue(0.5, animated: false)
            initialVolume = 0.5

            // 물리 볼륨 버튼 조작 시 실시간 값 변경 감지
            slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        }

        func cleanup() {
            slider?.removeTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        }

        @objc private func sliderValueChanged(_ sender: UISlider) {
            let now = Date()
            // 0.4초 이내 연쇄 동작 차단
            guard !isProcessing, now.timeIntervalSince(lastTriggerTime) > 0.4 else { return }
            
            isProcessing = true
            lastTriggerTime = now

            let currentVolume = sender.value

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                if currentVolume > self.initialVolume {
                    self.onVolumeUpPressed()
                } else if currentVolume < self.initialVolume {
                    self.onVolumeDownPressed()
                } else {
                    self.onVolumeUpPressed()
                }

                // 연속 제어를 위해 슬라이더 값을 0.5로 재설정
                sender.setValue(0.5, animated: false)
                self.initialVolume = 0.5

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.isProcessing = false
                }
            }
        }
    }
}
