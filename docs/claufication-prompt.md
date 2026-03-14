# Claufication — Vibe Coding Prompt

## What We're Building

A **macOS menu bar app** called **Claufication** built with **Swift + SwiftUI**. It monitors Claude Code running inside Warp terminal and plays a notification sound in two cases:

1. **Claude asks a question** (waits for user input) → play sound after a **3-second delay**
2. **Conversation/task completes** (Claude finishes and returns to idle prompt) → play sound immediately

**Critical: Do NOT play sounds for auto-accepted inputs.** Auto-accept means Claude automatically continues without waiting for user input. Only play sounds when Claude is genuinely *waiting* for the user.

**No popup/banner notifications.** Sound only.

---

## Architecture

```
Claufication/
├── ClauficationApp.swift          # App entry, MenuBarExtra
├── MenuBarView.swift              # Menu bar icon + dropdown UI
├── Settings/
│   ├── SettingsView.swift         # Volume slider + sound picker
│   └── SoundManager.swift         # Plays selected sound at set volume
├── Monitor/
│   └── ClaudeCodeMonitor.swift    # Core monitoring logic
├── Resources/
│   └── Sounds/                    # Bundled .aiff/.wav notification sounds
└── Info.plist
```

---

## Tech Stack & Setup

- **Language:** Swift 5.9+
- **UI:** SwiftUI with `MenuBarExtra` (macOS 13+)
- **Minimum target:** macOS 14 Sonoma
- **No external dependencies.** Pure Apple frameworks only.
- **App is LSUIElement = true** (no dock icon, menu bar only)

---

## Menu Bar Icon Behavior

- Default state: **SF Symbol `bell.fill`** in the menu bar
- When a notification fires: **switch to `bell.badge.fill`** (bell with a red dot)
- When the user clicks the menu bar icon: **reset back to `bell.fill`** (clear the dot)
- The icon should be a standard macOS menu bar template image size

---

## Monitoring Logic — This Is the Most Critical Part

### How to Detect Claude Code State in Warp

Use **`lsof`** or repeatedly read the **Warp terminal's PTY (pseudo-terminal) output** to detect Claude Code's state. The recommended approach:

**Primary approach — Monitor PTY output:**

1. Find Warp's active PTY sessions: run `lsof -c Warp | grep /dev/ttys` to get PTY paths
2. For each PTY, periodically read recent output using a helper (e.g., `script` session logging or `fs_usage`)
3. Parse the output for Claude Code patterns

**Alternative approach — Log file monitoring (preferred if available):**

Check if Claude Code writes conversation logs. Common locations:
- `~/.claude/` directory
- `~/.config/claude-code/`
- Look for any `.jsonl`, `.log`, or `.json` files that update during conversations

Pick whichever approach works. If PTY monitoring is too complex, fall back to **polling the clipboard or accessibility APIs**. The key constraint: **it must work without modifying Warp or Claude Code configs.**

### Detection Patterns

**Claude is asking a question / waiting for input:**
- The terminal output ends with a prompt-like pattern where Claude has printed a question and is waiting
- Look for patterns like:
  - Lines ending with `? ` followed by no new output for 2+ seconds
  - The cursor is on an empty input line after Claude's message
  - Common Claude Code prompts: `Do you want to proceed?`, `Y/n`, `(y/N)`, any line ending with `?` where the next line is the user input area
  - The key signal: **Claude has stopped outputting text and the last meaningful line contains a question mark or a yes/no prompt**

**Claude's task is complete:**
- Claude Code returns to its idle prompt (e.g., the `>` input prompt appears after a block of work)
- The output contains completion markers like `Task completed`, or Claude simply stops outputting and the input prompt reappears
- Detect: no new output for 5+ seconds AND the last output doesn't end with a question → task likely complete

**Auto-accepted inputs (DO NOT trigger sound):**
- These happen rapidly — Claude outputs something, and within milliseconds the conversation continues
- If the gap between Claude's question and the next Claude output is < 2 seconds, it was auto-accepted → **skip the notification**
- The 3-second delay before playing the question sound naturally handles this: if new output arrives within those 3 seconds, **cancel the pending notification**

### Monitoring Flow (Pseudocode)

```
every 1 second:
    read latest terminal output from Claude Code session

    if claude_just_asked_question:
        schedule notification for 3 seconds from now
        store pending_notification_id

    if new_output_arrived AND pending_notification exists:
        cancel pending_notification  // it was auto-accepted
        
    if claude_task_completed (idle prompt returned):
        play notification sound immediately
        set bell badge to active
```

---

## Sound System

### SoundManager

```swift
class SoundManager: ObservableObject {
    @AppStorage("selectedSound") var selectedSound: String = "default"
    @AppStorage("volume") var volume: Double = 0.7
    
    let availableSounds: [String]  // list of bundled sound names
    
    func playNotification() { ... }
}
```

- Use **AVFoundation** (`AVAudioPlayer`) to play sounds
- Bundle 4-5 short notification sounds (< 1 second each):
  - `default.aiff` — clean bell ding
  - `chime.aiff` — soft chime
  - `pop.aiff` — subtle pop
  - `ping.aiff` — metallic ping
  - `drop.aiff` — water drop
- If bundling real audio files is complex, fall back to **system sounds** using `NSSound(named:)` with sounds like `Glass`, `Ping`, `Pop`, `Purr`, `Tink`
- Volume is applied via `AVAudioPlayer.volume` (0.0 to 1.0)

---

## Settings View (Dropdown from Menu Bar)

When the user clicks the bell icon, show a minimal dropdown menu with:

```
┌─────────────────────────────┐
│  🔔 Claufication            │
│                             │
│  Sound: [Dropdown ▾]        │
│    • Default                │
│    • Chime                  │
│    • Pop                    │
│    • Ping                   │
│    • Drop                   │
│                             │
│  Volume: ────●──── 70%      │
│                             │
│  [▶ Test Sound]             │
│                             │
│  ─────────────────────      │
│  Status: ● Monitoring       │
│  ─────────────────────      │
│  Quit Claufication          │
└─────────────────────────────┘
```

- **Sound picker:** dropdown/picker with all available sounds
- **Volume slider:** 0% to 100%
- **Test Sound button:** plays the selected sound at selected volume
- **Status indicator:** green dot + "Monitoring" when actively watching Claude Code, red dot + "Not detected" when no Claude Code session found
- **Quit button**
- Keep it clean and native macOS looking. Use SwiftUI's built-in components.

---

## Key Implementation Rules

1. **3-second delay for questions only.** Schedule the sound, and if Claude continues outputting (auto-accept happened), cancel it. This is the primary mechanism to avoid false positives on auto-accepted inputs.

2. **No popup notifications.** Never use `UNUserNotificationCenter` or any banner/alert. Sound only via AVFoundation.

3. **Polling interval:** Check terminal state every 1 second. This is a good balance between responsiveness and CPU usage.

4. **Low resource usage.** This app must be lightweight. No continuous heavy processing. Simple text pattern matching on terminal output.

5. **Persist settings** with `@AppStorage` / `UserDefaults`.

6. **Launch at login:** Add an option in settings (use `SMAppService` for macOS 13+).

7. **Handle edge cases:**
   - Multiple Warp windows → monitor all active PTYs
   - Claude Code not running → show "Not detected" status, keep polling
   - Warp not running → show "Not detected" status, keep polling
   - App should gracefully start/stop monitoring as Warp/Claude Code sessions come and go

---

## Build & Run

This should be a standard Xcode project. Create it as a macOS App with SwiftUI lifecycle. Set `LSUIElement = true` in Info.plist to hide from Dock.

---

## Summary of Behavior

| Scenario | Sound? | Delay? |
|---|---|---|
| Claude asks a question and waits | ✅ Yes | 3 sec delay |
| User doesn't respond for 3+ sec | ✅ Sound plays | — |
| Claude auto-accepts and continues | ❌ No sound | Cancelled within 3 sec |
| Claude finishes task, returns to idle | ✅ Yes | Immediate |
| User is typing | ❌ No sound | — |
| Claude is actively outputting text | ❌ No sound | — |

**Build this app step by step. Start with the menu bar icon and settings UI, then implement the monitoring logic, then connect the sound system. Test each piece as you go.**
