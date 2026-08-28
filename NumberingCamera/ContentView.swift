import SwiftUI
import MediaPlayer
import Speech
import AVFoundation

// MARK: - ContentView
struct ContentView: View {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var speechRecognizer: SpeechRecognizer
    
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
                
                // 볼륨 버튼 이벤트 가로채기 핸들러 배치
                VolumeButtonHandlerView(
                    onVolumeDownPressed: {
                        if speechRecognizer.isRecording {
                            speechRecognizer.stopRecording { _ in }
                        } else {
                            speechRecognizer.startRecording(cameraManager: cameraManager)
                        }
                    },
                    onVolumeUpPressed: {
                        if speechRecognizer.isRecording {
                            speechRecognizer.stopRecording { voiceNote in
                                cameraManager.capturePhoto(voiceNote: voiceNote)
                            }
                        } else {
                            cameraManager.capturePhoto(voiceNote: "")
                        }
                    }
                )
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
                
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
                    landscapeOverlay(screenSize: screenSize, previewWidth: previewSize.width)
                } else {
                    portraitOverlay(screenSize: screenSize)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            cameraManager.checkPermissions()
            speechRecognizer.requestPermissions()
            
            speechRecognizer.onKeywordDetected = { voiceNote in
                cameraManager.capturePhoto(voiceNote: voiceNote)
            }
        }
        .onReceive(cameraManager.volumeDownPressed) { _ in
            if speechRecognizer.isRecording {
                speechRecognizer.stopRecording { _ in }
            } else {
                speechRecognizer.startRecording(cameraManager: cameraManager)
            }
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
            
            // 하단 컨트롤 영역
            // 화면 너비의 1/4 지점(25% - 좌측과 셔터버튼 중간)에 스피커 버튼을 강제로 위치시킴
            ZStack(alignment: .leading) {
                // 1. 셔터 버튼 (화면 중앙 정렬)
                HStack {
                    Spacer()
                    shutterButton
                    Spacer()
                }
                
                // 2. 스피커 버튼 (화면 전체 폭의 25% 지점에 센터 배치)
                speakerButton
                    .offset(x: (screenSize.width * 0.25) - 22) // 22는 스피커 버튼 크기(44)의 절반
            }
            .frame(width: screenSize.width, height: 72)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - 가로 레이아웃 (Landscape)
    @ViewBuilder
    private func landscapeOverlay(screenSize: CGSize, previewWidth: CGFloat) -> some View {
        let previewRightEdge = (screenSize.width + previewWidth) / 2
        let shutterSize: CGFloat = 72

        ZStack {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    numberTag
                        .padding(.top, 30)
                    
                    Spacer()
                    
                    VStack(spacing: 20) {
                        flashButton
                        ratioButton
                        settingsButton
                    }
                    
                    Spacer()
                }
                .padding(.leading, 30)
                
                Spacer()
            }
            
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    zoomControlBar
                        .padding(.bottom, 30)
                }
            }
            .frame(width: previewWidth, height: screenSize.height)

            shutterButton
                .position(
                    x: previewRightEdge + (shutterSize / 2),
                    y: 66
                )

            speakerButton
                .position(
                    x: previewRightEdge - 30,
                    y: 130
                )
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
                speechRecognizer.startRecording(cameraManager: cameraManager)
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
                            speechRecognizer.startRecording(cameraManager: cameraManager)
                        }
                    }
                    .onEnded { _ in
                        if speechRecognizer.isRecording {
                            speechRecognizer.stopRecording { voiceNote in
                                cameraManager.capturePhoto(voiceNote: voiceNote)
                            }
                        } else {
                            cameraManager.capturePhoto(voiceNote: "")
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
