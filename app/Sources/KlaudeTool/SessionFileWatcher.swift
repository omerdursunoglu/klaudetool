import Foundation
import Observation

@Observable
@MainActor
final class SessionFileWatcher {
    private(set) var currentFile: String?
    private(set) var isClaudeRunning = false

    private var fileOffset: UInt64 = 0
    private var pollTimer: Timer?
    private var processCheckTimer: Timer?

    var onNewEntries: (([SessionEntry]) -> Void)?

    private var claudeProjectsDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/projects"
    }

    func start() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        processCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkClaudeProcess()
            }
        }
        checkClaudeProcess()
        poll()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        processCheckTimer?.invalidate()
        processCheckTimer = nil
    }

    private func checkClaudeProcess() {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-x", "claude"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            isClaudeRunning = task.terminationStatus == 0
        } catch {
            isClaudeRunning = false
        }
    }

    private func poll() {
        guard let newestFile = findNewestSessionFile() else {
            if currentFile != nil {
                currentFile = nil
                fileOffset = 0
            }
            return
        }

        if newestFile != currentFile {
            currentFile = newestFile
            if let attrs = try? FileManager.default.attributesOfItem(atPath: newestFile),
               let size = attrs[.size] as? UInt64 {
                fileOffset = size
            }
            return
        }

        readNewLines(from: newestFile)
    }

    private func findNewestSessionFile() -> String? {
        let fm = FileManager.default
        let projectsPath = claudeProjectsDir

        guard fm.fileExists(atPath: projectsPath) else { return nil }

        var newestFile: String?
        var newestDate: Date = .distantPast

        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsPath) else {
            return nil
        }

        for dir in projectDirs {
            let dirPath = "\(projectsPath)/\(dir)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else {
                continue
            }

            for file in files where file.hasSuffix(".jsonl") {
                let filePath = "\(dirPath)/\(file)"
                guard let attrs = try? fm.attributesOfItem(atPath: filePath),
                      let modDate = attrs[.modificationDate] as? Date else {
                    continue
                }
                if modDate > newestDate {
                    newestDate = modDate
                    newestFile = filePath
                }
            }
        }

        if newestDate.timeIntervalSinceNow > -300 {
            return newestFile
        }
        return nil
    }

    private func readNewLines(from path: String) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }

        handle.seek(toFileOffset: fileOffset)
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return }

        fileOffset += UInt64(data.count)

        guard let text = String(data: data, encoding: .utf8) else { return }

        let entries: [SessionEntry] = text
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(SessionEntry.self, from: lineData)
            }

        if !entries.isEmpty {
            onNewEntries?(entries)
        }
    }
}
