import AppKit
import SwiftUI
import UniformTypeIdentifiers
@main struct DropCheck {
 static func main() {
  let vm = AppViewModel()
  let view = ContentView(viewModel: vm)
  let provider = NSItemProvider()
  let url = URL(fileURLWithPath: "/tmp/drop-check.flac")
  provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
   DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { completion(url.dataRepresentation, nil) }
   return nil
  }
  DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
   print("FAIL: drop blocks main thread or never completes"); exit(1)
  }
  let start = Date()
  guard view.handleDrop(providers: [provider]) else { print("FAIL: drop rejected"); exit(1) }
  guard Date().timeIntervalSince(start) < 0.1 else { print("FAIL: drop did not return immediately"); exit(1) }
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
   guard vm.inputPaths == [url] else { print("FAIL: file not added: \(vm.inputPaths)"); exit(1) }
   print("PASS: immediate return, responsive main queue, FLAC added"); exit(0)
  }
  RunLoop.main.run()
 }
}
