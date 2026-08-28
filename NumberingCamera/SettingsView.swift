import SwiftUI

struct SettingsView: View {
    @ObservedObject var cameraManager: CameraManager
    @EnvironmentObject var speechRecognizer: SpeechRecognizer // 맞춤 사전 제어용
    @StateObject private var wifiServer = WiFiServerManager() // Wi-Fi 서버 객체
    
    @State private var inputPrefix: String = ""
    @State private var inputNumber: String = ""
    @Environment(\.dismiss) private var dismiss
    
    // 키보드 제어용 FocusState
    @FocusState private var isPrefixFocused: Bool
    @FocusState private var isDictionaryFocused: Bool // 맞춤 사전 입력 포커스
    
    // 키워드 입력용 State
    @State private var shotKeywordInput: String = ""
    @State private var blankKeywordInput: String = ""
    
    // 맞춤 사전 추가용 State
    @State private var newKey: String = ""
    @State private var newValue: String = ""
    
    private var isValidNumber: Bool {
        guard let num = Int(inputNumber) else { return false }
        return num > 0
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 🌐 0. PC로 사진 전송 (Wi-Fi 파일 서버)
                Section(
                    header: Text("PC로 사진 전송 (Wi-Fi)"),
                    footer: Text("아이폰과 PC가 같은 Wi-Fi에 연결되어 있어야 합니다. PC 인터넷 브라우저 주소창에 위 주소를 입력하세요.")
                ) {
                    Toggle("Wi-Fi 전송 서버 키기", isOn: Binding(
                        get: { wifiServer.isRunning },
                        set: { newValue in
                            if newValue {
                                wifiServer.startServer()
                                UIApplication.shared.isIdleTimerDisabled = true // 화면 꺼짐 방지
                            } else {
                                wifiServer.stopServer()
                                UIApplication.shared.isIdleTimerDisabled = false
                            }
                        }
                    ))
                    
                    if wifiServer.isRunning {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PC 접속 주소:")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Text(wifiServer.serverURLString)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // 1. 사진 이름 및 시작 번호 설정
                Section(
                    header: Text("사진 이름 및 시작 번호 설정"),
                    footer: Text("예: '석탄부두 1BL' 입력 및 시작번호 1 설정 시 -> 석탄부두 1BL_0001.jpg 로 생성됩니다.")
                ) {
                    HStack {
                        Text("사진 접두사")
                        Spacer()
                        TextField("예: 석탄부두 1BL", text: $inputPrefix)
                            .multilineTextAlignment(.trailing)
                            .focused($isPrefixFocused)
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
                
                // 2. 음성 인식 제어 키워드 설정
                Section(
                    header: Text("음성 인식 제어 키워드"),
                    footer: Text("촬영 음성(예: '샷')을 말하면 즉시 촬영됩니다. 메모 없이 촬영할 때 말할 단어를 '공백'에 지정하세요.")
                ) {
                    HStack {
                        Text("사진촬영 키워드")
                        Spacer()
                        TextField("샷", text: $shotKeywordInput)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: shotKeywordInput) { newValue in
                                cameraManager.shotKeyword = newValue.isEmpty ? "샷" : newValue
                            }
                    }
                    
                    HStack {
                        Text("공백 처리 키워드")
                        Spacer()
                        TextField("공백", text: $blankKeywordInput)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: blankKeywordInput) { newValue in
                                cameraManager.blankKeyword = newValue.isEmpty ? "공백" : newValue
                            }
                    }
                }
                
                // 3. 음성 인식 맞춤 사전
                Section(
                    header: Text("음성 인식 맞춤 사전"),
                    footer: Text("말하는 단어를 원하는 텍스트로 자동 변환합니다. (예: '블럭' -> 'BL', '균백' -> '균열및백태')")
                ) {
                    HStack {
                        TextField("음성 (예:블럭)", text: $newKey)
                            .focused($isDictionaryFocused)
                        Image(systemName: "arrow.right")
                            .foregroundColor(.gray)
                        TextField("변환 (예:BL)", text: $newValue)
                            .focused($isDictionaryFocused)
                        
                        Button("추가") {
                            addDictionaryItem()
                        }
                        .disabled(newKey.isEmpty || newValue.isEmpty)
                    }
                    
                    ForEach(speechRecognizer.customDictionary.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack {
                            Text(key)
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                            Text(value)
                                .foregroundColor(.blue)
                                .fontWeight(.bold)
                        }
                    }
                    .onDelete(perform: deleteDictionaryItem)
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        wifiServer.stopServer()
                        UIApplication.shared.isIdleTimerDisabled = false
                        dismiss()
                    }
                }
                
                // 키보드 닫기 도구 버튼
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("완료") {
                            isPrefixFocused = false
                            isDictionaryFocused = false
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
                }
            }
            .onAppear {
                inputPrefix = cameraManager.prefixText
                inputNumber = String(cameraManager.currentNumber)
                shotKeywordInput = cameraManager.shotKeyword
                blankKeywordInput = cameraManager.blankKeyword
            }
            .onDisappear {
                wifiServer.stopServer()
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }
    
    // MARK: - 맞춤 사전 추가 / 삭제 처리
    private func addDictionaryItem() {
        let trimmedKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !trimmedKey.isEmpty && !trimmedValue.isEmpty {
            speechRecognizer.customDictionary[trimmedKey] = trimmedValue
            newKey = ""
            newValue = ""
        }
    }
    
    private func deleteDictionaryItem(at offsets: IndexSet) {
        let sortedKeys = speechRecognizer.customDictionary.sorted(by: { $0.key < $1.key }).map { $0.key }
        for index in offsets {
            let keyToDelete = sortedKeys[index]
            speechRecognizer.customDictionary.removeValue(forKey: keyToDelete)
        }
    }
}
