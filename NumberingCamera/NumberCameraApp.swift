import SwiftUI

@main
struct NumberCameraApp: App {
    // 🛑 앱 진입점에서 객체를 단 한 번만 생성하여 메모리에 고정합니다.
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var speechManager = SpeechRecognizer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // 🛑 하위 모든 뷰에서 동일한 인스턴스를 공유할 수 있도록 환경 객체로 주입합니다.
                .environmentObject(cameraManager)
                .environmentObject(speechManager)
        }
    }
}
