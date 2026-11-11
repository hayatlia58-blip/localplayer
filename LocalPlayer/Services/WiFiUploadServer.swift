import Foundation
import Network

/// 局域网网页上传：手机开一个小 HTTP 服务，电脑浏览器打开地址即可拖拽上传视频。
/// 只实现 GET / （上传页面）与 POST /upload（multipart/form-data，单文件流式写入）。
final class WiFiUploadServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var addressText = ""
    @Published private(set) var receivedCount = 0

    var onUpload: ((URL) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "localplayer.upload", qos: .userInitiated)
    private let documents: URL
    private let port: UInt16

    init(port: UInt16 = 8080) {
        self.port = port
        self.documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.includePeerToPeer = true
            let port = NWEndpoint.Port(rawValue: self.port) ?? .any
            let listener = try NWListener(using: params, on: port)

            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                let handler = UploadConnection(
                    connection: connection,
                    queue: self.queue,
                    documents: self.documents
                ) { [weak self] saved in
                    DispatchQueue.main.async {
                        self?.receivedCount += 1
                        self?.onUpload?(saved)
                    }
                }
                handler.start()
            }

            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        let ip = WiFiUploadServer.deviceIP() ?? "127.0.0.1"
                        self.addressText = "http://\(ip):\(self.port)"
                    case .failed, .cancelled:
                        self.isRunning = false
                        self.addressText = ""
                    default:
                        break
                    }
                }
            }

            listener.start(queue: queue)
            self.listener = listener
        } catch {
            isRunning = false
            addressText = ""
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        addressText = ""
    }

    deinit { listener?.cancel() }

    /// 取 Wi-Fi 网卡 IPv4 地址
    static func deviceIP() -> String? {
        var address: String?
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                address = String(cString: host)
            }
        }
        return address
    }
}

// MARK: - 单连接处理

private final class UploadConnection {
    private enum Phase { case headers, partHeader, body }

    private let connection: NWConnection
    private let documents: URL
    private let onSaved: (URL) -> Void

    private var keepAlive: UploadConnection?

    private var buffer = Data()
    private var phase: Phase = .headers
    private var isFinished = false

    private var method = "GET"
    private var contentLength = 0
    private var boundary = ""
    private var bodyBytesReceived = 0

    private var fileHandle: FileHandle?
    private var targetURL: URL?
    private var tail = Data()
    private let tailSize = 2048

    init(connection: NWConnection, queue: DispatchQueue, documents: URL, onSaved: @escaping (URL) -> Void) {
        self.connection = connection
        self.documents = documents
        self.onSaved = onSaved
        connection.start(queue: queue)
    }

    func start() {
        keepAlive = self
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.consume(data)
            }
            if error != nil {
                self.abort()
                return
            }
            if isComplete {
                self.finalizeBody()
                self.close()
                return
            }
            if !self.isFinished { self.receive() }
        }
    }

    private func consume(_ data: Data) {
        if isFinished { return }
        buffer.append(data)
        if phase != .headers { bodyBytesReceived += data.count }

        while !isFinished {
            switch phase {
            case .headers:
                guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                    if buffer.count > 64 * 1024 { respondError(431, "请求头过大") }
                    return
                }
                let head = buffer[buffer.startIndex..<range.lowerBound]
                parseHead(String(decoding: head, as: UTF8.self))
                let overflow = Data(buffer[range.upperBound...])
                buffer = Data()
                if !isUploadRequest { return }      // GET 已经响应并关闭
                phase = .partHeader
                bodyBytesReceived = overflow.count
                buffer = overflow
                if buffer.isEmpty { return }

            case .partHeader:
                guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                    if buffer.count > 32 * 1024 { respondError(400, "缺少表单头") }
                    return
                }
                let head = buffer[buffer.startIndex..<range.lowerBound]
                parsePartHeader(String(decoding: head, as: UTF8.self))
                buffer = Data(buffer[range.upperBound...])
                phase = .body
                guard openFile() else { return }
                if buffer.isEmpty { return }

            case .body:
                flushBuffer()
                if contentLength > 0, bodyBytesReceived >= contentLength {
                    finalizeBody()
                    respondOK()
                }
                return
            }
        }
    }

    // MARK: - 解析

    private var isUploadRequest: Bool { method == "POST" }

    private func parseHead(_ text: String) {
        let lines = text.components(separatedBy: "\r\n")
        if let first = lines.first {
            let parts = first.components(separatedBy: " ")
            if let m = parts.first { method = m.uppercased() }
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        contentLength = Int(headers["content-length"] ?? "0") ?? 0
        if let type = headers["content-type"], let range = type.range(of: "boundary=") {
            var value = String(type[range.upperBound...])
            if let semicolon = value.firstIndex(of: ";") { value = String(value[..<semicolon]) }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            boundary = value
        }

        if method == "GET" {
            respondHTML(uploadPage())
        } else if method != "POST" {
            respondError(405, "不支持的方法")
        } else if contentLength <= 0 {
            respondError(411, "缺少 Content-Length")
        }
    }

    private func parsePartHeader(_ text: String) {
        for line in text.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            guard lower.hasPrefix("content-disposition") else { continue }
            if let range = line.range(of: "filename*=") {
                var value = String(line[range.upperBound...])
                if let semicolon = value.firstIndex(of: ";") { value = String(value[..<semicolon]) }
                value = value.trimmingCharacters(in: .whitespaces)
                // 形如 UTF-8''%E4%B8%AD.mp4
                if let sep = value.range(of: "''") {
                    value = String(value[sep.upperBound...])
                }
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if let decoded = value.removingPercentEncoding { pendingName = decoded }
            } else if let range = line.range(of: "filename=") {
                var value = String(line[range.upperBound...])
                if let semicolon = value.firstIndex(of: ";") { value = String(value[..<semicolon]) }
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                pendingName = value
            }
        }
    }

    private var pendingName: String = ""

    private func openFile() -> Bool {
        let fm = FileManager.default
        var name = pendingName
        if let last = name.components(separatedBy: "/").last, !last.isEmpty {
            name = last
        }
        if name.isEmpty { name = "upload-\(Int(Date().timeIntervalSince1970)).mp4" }
        name = name.replacingOccurrences(of: "\\", with: "_")

        let destination = fm.uniqueURL(in: documents, preferredName: name)
        guard fm.createFile(atPath: destination.path, contents: nil) else {
            respondError(500, "无法写入文件")
            return false
        }
        guard let handle = try? FileHandle(forWritingTo: destination) else {
            respondError(500, "无法写入文件")
            return false
        }
        fileHandle = handle
        targetURL = destination
        return true
    }

    private func flushBuffer() {
        guard let handle = fileHandle else { return }
        tail.append(buffer)
        buffer = Data()
        if tail.count > tailSize {
            let writeCount = tail.count - tailSize
            let chunk = Data(tail.prefix(writeCount))
            tail = Data(tail.suffix(tailSize))
            try? handle.write(contentsOf: chunk)
        }
    }

    private func finalizeBody() {
        guard let handle = fileHandle else { return }
        flushBuffer()

        var payload = tail
        if !boundary.isEmpty {
            let marker = Data("\r\n--\(boundary)".utf8)
            if let range = payload.range(of: marker) {
                payload = Data(payload[payload.startIndex..<range.lowerBound])
            }
        }
        if !payload.isEmpty {
            try? handle.write(contentsOf: payload)
        }
        try? handle.close()
        fileHandle = nil

        if let url = targetURL {
            onSaved(url)
        }
        targetURL = nil
        tail = Data()
    }

    // MARK: - 响应

    private func respondOK() {
        let body = Data("{\"ok\":true}".utf8)
        respond("200 OK", contentType: "application/json; charset=utf-8", body: body)
    }

    private func respondError(_ code: Int, _ message: String) {
        let body = Data("{\"ok\":false,\"error\":\"\(message)\"}".utf8)
        respond("\(code) Error", contentType: "application/json; charset=utf-8", body: body)
    }

    private func respondHTML(_ html: String) {
        let body = Data(html.utf8)
        respond("200 OK", contentType: "text/html; charset=utf-8", body: body)
    }

    private func respond(_ status: String, contentType: String, body: Data) {
        guard !isFinished else { return }
        isFinished = true
        fileHandle?.closeFile()
        fileHandle = nil

        var head = "HTTP/1.1 " + status + "\r\n"
        head += "Content-Type: " + contentType + "\r\n"
        head += "Content-Length: " + String(body.count) + "\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n"
        head += "\r\n"

        var payload = Data(head.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { [weak self] _ in
            self?.close()
        })
    }

    private func abort() {
        isFinished = true
        fileHandle?.closeFile()
        fileHandle = nil
        if let url = targetURL { try? FileManager.default.removeItem(at: url) }
        targetURL = nil
        close()
    }

    private func close() {
        connection.cancel()
        keepAlive = nil
    }
}

// MARK: - 上传页面

private func uploadPage() -> String {
    #"""
    <!doctype html>
    <html lang="zh-CN">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>传视频到 iPhone</title>
    <style>
      :root { color-scheme: dark; }
      * { box-sizing: border-box; }
      body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
             background:#0b0c0f; color:#e8eaed; font-family:-apple-system,"PingFang SC",sans-serif; padding:24px; }
      .card { width:100%; max-width:560px; }
      h1 { font-size:20px; margin:0 0 6px; font-weight:600; }
      p.hint { color:#8b909a; font-size:13px; margin:0 0 20px; }
      .drop { border:1.5px dashed #303541; border-radius:18px; padding:44px 20px; text-align:center;
              transition:.2s; background:#12141a; cursor:pointer; }
      .drop.over { border-color:#5b8cff; background:#151a26; }
      .drop b { display:block; font-size:15px; margin-bottom:6px; }
      .drop span { color:#767c88; font-size:12.5px; }
      input[type=file] { display:none; }
      ul { list-style:none; padding:0; margin:18px 0 0; }
      li { background:#12141a; border:1px solid #1e222b; border-radius:12px; padding:12px 14px; margin-bottom:8px; }
      li .row { display:flex; justify-content:space-between; font-size:13px; gap:12px; }
      li .name { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
      li .st { color:#8b909a; flex:none; }
      .bar { height:4px; border-radius:2px; background:#1e222b; margin-top:9px; overflow:hidden; }
      .bar i { display:block; height:100%; width:0; background:#5b8cff; transition:width .15s; }
      .ok { color:#3ddc84; } .err { color:#ff6b6b; }
    </style>
    </head>
    <body>
    <div class="card">
      <h1>传视频到 iPhone</h1>
      <p class="hint">拖拽或点击选择，支持多选；文件会直接存进 App 的「导入的视频」目录。</p>
      <div class="drop" id="drop">
        <b>把视频拖到这里</b>
        <span>或点击选择文件 · 支持 mp4 / mkv / mov / avi 等</span>
        <input type="file" id="input" multiple accept="video/*,.mkv,.avi,.rmvb,.ts">
      </div>
      <ul id="list"></ul>
    </div>
    <script>
    const drop = document.getElementById('drop');
    const input = document.getElementById('input');
    const list = document.getElementById('list');

    drop.addEventListener('click', () => input.click());
    input.addEventListener('change', () => { queue([...input.files]); input.value=''; });
    ['dragenter','dragover'].forEach(e => drop.addEventListener(e, ev => {
      ev.preventDefault(); drop.classList.add('over');
    }));
    ['dragleave','drop'].forEach(e => drop.addEventListener(e, ev => {
      ev.preventDefault(); drop.classList.remove('over');
    }));
    drop.addEventListener('drop', ev => queue([...ev.dataTransfer.files]));

    async function queue(files) {
      for (const file of files) { await send(file); }
    }

    function send(file) {
      return new Promise(resolve => {
        const li = document.createElement('li');
        li.innerHTML = '<div class="row"><span class="name"></span><span class="st">等待</span></div>' +
                       '<div class="bar"><i></i></div>';
        li.querySelector('.name').textContent = file.name;
        const st = li.querySelector('.st');
        const bar = li.querySelector('.bar i');
        list.appendChild(li);

        const xhr = new XMLHttpRequest();
        xhr.open('POST', '/upload');
        xhr.upload.onprogress = e => {
          if (!e.lengthComputable) return;
          const p = Math.round(e.loaded / e.total * 100);
          bar.style.width = p + '%';
          st.textContent = p + '%';
        };
        xhr.onload = () => {
          const ok = xhr.status === 200;
          st.textContent = ok ? '完成' : '失败';
          st.className = 'st ' + (ok ? 'ok' : 'err');
          bar.style.width = '100%';
          resolve();
        };
        xhr.onerror = () => { st.textContent = '断开了'; st.className = 'st err'; resolve(); };

        const form = new FormData();
        form.append('file', file, file.name);
        xhr.send(form);
      });
    }
    </script>
    </body>
    </html>
    """#
}
