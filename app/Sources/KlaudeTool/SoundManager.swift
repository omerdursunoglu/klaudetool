import AppKit
import Observation

@Observable
@MainActor
final class SoundManager {
    static let availableSounds: [String] = [
        "Glass", "Ping", "Pop", "Purr", "Tink",
        "Blow", "Funk", "Hero", "Morse", "Submarine"
    ]

    var selectedSound: String = "Glass"
    var volume: Float = 0.5

    func play() {
        play(soundName: selectedSound)
    }

    func play(soundName: String) {
        guard let sound = NSSound(named: NSSound.Name(soundName)) else { return }
        sound.volume = volume
        sound.play()
    }
}
