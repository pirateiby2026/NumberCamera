import Foundation
import Network
import Photos
import UIKit
import Combine

class WiFiServerManager: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var serverIPAddress: String = ""
    @Published var serverPort: UInt16 = 8080
    
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.numberingcamera.wifiserver")
    
    var serverURLString: String {
        guard isRunning, !serverIPAddress.isEmpty else { return "서버 중지됨" }
        return "http://\(serverIPAddress):\(serverPort)"
    }
    
    func startServer(port: UInt16 = 8080) {
        self.serverPort = port
        let ip = getWiFiAddress() ?? "IP 확인 불가"
        
        do {
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.serverIPAddress = ip
                    case .failed(let error):
                        print("Server Failed: \(error)")
                        self?.stopServer()
                    case .cancelled:
                        self?.isRunning = false
                    default: break
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: queue)
        } catch {
            print("Failed to create NWListener: \(error)")
        }
    }
    
    func stopServer() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
            self.serverIPAddress = ""
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self = self, let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }
            let requestString = String(data: data, encoding: .utf8) ?? ""
            self.processHTTPRequest(requestString, connection: connection)
        }
    }
    
    private func processHTTPRequest(_ request: String, connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { connection.cancel(); return }
        
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else { connection.cancel(); return }
        
        let method = components[0]
        let path = components[1]
        
        // URL 쿼리 파라미터 해석 (예: /?prefix=석탄부두 또는 /?prefix=ALL)
        var selectedPrefix = "ALL"
        if let urlComponents = URLComponents(string: path),
           let queryItems = urlComponents.queryItems,
           let filter = queryItems.first(where: { $0.name == "prefix" })?.value {
            selectedPrefix = filter
        }
        
        if method == "POST" && path.hasPrefix("/download_selected_zip") {
            if let bodyIndex = request.range(of: "\r\n\r\n")?.upperBound {
                let body = String(request[bodyIndex...])
                sendSelectedZipResponse(body: body, connection: connection)
            } else {
                send404(connection: connection)
            }
        } else if path.hasPrefix("/image/") {
            let encodedName = path.replacingOccurrences(of: "/image/", with: "")
            if let decodedName = encodedName.removingPercentEncoding {
                sendSingleImageResponse(filename: decodedName, connection: connection)
            } else {
                send404(connection: connection)
            }
        } else {
            sendHTMLResponse(selectedPrefix: selectedPrefix, connection: connection)
        }
    }
    
    // MARK: - HTML UI (필터 탭 지원)
    private func sendHTMLResponse(selectedPrefix: String, connection: NWConnection) {
        let allTodayPhotos = getTodayPhotos()
        
        // 발견된 접두사 목록 자동 추출 (예: ["석탄부두", "원목부두", "IMG"])
        var discoveredPrefixes = Set<String>()
        for photo in allTodayPhotos {
            let name = photo.filename
            if let underscoreIndex = name.firstIndex(of: "_") {
                let prefix = String(name[..<underscoreIndex])
                discoveredPrefixes.insert(prefix)
            } else {
                discoveredPrefixes.insert("기타")
            }
        }
        
        // 선택된 필터에 따라 사진 걸러내기
        let filteredPhotos: [PhotoItem]
        if selectedPrefix == "ALL" {
            filteredPhotos = allTodayPhotos
        } else {
            filteredPhotos = allTodayPhotos.filter { $0.filename.hasPrefix(selectedPrefix) }
        }
        
        // 필터 버튼 HTML 생성
        var filterBtnsHTML = "<a href='/?prefix=ALL' class='btn-filter \(selectedPrefix == "ALL" ? "active" : "")'>전체 보기 (\(allTodayPhotos.count))</a> "
        for pfix in discoveredPrefixes.sorted() {
            let count = allTodayPhotos.filter { $0.filename.hasPrefix(pfix) }.count
            let isActive = (selectedPrefix == pfix) ? "active" : ""
            filterBtnsHTML += "<a href='/?prefix=\(pfix.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pfix)' class='btn-filter \(isActive)'>\(pfix) (\(count))</a> "
        }
        
        // 사진 목록 HTML 생성
        var listHTML = ""
        for (index, item) in filteredPhotos.enumerated() {
            let encodedFilename = item.filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.filename
            listHTML += """
            <div class="photo-item" data-index="\(index)" onclick="toggleSelect(\(index), event)">
                <input type="checkbox" class="photo-checkbox" value="\(item.filename)" id="chk_\(index)" onclick="event.stopPropagation(); updateSelection(\(index), event);">
                <label for="chk_\(index)" class="photo-name">📷 \(item.filename)</label>
                <a href="/image/\(encodedFilename)" download="\(item.filename)" class="btn-single" onclick="event.stopPropagation();">다운로드</a>
            </div>
            """
        }
        
        if filteredPhotos.isEmpty {
            listHTML = "<p style='color:#888; text-align:center; padding: 20px;'>해당 조건의 사진이 없습니다.</p>"
        }
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>넘버링카메라 사진 내보내기</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; max-width: 760px; margin: 0 auto; padding: 20px; background: #f4f5f7; color: #333; }
                .card { background: white; padding: 20px; border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); margin-bottom: 20px; }
                .btn-zip { display: block; width: 100%; background: #34C759; color: white; text-align: center; padding: 14px 0; font-size: 16px; font-weight: bold; text-decoration: none; border-radius: 10px; border: none; cursor: pointer; }
                .btn-zip:hover { background: #28a745; }
                .btn-zip:disabled { background: #ccc; cursor: not-allowed; }
                
                .filter-bar { margin-top: 15px; display: flex; gap: 8px; flex-wrap: wrap; }
                .btn-filter { padding: 6px 12px; background: #e9ecef; color: #495057; text-decoration: none; border-radius: 20px; font-size: 13px; font-weight: 600; }
                .btn-filter.active { background: #007AFF; color: white; }
                
                .toolbar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; border-bottom: 1px solid #eee; padding-bottom: 10px; }
                .btn-sec { background: #e9ecef; border: none; padding: 6px 12px; border-radius: 6px; font-size: 13px; cursor: pointer; font-weight: 600; }
                .btn-sec:hover { background: #dee2e6; }
                
                .photo-item { border: 1px solid #e1e4e8; padding: 10px 14px; margin: 6px 0; border-radius: 8px; display: flex; justify-content: space-between; align-items: center; background: white; user-select: none; cursor: pointer; }
                .photo-item:hover { background: #f8f9fa; }
                .photo-item.selected { background: #e7f5ff; border-color: #74c0fc; }
                .photo-checkbox { width: 18px; height: 18px; margin-right: 10px; cursor: pointer; }
                .photo-name { font-weight: 600; font-size: 14px; flex-grow: 1; cursor: pointer; }
                .btn-single { background: #007AFF; color: white; padding: 6px 12px; text-decoration: none; border-radius: 6px; font-size: 13px; }
            </style>
        </head>
        <body>
            <div class="card">
                <h2>📱 넘버링카메라 사진 내보내기</h2>
                <div class="filter-bar">
                    \(filterBtnsHTML)
                </div>
                <br>
                <button id="btnZip" onclick="downloadSelectedZIP()" class="btn-zip" \(filteredPhotos.isEmpty ? "disabled" : "")>📦 선택한 사진 ZIP 다운로드 (0장)</button>
            </div>
            
            <div class="card">
                <div class="toolbar">
                    <span style="font-weight:bold;">개별 사진 목록 (\(filteredPhotos.count)장)</span>
                    <div>
                        <button class="btn-sec" onclick="selectAll(true)">전체 선택</button>
                        <button class="btn-sec" onclick="selectAll(false)">전체 해제</button>
                    </div>
                </div>
                <div id="photoList">
                    \(listHTML)
                </div>
            </div>

            <script>
                let lastSelectedIndex = -1;

                function updateCount() {
                    const checked = document.querySelectorAll('.photo-checkbox:checked');
                    const btn = document.getElementById('btnZip');
                    btn.innerText = `📦 선택한 사진 ZIP 다운로드 (${checked.length}장)`;
                    btn.disabled = checked.length === 0;
                }

                function toggleSelect(index, event) {
                    const chk = document.getElementById(`chk_${index}`);
                    const checkboxes = Array.from(document.querySelectorAll('.photo-checkbox'));
                    
                    if (event.shiftKey && lastSelectedIndex !== -1) {
                        const start = Math.min(lastSelectedIndex, index);
                        const end = Math.max(lastSelectedIndex, index);
                        const targetState = chk.checked ? chk.checked : !chk.checked;
                        
                        for (let i = start; i <= end; i++) {
                            checkboxes[i].checked = targetState;
                            updateRowClass(i);
                        }
                    } else {
                        chk.checked = !chk.checked;
                        updateRowClass(index);
                        lastSelectedIndex = index;
                    }
                    updateCount();
                }

                function updateSelection(index, event) {
                    if (event.shiftKey && lastSelectedIndex !== -1) {
                        const checkboxes = Array.from(document.querySelectorAll('.photo-checkbox'));
                        const start = Math.min(lastSelectedIndex, index);
                        const end = Math.max(lastSelectedIndex, index);
                        const targetState = checkboxes[index].checked;
                        
                        for (let i = start; i <= end; i++) {
                            checkboxes[i].checked = targetState;
                            updateRowClass(i);
                        }
                    } else {
                        updateRowClass(index);
                        lastSelectedIndex = index;
                    }
                    updateCount();
                }

                function updateRowClass(index) {
                    const chk = document.getElementById(`chk_${index}`);
                    const row = chk.closest('.photo-item');
                    if (chk.checked) row.classList.add('selected');
                    else row.classList.remove('selected');
                }

                function selectAll(flag) {
                    const checkboxes = document.querySelectorAll('.photo-checkbox');
                    checkboxes.forEach((chk, idx) => {
                        chk.checked = flag;
                        updateRowClass(idx);
                    });
                    updateCount();
                }

                function downloadSelectedZIP() {
                    const checked = Array.from(document.querySelectorAll('.photo-checkbox:checked')).map(c => c.value);
                    if (checked.length === 0) return;

                    const form = document.createElement('form');
                    form.method = 'POST';
                    form.action = '/download_selected_zip';
                    
                    const input = document.createElement('input');
                    input.type = 'hidden';
                    input.name = 'filenames';
                    input.value = JSON.stringify(checked);
                    
                    form.appendChild(input);
                    document.body.appendChild(form);
                    form.submit();
                    document.body.removeChild(form);
                }

                selectAll(true);
            </script>
        </body>
        </html>
        """
        
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\n\r\n" + html
        sendData(response.data(using: .utf8)!, connection: connection)
    }
    
    private func sendSelectedZipResponse(body: String, connection: NWConnection) {
        var selectedNames: [String] = []
        
        // POST application/x-www-form-urlencoded 데이터 디코딩 로직 보완
        let pairs = body.components(separatedBy: "&")
        for pair in pairs {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2 && kv[0] == "filenames" {
                // '+' 기호를 공백으로 변경 후 percent decoding 수행
                let rawVal = kv[1].replacingOccurrences(of: "+", with: " ")
                if let decodedJson = rawVal.removingPercentEncoding,
                   let data = decodedJson.data(using: .utf8),
                   let names = try? JSONDecoder().decode([String].self, from: data) {
                    selectedNames = names
                    break
                }
            }
        }
        
        let allAssets = getTodayPhotos()
        let targetAssets = allAssets.filter { selectedNames.contains($0.filename) }
        sendZipForAssets(assets: targetAssets, connection: connection)
    }
    
    private func sendSingleImageResponse(filename: String, connection: NWConnection) {
        guard let asset = getTodayPhotos().first(where: { $0.filename == filename }) else {
            send404(connection: connection)
            return
        }
        
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        
        PHImageManager.default().requestImageDataAndOrientation(for: asset.asset, options: options) { data, _, _, _ in
            guard let imageData = data else {
                self.send404(connection: connection)
                return
            }
            
            let encodedFilename = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
            let headers = "HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\nContent-Disposition: attachment; filename=\"\(encodedFilename)\"; filename*=UTF-8''\(encodedFilename)\r\nContent-Length: \(imageData.count)\r\n\r\n"
            var fullData = headers.data(using: .utf8)!
            fullData.append(imageData)
            self.sendData(fullData, connection: connection)
        }
    }
    
    private func sendZipForAssets(assets: [PhotoItem], connection: NWConnection) {
        var filesToZip: [(String, Data)] = []
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        
        for item in assets {
            PHImageManager.default().requestImageDataAndOrientation(for: item.asset, options: options) { data, _, _, _ in
                if let data = data {
                    filesToZip.append((item.filename, data))
                }
            }
        }
        
        if let zipData = createWindowsCompatibleZip(files: filesToZip) {
            let zipName = "NumberingCamera_\(todayDateString()).zip"
            let encodedZipName = zipName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? zipName
            
            let headers = "HTTP/1.1 200 OK\r\nContent-Type: application/zip\r\nContent-Disposition: attachment; filename=\"\(zipName)\"; filename*=UTF-8''\(encodedZipName)\r\nContent-Length: \(zipData.count)\r\n\r\n"
            var fullData = headers.data(using: .utf8)!
            fullData.append(zipData)
            sendData(fullData, connection: connection)
        } else {
            send404(connection: connection)
        }
    }
    
    private func sendData(_ data: Data, connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    private func send404(connection: NWConnection) {
        let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
        sendData(response.data(using: .utf8)!, connection: connection)
    }
    
    struct PhotoItem {
        let filename: String
        let asset: PHAsset
    }
    
    // MARK: - 오늘 자 사진 전체 불러오기
    func getTodayPhotos() -> [PhotoItem] {
        var result: [PhotoItem] = []
        let fetchOptions = PHFetchOptions()
        
        let cal = Calendar.current
        let now = Date()
        let startOfDay = cal.startOfDay(for: now)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay)!
        
        fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", startOfDay as NSDate, endOfDay as NSDate)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        fetchResult.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            if let resource = resources.first {
                result.append(PhotoItem(filename: resource.originalFilename, asset: asset))
            }
        }
        return result
    }
    
    private func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
    
    private func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }
    
    // MARK: - Mac과 Windows 모두 호환 가능한 표준 ZIP 바이너리 생성
    private func createWindowsCompatibleZip(files: [(String, Data)]) -> Data? {
        var zipData = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0
        
        for (filename, fileData) in files {
            guard let nameData = filename.data(using: .utf8) else { continue }
            let crc = crc32Checksum(data: fileData)
            let size = UInt32(fileData.count)
            
            let dosTime: UInt16 = 0x4A00
            let dosDate: UInt16 = 0x589C
            
            // 💡 핵심 수정: General Purpose Flag를 [0x00, 0x08](Bit 11 - UTF-8 인코딩 지정)로 수정하여 Mac 압축 해제 오류 해결
            var localHeader = Data([0x50, 0x4b, 0x03, 0x04])
            localHeader.append(contentsOf: [0x14, 0x00]) // Version needed (2.0)
            localHeader.append(contentsOf: [0x00, 0x08]) // General Flag (UTF-8 인코딩)
            localHeader.append(contentsOf: [0x00, 0x00]) // Compression Method (0: Uncompressed)
            localHeader.append(contentsOf: withUnsafeBytes(of: dosTime.littleEndian) { Array($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: dosDate.littleEndian) { Array($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(nameData.count).littleEndian) { Array($0) })
            localHeader.append(contentsOf: [0x00, 0x00]) // Extra field length
            localHeader.append(nameData)
            
            var cdRecord = Data([0x50, 0x4b, 0x01, 0x02])
            cdRecord.append(contentsOf: [0x14, 0x00]) // Version made by
            cdRecord.append(contentsOf: [0x14, 0x00]) // Version needed
            cdRecord.append(contentsOf: [0x00, 0x08]) // General Flag (UTF-8 인코딩)
            cdRecord.append(contentsOf: [0x00, 0x00]) // Compression Method
            cdRecord.append(contentsOf: withUnsafeBytes(of: dosTime.littleEndian) { Array($0) })
            cdRecord.append(contentsOf: withUnsafeBytes(of: dosDate.littleEndian) { Array($0) })
            cdRecord.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
            cdRecord.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
            cdRecord.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
            cdRecord.append(contentsOf: withUnsafeBytes(of: UInt16(nameData.count).littleEndian) { Array($0) })
            cdRecord.append(contentsOf: [0x00, 0x00]) // Extra field length
            cdRecord.append(contentsOf: [0x00, 0x00]) // File comment length
            cdRecord.append(contentsOf: [0x00, 0x00]) // Disk number start
            cdRecord.append(contentsOf: [0x00, 0x00]) // Internal file attributes
            cdRecord.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // External file attributes
            cdRecord.append(contentsOf: withUnsafeBytes(of: offset.littleEndian) { Array($0) })
            cdRecord.append(nameData)
            
            centralDirectory.append(cdRecord)
            zipData.append(localHeader)
            zipData.append(fileData)
            
            offset += UInt32(localHeader.count + fileData.count)
        }
        
        let cdOffset = UInt32(zipData.count)
        let cdSize = UInt32(centralDirectory.count)
        
        var eocd = Data([0x50, 0x4b, 0x05, 0x06])
        eocd.append(contentsOf: [0x00, 0x00])
        eocd.append(contentsOf: [0x00, 0x00])
        eocd.append(contentsOf: withUnsafeBytes(of: UInt16(files.count).littleEndian) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: UInt16(files.count).littleEndian) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: cdSize.littleEndian) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: cdOffset.littleEndian) { Array($0) })
        eocd.append(contentsOf: [0x00, 0x00])
        
        zipData.append(centralDirectory)
        zipData.append(eocd)
        
        return zipData
    }
    
    private func crc32Checksum(data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        let table: [UInt32] = (0..<256).map { i in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 != 0) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

