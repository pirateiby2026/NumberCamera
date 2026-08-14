import SwiftUI

struct SettingsView: View {
    @ObservedObject var cameraManager: CameraManager
    @State private var inputNumber: String = ""
    @Environment(\.dismiss) private var dismiss
    
    // 1 이상 정수만 유효한 값으로 판단
    private var isValidNumber: Bool {
        guard let num = Int(inputNumber) else { return false }
        return num > 0
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("사진 시작 번호 설정"),
                    footer: Text("설정한 번호부터 파일명(IMG_xxxx)이 새로 지정됩니다.")
                ) {
                    HStack {
                        Text("시작 번호")
                        Spacer()
                        TextField("숫자 입력 (예: 1)", text: $inputNumber)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    Button(action: {
                        if let num = Int(inputNumber) {
                            cameraManager.setStartNumber(num)
                            dismiss()
                        }
                    }) {
                        HStack {
                            Spacer()
                            Text("번호 적용하기")
                                .fontWeight(.bold)
                            Spacer()
                        }
                    }
                    .disabled(!isValidNumber) // 유효하지 않은 숫입력 시 버튼 비활성화
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                inputNumber = String(cameraManager.currentNumber)
            }
        }
    }
}
