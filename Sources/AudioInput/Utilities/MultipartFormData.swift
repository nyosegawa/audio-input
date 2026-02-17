import Foundation

struct MultipartFormData: Sendable {
    private let boundary: String
    private var parts: [(name: String, data: Data, filename: String?, mimeType: String?)]

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
        self.parts = []
    }

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    mutating func addField(name: String, value: String) {
        if let data = value.data(using: .utf8) {
            parts.append((name: name, data: data, filename: nil, mimeType: nil))
        }
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data: Data) {
        parts.append((name: name, data: data, filename: filename, mimeType: mimeType))
    }

    func build() -> Data {
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"

        for part in parts {
            body.append(Data(boundaryPrefix.utf8))

            if let filename = part.filename, let mimeType = part.mimeType {
                body.append(Data("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\r\n".utf8))
                body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
            } else {
                body.append(Data("Content-Disposition: form-data; name=\"\(part.name)\"\r\n\r\n".utf8))
            }

            body.append(part.data)
            body.append(Data("\r\n".utf8))
        }

        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}
