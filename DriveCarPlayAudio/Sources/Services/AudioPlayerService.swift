import AVFoundation
import MediaPlayer

final class AudioPlayerService: NSObject {
    static let shared = AudioPlayerService()

    // MARK: - State (readable by CarPlay/UI)
    private(set) var currentTrack: DriveFile?
    private(set) var queue: [DriveFile] = []
    private(set) var currentIndex: Int = 0
    private(set) var isPlaying: Bool = false

    var onStateChange: (() -> Void)?
    var onError: ((String) -> Void)?

    private var player: AVPlayer?

    // MARK: - Setup

    override init() {
        super.init()
        configureAudioSession()
        setupRemoteCommandCenter()
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            onError?("Audio sessie fout: \(error.localizedDescription)")
        }
    }

    // MARK: - Playback control

    func play(file: DriveFile, fromQueue newQueue: [DriveFile]) async {
        queue = newQueue
        currentIndex = newQueue.firstIndex(where: { $0.id == file.id }) ?? 0
        await loadAndPlay(file: file)
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingRate(0)
        onStateChange?()
    }

    func resume() {
        player?.play()
        isPlaying = true
        updateNowPlayingRate(1)
        onStateChange?()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func playNext() async {
        guard currentIndex + 1 < queue.count else { return }
        currentIndex += 1
        await loadAndPlay(file: queue[currentIndex])
    }

    func playPrevious() async {
        // Restart current track if more than 3 s in, else go previous
        if let time = player?.currentTime().seconds, time > 3 {
            player?.seek(to: .zero)
            return
        }
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        await loadAndPlay(file: queue[currentIndex])
    }

    // MARK: - Private helpers

    private func loadAndPlay(file: DriveFile) async {
        currentTrack = file
        onStateChange?()

        do {
            let headers = try await GoogleDriveService.shared.streamHeaders()
            let url     = GoogleDriveService.shared.mediaURL(for: file.id)
            let asset   = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let item    = AVPlayerItem(asset: asset)

            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(itemDidFinish),
                name: .AVPlayerItemDidPlayToEndTime,
                object: item
            )

            await MainActor.run {
                if self.player == nil {
                    self.player = AVPlayer(playerItem: item)
                } else {
                    self.player?.replaceCurrentItem(with: item)
                }
                self.player?.play()
                self.isPlaying = true
                self.updateNowPlayingInfo(for: file)
                self.onStateChange?()
            }
        } catch {
            await MainActor.run {
                self.onError?("Kan '\(file.name)' niet afspelen: \(error.localizedDescription)")
            }
        }
    }

    @objc private func itemDidFinish() {
        Task { await playNext() }
    }

    // MARK: - Now Playing metadata

    private func updateNowPlayingInfo(for file: DriveFile) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:            file.name,
            MPMediaItemPropertyArtist:           "Drive CarPlay Audio",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        if let duration = player?.currentItem?.duration.seconds, !duration.isNaN {
            info[MPMediaItemPropertyPlaybackDuration]    = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentTime().seconds ?? 0
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingRate(_ rate: Float) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = rate
    }

    // MARK: - Remote Command Center

    private func setupRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { await self?.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { await self?.playPrevious() }
            return .success
        }
    }
}
