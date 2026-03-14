import Foundation
import Observation

enum MonitorState: String {
    case idle = "Idle"
    case working = "Working"
    case waitingInput = "Waiting for Input"
}

@Observable
@MainActor
final class ClaudeSessionMonitor {
    private(set) var state: MonitorState = .idle
    private(set) var hasNotification = false
    private(set) var lastAssistantText = ""

    let watcher = SessionFileWatcher()
    let soundManager = SoundManager()

    private var pendingNotification: DispatchWorkItem?
    private var lastAssistantHadToolUse = false
    private var silenceTimer: Timer?
    private var silenceTimerActive = false

    var isClaudeRunning: Bool { watcher.isClaudeRunning }
    var currentFile: String? { watcher.currentFile }

    func start() {
        watcher.onNewEntries = { [weak self] entries in
            Task { @MainActor in
                self?.handleEntries(entries)
            }
        }
        watcher.start()
    }

    func stop() {
        watcher.stop()
        cancelPending()
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    func clearNotification() {
        hasNotification = false
    }

    // MARK: - Entry Processing

    private func handleEntries(_ entries: [SessionEntry]) {
        if silenceTimerActive {
            resetSilenceTimer()
        }

        for entry in entries {
            if entry.type == "user" {
                cancelPending()
            }
            processEntry(entry)
        }

        if lastAssistantHadToolUse && state == .working {
            startSilenceTimer()
        }
    }

    private func processEntry(_ entry: SessionEntry) {
        switch entry.type {
        case "user":
            state = .working
            hasNotification = false
            lastAssistantHadToolUse = false

        case "assistant":
            if let content = entry.message?.content {
                let text = content.plainText
                if !text.isEmpty {
                    lastAssistantText = text
                }
                lastAssistantHadToolUse = content.hasToolUse
            }
            state = .working

        case "system":
            if entry.subtype == "turn_duration" {
                lastAssistantHadToolUse = false
                handleTurnEnd()
            }

        default:
            break
        }
    }

    private func handleTurnEnd() {
        let text = lastAssistantText
        let isQuestion = analyzeForQuestion(text)

        state = .waitingInput
        if isQuestion {
            scheduleNotification(delay: 3.0)
        }
    }

    // MARK: - Silence Timer (tool permission detection)

    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimerActive = true
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleSilenceTimeout()
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        silenceTimerActive = false
    }

    private func handleSilenceTimeout() {
        guard state == .working, lastAssistantHadToolUse else { return }
        state = .waitingInput
        hasNotification = true
        soundManager.play()
    }

    // MARK: - Question Analysis

    private func analyzeForQuestion(_ text: String) -> Bool {
        let lower = text.lowercased()
        let lastLine = text.components(separatedBy: "\n")
            .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        let lastLineLower = lastLine.lowercased()

        let questionPatterns = [
            "(y/n)", "(yes/no)",
            "do you want", "would you like", "should i",
            "shall i", "can i", "may i",
            "please confirm", "proceed?",
            "which option", "what would you",
            "approve", "permission",
        ]

        for pattern in questionPatterns {
            if lastLineLower.contains(pattern) { return true }
        }

        if lastLine.trimmingCharacters(in: .whitespaces).hasSuffix("?") {
            return true
        }

        if lower.contains("askuserquestion") {
            return true
        }

        return false
    }

    // MARK: - Notification Scheduling

    private func scheduleNotification(delay: TimeInterval) {
        cancelPending()

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.fireNotification()
            }
        }
        pendingNotification = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPending() {
        pendingNotification?.cancel()
        pendingNotification = nil
    }

    private func fireNotification() {
        guard state == .waitingInput else { return }
        hasNotification = true
        soundManager.play()
    }
}
