import Foundation
import CryptoKit

let supportedInputExts: Set<String> = [".flac"]
let outputExt: String = ".m4a"

enum ConversionStatus: String, Codable {
    case queued = "QUEUED"
    case running = "RUN"
    case ok = "OK"
    case skip = "SKIP"
    case fail = "FAIL"
}

struct ConversionItem: Identifiable, Codable {
    var id = UUID()
    var source: URL
    var destination: URL?
    var status: ConversionStatus
    var message: String

    var displayName: String { source.lastPathComponent }
}

struct ConversionSummary {
    let ok: Int
    let skip: Int
    let fail: Int
}

final class Converter {
    func convert(
        inputs: [URL],
        outputDir: URL?,
        inplace: Bool,
        overwrite: Bool,
        verify: Bool,
        keepArtwork: Bool,
        preferAfconvert: Bool,
        workers: Int,
        progress: @escaping (ConversionItem) -> Void
    ) async throws -> ConversionSummary {
        let files = try gatherInputs(inputs)
        if files.isEmpty { return .init(ok: 0, skip: 0, fail: 0) }

        let (kind, tool) = try detectConverter(preferAfconvert: preferAfconvert)
        let ffmpegForVerify = (try? which("ffmpeg"))

        let inputRoot: URL? = inputs.count == 1 && isDirectory(inputs[0]) ? inputs[0] : nil

        let semaphore = DispatchSemaphore(value: max(1, workers))
        let lock = NSLock()
        var ok = 0, skip = 0, fail = 0

        try await withThrowingTaskGroup(of: Void.self) { group in
            for src in files {
                semaphore.wait()
                group.addTask {
                    defer { semaphore.signal() }
                    var item = ConversionItem(source: src, destination: nil, status: .running, message: "")
                    progress(item)
                    do {
                        let dst = self.computeOutputPath(src: src, inplace: inplace, outputDir: outputDir, inputRoot: inputRoot)
                        item.destination = dst
                        if !overwrite, self.shouldSkip(src: src, dst: dst) {
                            item.status = .skip
                            item.message = "既に最新の出力が存在"
                            lock.lock(); skip += 1; lock.unlock()
                            progress(item)
                            return
                        }
                        try self.ensureParentDir(dst)
                        if kind == "ffmpeg" {
                            try self.runFFmpeg(ffmpeg: tool, src: src, dst: dst, overwrite: overwrite, keepArtwork: keepArtwork)
                        } else {
                            try self.runAfconvert(afconvert: tool, src: src, dst: dst, overwrite: overwrite)
                        }
                        if verify, let ff = ffmpegForVerify {
                            let a = try self.computePCMMD5(ffmpeg: ff, url: src)
                            let b = try self.computePCMMD5(ffmpeg: ff, url: dst)
                            if a != b {
                                // 不一致は失敗扱いし生成物は削除
                                try? FileManager.default.removeItem(at: dst)
                                throw NSError(domain: "verify", code: 1, userInfo: [NSLocalizedDescriptionKey: "verify不一致: PCM MD5不一致"])
                            }
                        }
                        item.status = .ok
                        item.message = "ok"
                        lock.lock(); ok += 1; lock.unlock()
                        progress(item)
                    } catch {
                        item.status = .fail
                        item.message = error.localizedDescription
                        lock.lock(); fail += 1; lock.unlock()
                        progress(item)
                    }
                }
            }
            try await group.waitForAll()
        }

        return .init(ok: ok, skip: skip, fail: fail)
    }

    // MARK: - Core helpers

    func gatherInputs(_ paths: [URL]) throws -> [URL] {
        var files: [URL] = []
        for p in paths {
            if isFile(p), supportedInputExts.contains(p.pathExtension.lowercased().prependedDot) {
                files.append(p)
            } else if isDirectory(p) {
                let it = FileManager.default.enumerator(at: p, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                while let u = it?.nextObject() as? URL {
                    if isFile(u), supportedInputExts.contains(u.pathExtension.lowercased().prependedDot) {
                        files.append(u)
                    }
                }
            }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func detectConverter(preferAfconvert: Bool) throws -> (String, String) {
        let ff = try? which("ffmpeg")
        let af = try? which("afconvert")
        if preferAfconvert, let af { return ("afconvert", af) }
        if let ff { return ("ffmpeg", ff) }
        if let af { return ("afconvert", af) }
        throw NSError(domain: "converter", code: 127, userInfo: [NSLocalizedDescriptionKey: "ffmpeg または afconvert が見つかりません。インストールしてください。"])
    }

    func computeOutputPath(src: URL, inplace: Bool, outputDir: URL?, inputRoot: URL?) -> URL {
        if inplace { return src.deletingPathExtension().appendingPathExtension("m4a") }
        let base = outputDir ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("alac")
        if let root = inputRoot, src.path.hasPrefix(root.path) {
            let rel = src.path.replacingOccurrences(of: root.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let to = base.appendingPathComponent(rel).deletingPathExtension().appendingPathExtension("m4a")
            return to
        }
        return base.appendingPathComponent(src.lastPathComponent).deletingPathExtension().appendingPathExtension("m4a")
    }

    func ensureParentDir(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func shouldSkip(src: URL, dst: URL) -> Bool {
        guard let ds = try? dst.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              let ss = try? src.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return false }
        return ds >= ss
    }

    func runFFmpeg(ffmpeg: String, src: URL, dst: URL, overwrite: Bool, keepArtwork: Bool) throws {
        var args = ["-hide_banner", "-loglevel", "error"]
        args += [overwrite ? "-y" : "-n"]
        args += ["-i", src.path]
        if keepArtwork {
            args += ["-map", "0:a:0", "-c:a", "alac", "-map", "0:v?", "-c:v", "copy", "-disposition:v:0", "attached_pic", "-map_metadata", "0", "-movflags", "use_metadata_tags"]
        } else {
            args += ["-map", "0:a:0", "-c:a", "alac", "-map_metadata", "0", "-movflags", "use_metadata_tags"]
        }
        args += [dst.path]
        try runProcess(launchPath: ffmpeg, arguments: args)
    }

    func runAfconvert(afconvert: String, src: URL, dst: URL, overwrite: Bool) throws {
        if overwrite, FileManager.default.fileExists(atPath: dst.path) {
            try? FileManager.default.removeItem(at: dst)
        }
        try runProcess(launchPath: afconvert, arguments: ["-f", "m4af", "-d", "alac", src.path, dst.path])
    }

    func computePCMMD5(ffmpeg: String, url: URL) throws -> String {
        // ffmpeg -v error -i <url> -map 0:a:0 -f s32le - | md5
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffmpeg)
        proc.arguments = ["-v", "error", "-i", url.path, "-map", "0:a:0", "-f", "s32le", "-"]
        proc.standardOutput = pipe
        let group = DispatchGroup()
        var digest = Insecure.MD5()
        var readErr: Error? = nil
        group.enter()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.count > 0 {
                digest.update(data: data)
            }
        }
        do {
            try proc.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        proc.terminationHandler = { _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            group.leave()
        }
        group.wait()
        if proc.terminationStatus != 0 {
            throw readErr ?? NSError(domain: "ffmpeg", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "PCMデコードに失敗"])
        }
        let hash = digest.finalize()
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    func runProcess(launchPath: String, arguments: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        let out = Pipe(); proc.standardOutput = out
        let err = Pipe(); proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "失敗"
            throw NSError(domain: "process", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: msg.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
    }

    func which(_ name: String) throws -> String {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [name]
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 { throw NSError(domain: "which", code: 1, userInfo: [NSLocalizedDescriptionKey: "not found"]) }
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if path.isEmpty { throw NSError(domain: "which", code: 1, userInfo: [NSLocalizedDescriptionKey: "not found"]) }
        return path
    }

    // MARK: - FS utils
    func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
    func isFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
    }
}

private extension String {
    var prependedDot: String { self.hasPrefix(".") ? self : "." + self }
}

