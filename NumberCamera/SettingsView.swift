import SwiftUI

struct SettingsView: View {
    @ObservedObject var cameraManager: CameraManager
    @State private var inputPrefix: String = ""
    @State private var inputNumber: String = ""
    @Environment(\.dismiss) private var dismiss
    
    private var isValidNumber: Bool {
        guard let num = Int(inputNumber) else { return false }
        return num > 0
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("사진 이름 및 시작 번호 설정"),
                    footer: Text("예: '석탄부두 1BL' 입력 및 시작번호 1 설정 시 -> 석탄부두 1BL_0001.jpg 로 생성됩니다.")
                ) {
                    HStack {
                        Text("사진 접두사")
                        Spacer()
                        TextField("예: 석탄부두 1BL", text: $inputPrefix)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("시작 번호")
                        Spacer()
                        TextField("숫자 입력 (예: 1)", text: $inputNumber)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    Button(action: {
                        if let num = Int(inputNumber) {
                            cameraManager.setStartNumber(num, prefix: inputPrefix)
                            dismiss()
                        }
                    }) {
                        HStack {
                            Spacer()
                            Text("적용하기")
                                .fontWeight(.bold)
                            Spacer()
                        }
                    }
                    .disabled(!isValidNumber)
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
                inputPrefix = cameraManager.prefixText
                inputNumber = String(cameraManager.currentNumber)
            }
        }
    }
}
