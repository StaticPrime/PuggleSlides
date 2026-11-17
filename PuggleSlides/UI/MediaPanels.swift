import AppKit
import PuggleSlidesKit
import SwiftUI

/// Format options for a video ("Video playback") or a sound ("Audio playback").
struct MediaPlaybackSections: View {
    let element: SlideElement
    let clip: MediaClip
    let controller: PresentationController
    @State private var start = ""
    @State private var end = ""
    @State private var duration: Double?

    var body: some View {
        if clip.isVideo {
            PanelSection(title: "Video playback") {
                Picker("", selection: Binding(get: { clip.playback }, set: { controller.setClipPlayback($0) })) {
                    Text("Play (on click)").tag(MediaPlayback.onClick)
                    Text("Play (automatically)").tag(MediaPlayback.automatically)
                    Text("Play (manually)").tag(MediaPlayback.manually)
                }
                .labelsHidden()
                .frame(width: 220)
                HStack(spacing: 10) {
                    timeField("Start at", text: $start)
                    timeField("End at", text: $end)
                }
                Toggle("Mute audio", isOn: Binding(get: { clip.isMuted }, set: { controller.setClipMuted($0) }))
                    .font(.system(size: 13))
            }
        } else {
            PanelSection(title: "Audio playback") {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Start playing").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                    Picker("", selection: Binding(get: { clip.playback == .automatically ? MediaPlayback.automatically : .onClick },
                                                  set: { controller.setClipPlayback($0) })) {
                        Text("On click").tag(MediaPlayback.onClick)
                        Text("Automatically").tag(MediaPlayback.automatically)
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                AdjustmentSlider(title: "Volume when presenting", value: clip.volume, range: 0...1) { controller.setClipVolume($0) }
                Toggle("Hide icon when presenting", isOn: Binding(get: { clip.hidesWhenPresenting }, set: { controller.setClipHidesWhenPresenting($0) }))
                    .disabled(clip.playback != .automatically)
                    .help("Only a sound that starts automatically can hide its icon")
                Toggle("Loop audio", isOn: Binding(get: { clip.loops }, set: { controller.setClipLoops($0) }))
                Toggle("Stop on slide change", isOn: Binding(get: { clip.stopsOnSlideChange }, set: { controller.setClipStopsOnSlideChange($0) }))
            }
            .font(.system(size: 13))
        }
    }

    private func timeField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            PanelField(placeholder: "0:00", text: text)
                .frame(width: 90)
                .onSubmit(commitTimes)
        }
        .task(id: clip) {
            start = Self.text(clip.start ?? 0)
            duration = await MediaFiles.duration(of: clip, in: controller.presentation)
            end = (clip.end ?? duration).map(Self.text) ?? ""
        }
    }

    private func commitTimes() {
        let from = Self.seconds(start)
        var to = Self.seconds(end)
        // The end of the file is no trim at all.
        if let length = duration, let value = to, abs(value - length) < 0.5 { to = nil }
        controller.setClipTrim(start: from, end: to)
    }

    /// "1:05", "0:07.5".
    static func text(_ seconds: Double) -> String {
        let whole = Int(seconds), fraction = seconds - Double(whole)
        let base = "\(whole / 60):" + String(format: "%02d", whole % 60)
        return fraction >= 0.05 ? base + String(format: ".%d", Int((fraction * 10).rounded())) : base
    }

    /// Seconds from "1:05", "65" or "1:05.5"; nil when empty or not a time.
    static func seconds(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }
}
