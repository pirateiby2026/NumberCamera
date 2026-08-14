import SwiftUI
import MediaPlayer // 1. 볼륨 바 숨김 처리를 위한 모듈 추가

// 화면에 보이지 않는 시스템 볼륨 뷰 (볼륨 HUD 팝업 방지용)
struct HiddenVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.alpha = 0.0001 // 화면에서 숨김 처리
        return volumeView
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var isShowingSettings = false // 설정 창 표시 상태값
    
    var body: some View {
        ZStack {
            // 1. 전체 화면 카메라 프리뷰
            CameraPreviewView(
                session: cameraManager.session,
                onPinchZoom: { scale in
                    let newZoom = cameraManager.zoomFactor * scale
                    cameraManager.setZoom(factor: newZoom)
                },
                onTapToFocus: { point in
                    cameraManager.focus(at: point)
                }
            )
            .ignoresSafeArea()
            
            // 2. 볼륨 조절 바 숨김용 뷰 (투명)
            HiddenVolumeView()
                .frame(width: 0, height: 0)
            
            // 3. 프리뷰 위에 겹쳐진 UI 오버레이
            VStack(spacing: 0) {
                // [상단 컨트롤 바]
                HStack {
                    // 플래시 버튼
                    Button(action: {
                        cameraManager.toggleTorch()
                    }) {
                        Image(systemName: cameraManager.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(cameraManager.isTorchOn ? .yellow : .white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    // 화면 비율 버튼
                    Button(action: {
                        cameraManager.cycleAspectRatio()
                    }) {
                        Text(cameraManager.selectedRatio.rawValue)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(20)
                    }
                    
                    Spacer()
                    
                    // 설정 버튼
                    Button(action: {
                        isShowingSettings = true // 설정 버튼 클릭 시 시트 오픈
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                // [우측 상단 사진 번호 태그 (2배 확대 적용)]
                HStack {
                    Spacer()
                    Text(String(format: "IMG_%04d", cameraManager.currentNumber))
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                        .padding(.trailing, 20)
                        .padding(.top, 12)
                }
                
                Spacer()
                
                // [하단 셔터 버튼 영역]
                HStack {
                    Spacer()
                    Button(action: {
                        cameraManager.capturePhoto()
                    }) {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 76, height: 76)
                            .overlay(
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 64, height: 64)
                            )
                            .shadow(radius: 4)
                    }
                    Spacer()
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            cameraManager.checkPermissions()
        }
        // SettingsView 모달 연결
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(cameraManager: cameraManager)
        }
    }
}
