import SwiftUI
import MediaPlayer

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var isShowingSettings = false
    
    var isLandscape: Bool {
        return cameraManager.customOrientation == .landscapeLeft || cameraManager.customOrientation == .landscapeRight
    }
    
    var body: some View {
        GeometryReader { geometry in
            let screenSize = geometry.size
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                // 가로/세로 오리엔테이션에 맞춰 정확히 계산된 프리뷰 크기
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
                
                // 2. 오버레이 컨트롤 (가로/세로 대응)
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
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(cameraManager: cameraManager)
        }
    }
    
    // MARK: - 세로 레이아웃
    @ViewBuilder
    private func portraitOverlay(screenSize: CGSize) -> some View {
        VStack(spacing: 0) {
            // 상단 마스크 & 컨트롤
            VStack {
                HStack {
                    flashButton
                    Spacer()
                    ratioButton
                    Spacer()
                    settingsButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 50)
                
                HStack {
                    Spacer()
                    numberTag
                        .padding(.trailing, 20)
                        .padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.5))
            
            Spacer()
            
            // 배율 버튼
            zoomControlBar
                .padding(.bottom, 12)
            
            // 하단 셔터 마스크
            VStack {
                HStack {
                    Spacer()
                    shutterButton
                    Spacer()
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.5))
        }
    }
    
    // MARK: - 가로 레이아웃
    @ViewBuilder
    private func landscapeOverlay(screenSize: CGSize) -> some View {
        HStack(spacing: 0) {
            // 좌측 바
            VStack {
                flashButton
                Spacer()
                ratioButton
                Spacer()
                settingsButton
            }
            .padding(.vertical, 40)
            .padding(.horizontal, 16)
            .background(Color.black.opacity(0.5))
            
            Spacer()
            
            // 우측 셔터 및 컨트롤 바
            VStack {
                numberTag
                    .padding(.top, 30)
                
                Spacer()
                
                zoomControlBar
                    .padding(.vertical, 10)
                
                shutterButton
                    .padding(.bottom, 30)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .background(Color.black.opacity(0.5))
        }
    }
    
    // MARK: - 공통 UI 구성 요소
    private var flashButton: some View {
        Button(action: { cameraManager.toggleTorch() }) {
            Image(systemName: cameraManager.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(cameraManager.isTorchOn ? .yellow : .white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.3))
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
                .background(Color.black.opacity(0.3))
                .clipShape(Circle())
        }
    }
    
    private var numberTag: some View {
        Text(String(format: "IMG_%04d", cameraManager.currentNumber))
            .font(.system(size: 22, weight: .bold, design: .monospaced))
            .foregroundColor(.yellow)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6))
            .cornerRadius(10)
    }
    
    private var shutterButton: some View {
        Button(action: { cameraManager.capturePhoto() }) {
            Circle()
                .stroke(Color.white, lineWidth: 4)
                .frame(width: 72, height: 72)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .frame(width: 60, height: 60)
                )
                .shadow(radius: 4)
        }
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
    
    // MARK: - 가로/세로 호환 비율 계산
    private func calculatePreviewSize(screenSize: CGSize, ratio: AspectRatioOption, isLandscape: Bool) -> CGSize {
        let screenW = screenSize.width
        let screenH = screenSize.height
        
        let ratioVal = ratio.ratioValue // 4:3 -> 0.75, 16:9 -> 0.5625, 1:1 -> 1.0
        
        if isLandscape {
            // 가로 모드일 때는 Height 기준으로 Width를 계산
            var targetH = screenH
            var targetW = targetH / ratioVal
            
            if targetW > screenW {
                targetW = screenW
                targetH = targetW * ratioVal
            }
            return CGSize(width: targetW, height: targetH)
        } else {
            // 세로 모드일 때는 Width 기준으로 Height를 계산
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
