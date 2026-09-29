import Foundation
import Vision
import AppKit

func fail(_ msg: String) -> Never {
    let obj: [String: Any] = ["error": msg, "blocks": []]
    if let data = try? JSONSerialization.data(withJSONObject: obj) {
        FileHandle.standardOutput.write(data)
    }
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage: ms_ocr_read <image> [fast]") }
let path = args[1]
let fast = args.count >= 3 && args[2] == "fast"

guard let nsimg = NSImage(contentsOfFile: path),
      let cg = nsimg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("could not load image: \(path)")
}

let W = CGFloat(cg.width)
let H = CGFloat(cg.height)

let request = VNRecognizeTextRequest()
request.recognitionLevel = fast ? .fast : .accurate
request.usesLanguageCorrection = false

let handler = VNImageRequestHandler(cgImage: cg, options: [:])
do {
    try handler.perform([request])
} catch {
    fail("recognition failed: \(error.localizedDescription)")
}

var blocks: [[String: Any]] = []
for observation in (request.results ?? []) {
    guard let candidate = observation.topCandidates(1).first else { continue }
    let bb = observation.boundingBox // normalized, bottom-left origin
    let px = bb.origin.x * W
    let py = (1.0 - bb.origin.y - bb.size.height) * H // flip to top-left
    let pw = bb.size.width * W
    let ph = bb.size.height * H
    blocks.append([
        "text": candidate.string,
        "conf": candidate.confidence,
        "x": Int(px.rounded()),
        "y": Int(py.rounded()),
        "w": Int(pw.rounded()),
        "h": Int(ph.rounded()),
    ])
}

let out: [String: Any] = ["w": Int(W), "h": Int(H), "blocks": blocks]
guard let data = try? JSONSerialization.data(withJSONObject: out) else {
    fail("could not encode result")
}
FileHandle.standardOutput.write(data)
