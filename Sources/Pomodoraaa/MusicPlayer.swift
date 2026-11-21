import AppKit
import WebKit

enum MusicSource: String, Codable, CaseIterable, Identifiable {
    case youtube, spotify
    var id: String { rawValue }
    var label: String { self == .youtube ? "YouTube Music" : "Spotify" }
}

struct Station: Codable, Hashable, Identifiable {
    var name: String
    var detail: String
    var link: String
    var source: MusicSource
    var id: String { link }
}

/// Plays focus music from YouTube / YouTube Music (embedded player, no account needed)
/// or Spotify (drives the Spotify desktop app via AppleScript).
@MainActor
final class MusicPlayer: ObservableObject {
    static let quickPicks: [Station] = [
        Station(name: "Lofi hip hop radio", detail: "Lofi Girl · live",
                link: "https://www.youtube.com/watch?v=jfKfPfyJRdk", source: .youtube),
        Station(name: "Synthwave radio", detail: "Lofi Girl · live",
                link: "https://www.youtube.com/watch?v=nWjC1RnLYbM", source: .youtube),
        Station(name: "Sleepy lofi radio", detail: "Lofi Girl · live · softer",
                link: "https://www.youtube.com/watch?v=rUxyKA_-grg", source: .youtube),
        Station(name: "Deep Focus", detail: "Spotify · playlist",
                link: "https://open.spotify.com/playlist/37i9dQZF1DWZeKCadgRdKQ", source: .spotify),
        Station(name: "Peaceful Piano", detail: "Spotify · playlist",
                link: "https://open.spotify.com/playlist/37i9dQZF1DX4sWSpwq3LiO", source: .spotify),
        Station(name: "Lofi Beats", detail: "Spotify · playlist",
                link: "https://open.spotify.com/playlist/37i9dQZF1DWWQRwui0ExPn", source: .spotify),
    ]

    private let defaults = UserDefaults.standard

    @Published var source: MusicSource {
        didSet { defaults.set(source.rawValue, forKey: "musicSource") }
    }
    @Published private(set) var current: Station?
    @Published private(set) var isPlaying = false
    @Published var volume: Double {
        didSet {
            defaults.set(volume, forKey: "musicVolume")
            scheduleVolumeApply()
        }
    }
    @Published var pauseOnBreaks: Bool {
        didSet { defaults.set(pauseOnBreaks, forKey: "pauseOnBreaks") }
    }
    @Published private(set) var recent: [Station]
    @Published var message: String?

    /// True once the user picked something — music then follows the timer.
    private var wantsMusic = false

    private let bridge = ScriptBridge()
    private(set) lazy var webView: WKWebView = makeWebView()
    private var pageReady = false
    private var pendingJS: [String] = []
    private let scriptQueue = DispatchQueue(label: "app.pomodoraaa.applescript")
    private var volumeWork: DispatchWorkItem?

    init() {
        let d = UserDefaults.standard
        source = MusicSource(rawValue: d.string(forKey: "musicSource") ?? "") ?? .youtube
        volume = d.object(forKey: "musicVolume") as? Double ?? 60
        pauseOnBreaks = d.object(forKey: "pauseOnBreaks") as? Bool ?? true
        if let data = d.data(forKey: "recentStations"),
           let list = try? JSONDecoder().decode([Station].self, from: data) {
            recent = list
        } else {
            recent = []
        }
        bridge.onMessage = { [weak self] text in
            guard let player = self else { return }
            Task { @MainActor in player.handleWebMessage(text) }
        }
    }

    var picksForSource: [Station] {
        let mine = recent.filter { $0.source == source }
        let picks = Self.quickPicks.filter { $0.source == source }
        return mine + picks.filter { p in !mine.contains(where: { $0.link == p.link }) }
    }

    func isCurrent(_ station: Station) -> Bool { current?.link == station.link }

    // MARK: Public controls

    /// Paste-a-link entry point.
    func play(link raw: String) {
        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { return }
        if let ids = Self.youtubeIDs(from: link) {
            let name = ids.list != nil ? "Your YouTube playlist" : "Your YouTube track"
            play(Station(name: name, detail: "YouTube Music · pasted link", link: link, source: .youtube), remember: true)
        } else if let uri = Self.spotifyURI(from: link) {
            let kind = uri.split(separator: ":").dropFirst().first.map(String.init) ?? "link"
            play(Station(name: "Your Spotify \(kind)", detail: "Spotify · pasted link", link: link, source: .spotify), remember: true)
        } else {
            message = "Paste a YouTube Music, YouTube or Spotify link."
        }
    }

    /// Tap on a station row: play it, or pause it if it is already playing.
    func tap(_ station: Station) {
        if isCurrent(station) {
            if isPlaying { wantsMusic = false; pauseInternal() } else { wantsMusic = true; resumeInternal() }
        } else {
            play(station, remember: false)
        }
    }

    func togglePlayPause() {
        guard current != nil else { return }
        if isPlaying { wantsMusic = false; pauseInternal() } else { wantsMusic = true; resumeInternal() }
    }

    func stop() {
        wantsMusic = false
        pauseInternal()
        current = nil
    }

    /// Called whenever the timer starts, pauses or switches between focus and break.
    func syncWithTimer(running: Bool, isBreak: Bool) {
        guard wantsMusic, current != nil else { return }
        let shouldPlay = running && !(isBreak && pauseOnBreaks)
        if shouldPlay { resumeInternal() } else { pauseInternal() }
    }

    // MARK: Internals

    private func play(_ station: Station, remember: Bool) {
        message = nil
        if let cur = current, cur.source != station.source { pauseInternal() }
        current = station
        source = station.source
        wantsMusic = true
        if remember { self.remember(station) }

        switch station.source {
        case .youtube:
            guard let ids = Self.youtubeIDs(from: station.link) else {
                message = "That doesn't look like a YouTube link."
                return
            }
            runJS("loadMedia(\(Self.jsLiteral(ids.video)), \(Self.jsLiteral(ids.list)), \(Int(volume)))")
            isPlaying = true
        case .spotify:
            guard let uri = Self.spotifyURI(from: station.link) else {
                message = "That doesn't look like a Spotify link."
                return
            }
            guard spotifyInstalled else {
                openInBrowser(station.link)
                message = "Spotify app not found — opened the link in your browser."
                isPlaying = false
                return
            }
            spotify("set sound volume to \(Int(volume))")
            spotify("play track \"\(uri)\"")
            isPlaying = true
        }
    }

    private func pauseInternal() {
        guard let current, isPlaying else { return }
        switch current.source {
        case .youtube: runJS("pauseMedia()")
        case .spotify: if spotifyInstalled { spotify("pause") }
        }
        isPlaying = false
    }

    private func resumeInternal() {
        guard let current, !isPlaying else { return }
        switch current.source {
        case .youtube: runJS("playMedia()")
        case .spotify:
            guard spotifyInstalled else { return }
            spotify("play")
        }
        isPlaying = true
    }

    private func remember(_ station: Station) {
        recent.removeAll { $0.link == station.link }
        recent.insert(station, at: 0)
        if recent.count > 5 { recent = Array(recent.prefix(5)) }
        if let data = try? JSONEncoder().encode(recent) { defaults.set(data, forKey: "recentStations") }
    }

    private func scheduleVolumeApply() {
        volumeWork?.cancel()
        let level = Int(volume)
        let work = DispatchWorkItem { [weak self] in
            guard let player = self else { return }
            Task { @MainActor in player.applyVolume(level) }
        }
        volumeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func applyVolume(_ level: Int) {
        guard let current else { return }
        switch current.source {
        case .youtube: runJS("setVol(\(level))")
        case .spotify: if spotifyInstalled { spotify("set sound volume to \(level)") }
        }
    }

    private func openInBrowser(_ link: String) {
        var s = link
        if !s.contains("://") { s = "https://" + s }
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }

    // MARK: YouTube (embedded IFrame player in an invisible web view)

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(bridge, name: "pomo")
        let view = PassthroughWebView(frame: NSRect(x: 0, y: 0, width: 240, height: 240), configuration: config)
        view.alphaValue = 0.01
        view.loadHTMLString(Self.playerHTML, baseURL: URL(string: "https://pomodoraaa.app/"))
        return view
    }

    private func runJS(_ js: String) {
        _ = webView // make sure the page is loading
        if pageReady {
            webView.evaluateJavaScript(js, completionHandler: nil)
        } else {
            pendingJS.append(js)
        }
    }

    private func handleWebMessage(_ text: String) {
        if text == "page" {
            pageReady = true
            let queued = pendingJS
            pendingJS.removeAll()
            for js in queued { webView.evaluateJavaScript(js, completionHandler: nil) }
        } else if text.hasPrefix("state:"), current?.source == .youtube {
            switch text.dropFirst(6) {
            case "1": isPlaying = true
            case "2", "0": isPlaying = false
            default: break
            }
        } else if text.hasPrefix("error:"), let station = current, station.source == .youtube {
            isPlaying = false
            openInBrowser(station.link)
            message = "This one can't play inside the widget, so it opened in your browser."
        }
    }

    // MARK: Spotify (desktop app via AppleScript)

    private var spotifyInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil
    }

    private func spotify(_ command: String) {
        let source = "tell application \"Spotify\" to \(command)"
        scriptQueue.async { [weak self] in
            var error: NSDictionary?
            _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let code = error?[NSAppleScript.errorNumber] as? Int
            let text = error?[NSAppleScript.errorMessage] as? String
            guard code != nil || text != nil, let player = self else { return }
            Task { @MainActor in player.spotifyFailed(code: code, text: text) }
        }
    }

    private func spotifyFailed(code: Int?, text: String?) {
        isPlaying = false
        if code == -1743 {
            message = "Allow Pomodoraaa to control Spotify: System Settings › Privacy & Security › Automation."
        } else {
            message = "Spotify didn't respond" + (text.map { " (\($0))" } ?? ".")
        }
    }

    // MARK: Link parsing

    static func youtubeIDs(from link: String) -> (video: String?, list: String?)? {
        var s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard let comps = URLComponents(string: s), let host = comps.host?.lowercased(),
              host.hasSuffix("youtube.com") || host.hasSuffix("youtu.be") || host.hasSuffix("youtube-nocookie.com")
        else { return nil }

        let items = comps.queryItems ?? []
        var video = items.first(where: { $0.name == "v" })?.value
        let list = items.first(where: { $0.name == "list" })?.value
        let parts = comps.path.split(separator: "/").map(String.init)
        if host.hasSuffix("youtu.be") {
            video = parts.first
        } else if video == nil, parts.count >= 2, ["live", "embed", "shorts"].contains(parts[0]) {
            video = parts[1]
        }
        let v = video.map(clean).flatMap { $0.isEmpty ? nil : $0 }
        let l = list.map(clean).flatMap { $0.isEmpty ? nil : $0 }
        if v == nil && l == nil { return nil }
        return (v, l)
    }

    static func spotifyURI(from link: String) -> String? {
        let kinds = ["playlist", "album", "track", "artist", "episode", "show"]
        let s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("spotify:") {
            let parts = s.split(separator: ":").map(String.init)
            guard parts.count >= 3, kinds.contains(parts[1]) else { return nil }
            let id = clean(parts[2])
            return id.isEmpty ? nil : "spotify:\(parts[1]):\(id)"
        }
        var t = s
        if !t.contains("://") { t = "https://" + t }
        guard let comps = URLComponents(string: t), let host = comps.host?.lowercased(),
              host.hasSuffix("spotify.com") else { return nil }
        let parts = comps.path.split(separator: "/").map(String.init)
        for (i, p) in parts.enumerated() where kinds.contains(p) && i + 1 < parts.count {
            let id = clean(parts[i + 1])
            if !id.isEmpty { return "spotify:\(p):\(id)" }
        }
        return nil
    }

    /// Keep only characters that can appear in YouTube / Spotify IDs.
    static func clean(_ s: String) -> String {
        String(s.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
    }

    static func jsLiteral(_ s: String?) -> String {
        guard let s else { return "null" }
        return "'\(clean(s))'"
    }

    static let playerHTML = """
    <!doctype html>
    <html><head><meta charset="utf-8">
    <meta name="referrer" content="strict-origin-when-cross-origin">
    <style>html,body{margin:0;background:transparent;overflow:hidden}</style>
    </head><body>
    <div id="holder"><div id="p"></div></div>
    <script>
    var player = null, apiReady = false, pending = null, vol = 60;
    function post(m) { try { window.webkit.messageHandlers.pomo.postMessage(m); } catch (e) {} }
    function onYouTubeIframeAPIReady() {
      apiReady = true;
      if (pending) { var p = pending; pending = null; loadMedia(p.video, p.list, p.volume); }
    }
    function loadMedia(video, list, volume) {
      vol = volume;
      if (!apiReady) { pending = { video: video, list: list, volume: volume }; return; }
      if (player) { try { player.destroy(); } catch (e) {} player = null; }
      document.getElementById('holder').innerHTML = '<div id="p"></div>';
      var vars = { autoplay: 1, controls: 0, playsinline: 1, rel: 0, origin: window.location.origin };
      if (list) { vars.listType = 'playlist'; vars.list = list; }
      var opts = { width: '240', height: '240', playerVars: vars, events: {
        onReady: function (e) { e.target.setVolume(vol); e.target.playVideo(); },
        onStateChange: function (e) { post('state:' + e.data); },
        onError: function (e) { post('error:' + e.data); }
      } };
      if (video) { opts.videoId = video; }
      player = new YT.Player('p', opts);
    }
    function pauseMedia() { if (player && player.pauseVideo) { player.pauseVideo(); } }
    function playMedia() { if (player && player.playVideo) { player.playVideo(); } }
    function setVol(v) { vol = v; if (player && player.setVolume) { player.setVolume(v); } }
    post('page');
    </script>
    <script src="https://www.youtube.com/iframe_api"></script>
    </body></html>
    """
}

/// Receives messages from the player page.
final class ScriptBridge: NSObject, WKScriptMessageHandler {
    var onMessage: ((String) -> Void)?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        onMessage?(message.body as? String ?? "")
    }
}

/// A web view that never takes clicks (it only plays audio).
final class PassthroughWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
