import SwiftUI
import UIKit

/// What a submitted passcode led to. It decides the haptic and whether the dots shake.
enum PasscodeResult {
    /// Accepted for good: the PIN unlocked something, or a new PIN was saved.
    case accepted
    /// Accepted, with another step to come, e.g. "Enter it again".
    case next
    /// Wrong or mismatched: shake, buzz, clear.
    case rejected
}

/// A passcode screen in the style of the iOS lock screen: a title, dots, and a round number pad.
/// iOS has no public passcode UI for an app's own PIN, so this mirrors it.
///
/// With `length` set it submits as soon as that many digits are in. Without one (an older PIN,
/// or choosing a new PIN of 4–6 digits) it shows an OK button once 4 digits are in.
struct PasscodeEntry<Footer: View>: View {
    let title: String
    var message: String?
    var length: Int?
    /// Called with the digits once they're all in.
    let submit: (String) -> PasscodeResult
    @ViewBuilder var footer: Footer

    @State private var code = ""
    @State private var shakes = 0

    private var maxLength: Int { length ?? 6 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            dots
                .padding(.top, 20)
                .modifier(Shake(shakes: shakes))
            Text(message ?? " ")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 40, alignment: .top)
                .padding(.top, 14)
                .padding(.horizontal, 24)
            Spacer(minLength: 12)
            keypad
            footer
                .padding(.top, 16)
                .padding(.horizontal, 28)
            Spacer(minLength: 12)
        }
    }

    /// UIKit generators rather than .sensoryFeedback: the success buzz has to play even though
    /// the screen is dismissed in the same moment.
    @MainActor private enum Haptics {
        static func key() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        static func result(_ result: PasscodeResult) {
            switch result {
            case .accepted: UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .next: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .rejected: UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 18) {
            ForEach(0..<max(maxLength, code.count), id: \.self) { i in
                Circle()
                    .strokeBorder(.primary, lineWidth: 1.2)
                    .background(Circle().fill(i < code.count ? Color.primary : .clear))
                    .frame(width: 13, height: 13)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(code.count) of \(maxLength) digits entered")
    }

    private var keypad: some View {
        let rows: [[Key]] = [
            [.digit(1, ""), .digit(2, "ABC"), .digit(3, "DEF")],
            [.digit(4, "GHI"), .digit(5, "JKL"), .digit(6, "MNO")],
            [.digit(7, "PQRS"), .digit(8, "TUV"), .digit(9, "WXYZ")],
            [length == nil && code.count >= 4 ? .ok : .blank, .digit(0, ""), code.isEmpty ? .blank : .delete],
        ]
        return VStack(spacing: 16) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 26) {
                    ForEach(rows[r].indices, id: \.self) { c in
                        button(rows[r][c])
                    }
                }
            }
        }
    }

    private enum Key: Equatable {
        case digit(Int, String)
        case delete, ok, blank
    }

    @ViewBuilder private func button(_ key: Key) -> some View {
        switch key {
        case .digit(let n, let letters):
            Button { type(n) } label: {
                VStack(spacing: 0) {
                    Text("\(n)").font(.system(size: 34, weight: .regular))
                    if !letters.isEmpty {
                        Text(letters).font(.system(size: 10, weight: .semibold)).kerning(2)
                    }
                }
                .frame(width: 78, height: 78)
                .background(Circle().fill(Color(.tertiarySystemFill)))
            }
            .buttonStyle(KeyStyle())
            .accessibilityLabel("\(n)")
        case .delete:
            Button {
                code.removeLast()
                Haptics.key()
            } label: {
                Text("Delete").font(.body).frame(width: 78, height: 78)
            }
            .buttonStyle(.plain)
        case .ok:
            Button { finish() } label: {
                Text("OK").font(.body.weight(.semibold)).frame(width: 78, height: 78)
            }
            .buttonStyle(.plain)
        case .blank:
            Color.clear.frame(width: 78, height: 78).accessibilityHidden(true)
        }
    }

    private func type(_ n: Int) {
        guard code.count < maxLength else { return }
        code.append(String(n))
        Haptics.key()
        if let length, code.count == length {
            // Let the last dot fill before the screen reacts.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                finish()
            }
        }
    }

    private func finish() {
        let entered = code
        let result = submit(entered)
        Haptics.result(result)
        if result == .rejected {
            withAnimation(.default) { shakes += 1 }
        }
        code = ""
    }
}

private struct KeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .brightness(configuration.isPressed ? 0.25 : 0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The lock screen's side-to-side shake for a wrong passcode.
private struct Shake: GeometryEffect {
    var shakes: Int
    var animatableData: CGFloat

    init(shakes: Int) {
        self.shakes = shakes
        animatableData = CGFloat(shakes)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 12 * sin(animatableData * .pi * 4), y: 0))
    }
}
