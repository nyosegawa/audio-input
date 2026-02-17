import Foundation
import XCTest

@testable import AudioInput

final class MultipartFormDataTests: XCTestCase {
    func testField() {
        var form = MultipartFormData(boundary: "TestBoundary")
        form.addField(name: "model", value: "whisper-1")
        form.addField(name: "language", value: "ja")

        let data = form.build()
        let body = String(data: data, encoding: .utf8)!

        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"model\""))
        XCTAssertTrue(body.contains("whisper-1"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"language\""))
        XCTAssertTrue(body.contains("ja"))
        XCTAssertTrue(body.contains("--TestBoundary"))
        XCTAssertTrue(body.contains("--TestBoundary--"))
    }

    func testFile() {
        var form = MultipartFormData(boundary: "TestBoundary")
        let audioData = Data([0x52, 0x49, 0x46, 0x46])
        form.addFile(name: "file", filename: "audio.wav", mimeType: "audio/wav", data: audioData)

        let data = form.build()
        let body = String(data: data, encoding: .utf8)!

        XCTAssertTrue(body.contains("filename=\"audio.wav\""))
        XCTAssertTrue(body.contains("Content-Type: audio/wav"))
    }

    func testContentType() {
        let form = MultipartFormData(boundary: "TestBoundary")
        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=TestBoundary")
    }
}
