import SwiftUI
import AppKit

final class AppViewModel: ObservableObject {
    @Published var inputPaths: [URL] = []
    @Published var outputDir: URL? = nil
    @Published var inplace: Bool = false
    @Published var overwrite: Bool = false
    @Published var verify: Bool = false
    @Published var keepArtwork: Bool = true
    @Published var preferAfconvert: Bool = false
    @Published var workers: Int = max(1, ProcessInfo.processInfo.processorCount)

    @Published var items: [ConversionItem] = []
    @Published var isRunning: Bool = false
    @Published var summary: String = ""

    let converter = Converter()

    func chooseInputs() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedFileTypes = ["flac"]
        if panel.runModal() == .OK {
            inputPaths = panel.urls
        }
    }

    func chooseOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        if panel.runModal() == .OK {
            outputDir = panel.url
        }
    }

    @MainActor
    func run() {
        guard !isRunning else { return }
        let targets = inputPaths
        if targets.isEmpty {
            NSSound.beep()
            return
        }
        isRunning = true
        items.removeAll()
        summary = ""

        Task {
            do {
                let result = try await converter.convert(
                    inputs: targets,
                    outputDir: inplace ? nil : outputDir,
                    inplace: inplace,
                    overwrite: overwrite,
                    verify: verify,
                    keepArtwork: keepArtwork,
                    preferAfconvert: preferAfconvert,
                    workers: workers,
                    progress: { [weak self] item in
                        Task { @MainActor in
                            if let idx = self?.items.firstIndex(where: { $0.id == item.id }) {
                                self?.items[idx] = item
                            } else {
                                self?.items.append(item)
                            }
                        }
                    }
                )

                await MainActor.run {
                    self.summary = "完了: OK \(result.ok) / SKIP \(result.skip) / FAIL \(result.fail)"
                    self.isRunning = false
                }
            } catch {
                await MainActor.run {
                    self.summary = "エラー: \(error.localizedDescription)"
                    self.isRunning = false
                }
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox(label: Text("入力")) {
                HStack {
                    Button("選択…") { viewModel.chooseInputs() }
                    Text(viewModel.inputPaths.isEmpty ? "未選択" : viewModel.inputPaths.map { $0.path }.joined(separator: ", "))
                        .lineLimit(3)
                        .truncationMode(.middle)
                }
                .padding(6)
            }

            GroupBox(label: Text("出力")) {
                VStack(alignment: .leading) {
                    Toggle("入力と同じ場所に出力（.m4a）", isOn: $viewModel.inplace)
                    HStack {
                        Button("出力先…") { viewModel.chooseOutputDir() }
                            .disabled(viewModel.inplace)
                        Text((viewModel.outputDir?.path) ?? "未指定（デフォルトは ./alac）")
                            .foregroundColor(viewModel.inplace ? .secondary : .primary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
                .padding(6)
            }

            GroupBox(label: Text("オプション")) {
                VStack(alignment: .leading) {
                    HStack {
                        Toggle("既存出力を上書き", isOn: $viewModel.overwrite)
                        Toggle("可逆性を検証（PCM MD5）", isOn: $viewModel.verify)
                    }
                    HStack {
                        Toggle("アートワーク維持", isOn: $viewModel.keepArtwork)
                        Toggle("afconvert優先(macOS)", isOn: $viewModel.preferAfconvert)
                    }
                    HStack {
                        Stepper(value: $viewModel.workers, in: 1...64) {
                            Text("並列数: \(viewModel.workers)")
                        }
                    }
                }
                .padding(6)
            }

            HStack {
                Button(action: { viewModel.run() }) {
                    Text(viewModel.isRunning ? "実行中…" : "変換開始")
                }
                .disabled(viewModel.isRunning)
                Spacer()
                Text(viewModel.summary)
                    .foregroundColor(.secondary)
            }

            List(viewModel.items) { item in
                HStack {
                    Text("[\(item.status.rawValue)]")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(color(for: item.status))
                    Text(item.displayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(item.message)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(minHeight: 240)

        }
        .padding(12)
        .frame(minWidth: 860, minHeight: 520)
    }

    private func color(for status: ConversionStatus) -> Color {
        switch status {
        case .ok: return .green
        case .skip: return .orange
        case .fail: return .red
        case .running: return .blue
        case .queued: return .secondary
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: AppViewModel())
    }
}

