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
        let view = UIView(frame: .zero)
        view.isHidden = true
        
        // 화면 밖으로 MPVolumeView를 보내서 화면에 볼륨 슬라이더가 나타나지 않게 감춤
        let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 0, height: 0))
        view.addSubview(volumeView)
        
        context.coordinator.startObserving()
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }
    
    class Coordinator: NSObject {
        var onVolumeDownPressed: () -> Void
        var onVolumeUpPressed: () -> Void
        
        private var initialVolume: Float = 0.5
        private var observation: NSKeyValueObservation?
        
        init(onVolumeDownPressed: @escaping () -> Void, onVolumeUpPressed: @escaping () -> Void) {
            self.onVolumeDownPressed = onVolumeDownPressed
            self.onVolumeUpPressed = onVolumeUpPressed
            super.init()
        }
        
        func startObserving() {
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(.playAndRecord, options: [.mixWithOthers, .defaultToSpeaker])
                try audioSession.setActive(true)
            } catch {
                print("VolumeAudioSession 설정 오류: \(error)")
            }
            
            initialVolume = audioSession.outputVolume
            
            // 볼륨 값 변화 감지
            observation = audioSession.observe(\.outputVolume, options: [.new]) { [weak self] session, change in
                guard let self = self, let newVolume = change.newValue else { return }
                
                // 연속 감지 및 연산차 오차 방지
                if abs(newVolume - self.initialVolume) > 0.001 {
                    if newVolume < self.initialVolume {
                        // 볼륨 다운 버튼 클릭
                        DispatchQueue.main.async {
                            self.onVolumeDownPressed()
                        }
                    } else if newVolume > self.initialVolume {
                        // 볼륨 업 버튼 클릭
                        DispatchQueue.main.async {
                            self.onVolumeUpPressed()
                        }
                    }
                    
                    // 시스템 볼륨 레벨을 항상 일정 수준으로 다시 리셋하여 연속 클릭 가능하도록 유지
                    self.resetSystemVolume()
                }
            }
        }
        
        private func resetSystemVolume() {
            // MPVolumeView의 Slider 제어로 볼륨 레벨 리셋
            let volumeView = MPVolumeView()
            if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    slider.value = 0.5
                }
            }
        }
        
        func stopObserving() {
            observation?.invalidate()
            observation = nil
        }
    }
}
