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
        // 🛑 [중요] 화면 좌측 상단 (0,0) 위치에 2x2 크기로 배치 (iOS가 보이지 않는 뷰로 인식하지 못하게 함)
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        containerView.backgroundColor = .clear

        let volumeView = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        volumeView.alpha = 0.05 // opacity를 너무 낮추지 않고 0.05로 유지
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

        init(onVolumeDownPressed: @escaping () -> Void, onVolumeUpPressed: @escaping () -> Void) {
            self.onVolumeDownPressed = onVolumeDownPressed
            self.onVolumeUpPressed = onVolumeUpPressed
            super.init()
        }

        func setupSlider(_ slider: UISlider) {
            self.slider = slider
            
            // 오디오 세션 활성화
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .mixWithOthers])
                try session.setActive(true)
            } catch {
                print("AudioSession Setup Error: \(error)")
            }

            // 슬라이더 값을 중간(0.5)으로 고정
            slider.setValue(0.5, animated: false)
            initialVolume = 0.5

            // 슬라이더 값 변경 감지 (물리 버튼 작동 시 UISlider 값이 즉시 변경됨)
            slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        }

        func cleanup() {
            slider?.removeTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        }

        @objc private func sliderValueChanged(_ sender: UISlider) {
            guard !isProcessing else { return }
            isProcessing = true

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

                // 연속 연타를 위해 다시 슬라이더 값을 0.5로 즉시 원복
                sender.setValue(0.5, animated: false)
                self.initialVolume = 0.5

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isProcessing = false
                }
            }
        }
    }
}
