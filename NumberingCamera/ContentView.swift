import SwiftUI
import MediaPlayer
import Speech
import AVFoundation

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var isShowingSettings = false
    
    @Environment(\.scenePhase) private var scenePhase
    
    var isLandscape: Bool {
        return cameraManager.customOrientation == .landscapeLeft || cameraManager.customOrientation == .landscapeRight
    }
    
    var body: some View {
        GeometryReader { geometry in
            let screenSize = geometry.size
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                let previewSize = calculatePreviewSize(
                    screenSize: screenSize,
                    ratio: cameraManager.selectedRatio,
                    isLandscape: isLandscape
                )
                
                // 1. 카메라 프리뷰
                CameraPreviewView(
                    session: cameraManager.session,
                    orientation: cameraManager.customOrientation,
                    onPinchZoom: { scale in
                        let newZoom = cameraManager.zoomFactor * scale
                        cameraManager.setZoom(factor: newZoom)
                    },
                    onTapToFocus: { point in
                        cameraManager.focus(at: point)
                    }
                )
                .frame(width: previewSize.width, height: previewSize.height)
                .clipped()
                
                // 음성 인식 실시간 자막
                if speechRecognizer.isRecording {
                    VStack {
                        Spacer()
                        Text(speechRecognizer.transcribedText.isEmpty ? "음성을 듣는 중..." : speechRecognizer.transcribedText)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.yellow.opacity(0.9))
                            .cornerRadius(20)
                            .padding(.bottom, isLandscape ? 100 : 160)
                    }
                }
                
                // 2. 오버레이 컨트롤
                if isLandscape {
                    landscapeOverlay(screenSize: screenSize)
                } else {
                    portraitOverlay(screenSize: screenSize)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            cameraManager.checkPermissions()
            speechRecognizer.requestPermissions()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                cameraManager.checkPermissions()
                cameraManager.resumeSession()
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(cameraManager: cameraManager)
        }
    }
    
    // MARK: - 세로 레이아웃 (Portrait)
    @ViewBuilder
    private func portraitOverlay(screenSize: CGSize) -> some View {
        VStack(spacing: 0) {
            // 상단 컨트롤 바
            HStack {
                flashButton
                Spacer()
                ratioButton
                Spacer()
                settingsButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 50)
            .padding(.bottom, 10)
            
            // 상단 오른쪽 사진번호 표시
            HStack {
                Spacer()
                numberTag
                    .padding(.trailing, 20)
            }
            
            Spacer()
            
            // 배율 조절 바
            zoomControlBar
                .padding(.bottom, 20)
            
            // 하단 영역: 스피커 버튼을 맨 좌측에 배치하고 셔터 버튼을 화면 중앙에 정렬
            HStack(spacing: 0) {
                speakerButton
                    .padding(.leading, 24) // 맨 좌측 여백
                
                Spacer()
                
                shutterButton
                
                Spacer()
                
                // 좌우 균형 맞춤용 더미 공간 (스피커 버튼 크기 + 여백)
                Color.clear
                    .frame(width: 44 + 24, height: 44)
            }
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - 가로 레이아웃 (Landscape)
    @ViewBuilder
    private func landscapeOverlay(screenSize: CGSize) -> some View {
        HStack(spacing: 0) {
            // 좌측 컨트롤 바
            VStack {
                flashButton
                Spacer()
                ratioButton
                Spacer()
                settingsButton
            }
            .padding(.vertical, 40)
            .padding(.leading, 30)
            
            Spacer()
            
            // 우측 영역: 사진번호 태그 -> 스피커 버튼 -> 셔터 버튼 -> 하단 배율 숫자
            VStack(spacing: 0) {
                numberTag
                    .padding(.top, 30)
                
                // 상단 번호표와 스피커 사이 유연한 공간
                Spacer().frame(height: 16)
                
                // 셔터 위쪽(사진번호 아래 영역)으로 이동한 스피커 버튼
                speakerButton
                
                // 스피커와 셔터 사이 여백
                Spacer()
                
                // 셔터 버튼
                shutterButton
                
                // 셔터와 하단 배율 숫자 사이 공간
                Spacer()
                
                // 하단 배율 조절 바 (숫자)
                zoomControlBar
                    .padding(.bottom, 30)
            }
            .padding(.trailing, 30)
        }
    }
    
    // MARK: - 공통 UI 구성 요소
    private var flashButton: some View {
        Button(action: { cameraManager.toggleTorch() }) {
            Image(systemName: cameraManager.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(cameraManager.isTorchOn ? .yellow : .white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
    }
    
    private var speakerButton: some View {
        Button(action: {
            if speechRecognizer.isRecording {
                speechRecognizer.stopRecording { _ in }
            } else {
                speechRecognizer.startRecording()
            }
        }) {
            Image(systemName: speechRecognizer.isRecording ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(speechRecognizer.isRecording ? .yellow : .white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }
    
    private var ratioButton: some View {
        Button(action: { cameraManager.cycleAspectRatio() }) {
            Text(cameraManager.selectedRatio.rawValue)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.4))
                .cornerRadius(20)
        }
    }
    
    private var settingsButton: some View {
        Button(action: { isShowingSettings = true }) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
    }
    
    private var numberTag: some View {
        Text(String(format: "%@_%04d", cameraManager.prefixText, cameraManager.currentNumber))
            .font(.system(size: 29, weight: .bold, design: .monospaced))
            .foregroundColor(.yellow)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))
            .cornerRadius(10)
    }
    
    private var shutterButton: some View {
        Circle()
            .stroke(speechRecognizer.isRecording ? Color.red : Color.white, lineWidth: 4)
            .frame(width: 72, height: 72)
            .overlay(
                Circle()
                    .fill(speechRecognizer.isRecording ? Color.red : Color.white)
                    .frame(width: 60, height: 60)
            )
            .shadow(radius: 4)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !speechRecognizer.isRecording {
                            speechRecognizer.startRecording()
                        }
                    }
                    .onEnded { _ in
                        speechRecognizer.stopRecording { voiceNote in
                            cameraManager.capturePhoto(voiceNote: voiceNote)
                        }
                    }
            )
    }
    
    private var zoomControlBar: some View {
        HStack(spacing: 12) {
            zoomButton(title: "0.5x", displayFactor: 0.5)
            zoomButton(title: "1x", displayFactor: 1.0)
            zoomButton(title: "2x", displayFactor: 2.0)
        }
    }
    
    @ViewBuilder
    private func zoomButton(title: String, displayFactor: CGFloat) -> some View {
        let isSelected = abs(cameraManager.displayZoomFactor - displayFactor) < 0.15
        Button(action: {
            cameraManager.setDisplayZoom(displayFactor: displayFactor)
        }) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isSelected ? .yellow : .white)
                .frame(width: 38, height: 38)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }
    
    private func calculatePreviewSize(screenSize: CGSize, ratio: AspectRatioOption, isLandscape: Bool) -> CGSize {
        let screenW = screenSize.width
        let screenH = screenSize.height
        let ratioVal = ratio.ratioValue
        
        if isLandscape {
            var targetH = screenH
            var targetW = targetH / ratioVal
            
            if targetW > screenW {
                targetW = screenW
                targetH = targetW * ratioVal
            }
            return CGSize(width: targetW, height: targetH)
        } else {
            var targetW = screenW
            var targetH = targetW / ratioVal
            
            if targetH > screenH {
                targetH = screenH
                targetW = targetH * ratioVal
            }
            return CGSize(width: targetW, height: targetH)
        }
    }
}
