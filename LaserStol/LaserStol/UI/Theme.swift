import SwiftUI
import AppKit

enum Theme {
    static let cream = Color(red: 0.984, green: 0.965, blue: 0.941)
    static let creamDeep = Color(red: 0.973, green: 0.949, blue: 0.922)
    static let card = Color(red: 1.0, green: 0.992, blue: 0.984)
    static let terracotta = Color(red: 0.773, green: 0.455, blue: 0.365)
    static let terracottaSoft = Color(red: 0.973, green: 0.918, blue: 0.886)
    /// Угольно-коричневый: не Color.primary (в тёмной теме системы он белый).
    static let ink = Color(red: 0.12, green: 0.09, blue: 0.07)
    static let mute = Color(red: 0.36, green: 0.30, blue: 0.26)
    static let line = Color(red: 0.894, green: 0.859, blue: 0.824)
    static let woodLight = Color(red: 0.914, green: 0.792, blue: 0.612)
    static let woodMid = Color(red: 0.843, green: 0.690, blue: 0.502)
    static let woodDark = Color(red: 0.690, green: 0.525, blue: 0.353)
    static let progress = Color(red: 0.400, green: 0.557, blue: 0.365)
    static let stop = Color(red: 0.878, green: 0.243, blue: 0.243)
    static let good = Color(red: 0.310, green: 0.690, blue: 0.408)
    static let dashCut = Color(red: 0.820, green: 0.290, blue: 0.255)
    static let burnDot = Color(red: 0.910, green: 0.580, blue: 0.255)

    static let titleFont = Font.system(size: 22, weight: .semibold, design: .default)
    static let sectionFont = Font.system(size: 13, weight: .semibold)
    static let captionFont = Font.system(size: 11, weight: .regular)
    static let buttonFont = Font.system(size: 12, weight: .medium)

    static var nsCream: NSColor { NSColor(calibratedRed: 0.984, green: 0.965, blue: 0.941, alpha: 1) }
    static var nsInk: NSColor { NSColor(calibratedRed: 0.12, green: 0.09, blue: 0.07, alpha: 1) }
    static var nsTerracotta: NSColor { NSColor(calibratedRed: 0.773, green: 0.455, blue: 0.365, alpha: 1) }
    static var nsWoodLight: NSColor { NSColor(calibratedRed: 0.914, green: 0.792, blue: 0.612, alpha: 1) }
    static var nsWoodMid: NSColor { NSColor(calibratedRed: 0.843, green: 0.690, blue: 0.502, alpha: 1) }
}

struct CompactButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var fill: Color = Theme.terracotta
    var ink: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.buttonFont)
            .foregroundColor(prominent ? ink : Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(prominent ? fill.opacity(configuration.isPressed ? 0.85 : 1) : Theme.creamDeep)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(prominent ? Color.clear : Theme.line, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

struct QuietIconButton: View {
    var systemName: String
    var title: String
    var selected: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 28, height: 28)
                    .foregroundColor(selected ? Theme.terracotta : Theme.ink.opacity(0.72))
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.mute)
            }
            .frame(width: 64)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Theme.terracottaSoft : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct StrengthSlider: View {
    var title: String
    var labels: [String]
    @Binding var value: ProcessStrength

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.ink)
            Slider(
                value: Binding(
                    get: { Double(value.rawValue) },
                    set: { value = ProcessStrength(rawValue: Int($0.rounded())) ?? .medium }
                ),
                in: 0...2,
                step: 1
            )
            .accentColor(Theme.progress)
            HStack {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.mute)
                    if label != labels.last { Spacer() }
                }
            }
        }
    }
}

extension View {
    /// Кремовая поверхность: светлая схема + явные чернила, чтобы подписи не стали белыми в Dark Mode.
    func creamSurface() -> some View {
        self
            .foregroundColor(Theme.ink)
            .accentColor(Theme.terracotta)
            .colorScheme(.light)
            .environment(\.colorScheme, .light)
            .preferredColorScheme(.light)
    }
}

struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                Self.applyLightAppearance(window)
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            Self.applyLightAppearance(window)
            onResolve(window)
        }
    }

    private static func applyLightAppearance(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = Theme.nsCream
    }
}

/// Полоса, за которую можно перетащить окно (скрытый title bar).
struct WindowDragRegion: NSViewRepresentable {
    var leadingReserved: CGFloat = 72

    func makeNSView(context: Context) -> WindowDragView {
        let view = WindowDragView()
        view.leadingReserved = leadingReserved
        return view
    }

    func updateNSView(_ nsView: WindowDragView, context: Context) {
        nsView.leadingReserved = leadingReserved
    }
}

final class WindowDragView: NSView {
    var leadingReserved: CGFloat = 72

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point), point.x >= leadingReserved else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard loc.x >= leadingReserved else { return }
        window?.performWindowDrag(with: event)
    }
}
