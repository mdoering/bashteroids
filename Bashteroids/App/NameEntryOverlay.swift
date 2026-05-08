#if os(tvOS) || os(iOS)
import SwiftUI

struct NameEntryOverlay: View {
    @ObservedObject var coordinator: NameEntryCoordinator
    @State private var name: String = ""
    @FocusState private var focused: Bool

    // tvOS is viewed from across the room — bigger fonts and a wider field.
    // iPad/Catalyst sit close, so scale everything down.
    #if os(tvOS)
    private let titleFont:    CGFloat = 36
    private let fieldFont:    CGFloat = 48
    private let buttonFont:   CGFloat = 28
    private let recentLabel:  CGFloat = 18
    private let recentFont:   CGFloat = 28
    private let fieldWidth:   CGFloat = 600
    private let outerPadding: CGFloat = 60
    private let stackSpacing: CGFloat = 30
    #else
    private let titleFont:    CGFloat = 22
    private let fieldFont:    CGFloat = 28
    private let buttonFont:   CGFloat = 18
    private let recentLabel:  CGFloat = 12
    private let recentFont:   CGFloat = 18
    private let fieldWidth:   CGFloat = 320
    private let outerPadding: CGFloat = 30
    private let stackSpacing: CGFloat = 18
    #endif

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: stackSpacing) {
                Text("PLAYER \((coordinator.request?.slot ?? 0) + 1) NAME")
                    .font(.system(size: titleFont, weight: .bold))
                    .foregroundStyle(.white)

                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: fieldFont))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: fieldWidth)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .focused($focused)
                    .onSubmit { submit() }

                let recents = Array(RecentNames.all.prefix(4))
                if !recents.isEmpty {
                    VStack(spacing: 8) {
                        Text("RECENT")
                            .font(.system(size: recentLabel, weight: .semibold))
                            .foregroundStyle(.gray)
                        ForEach(recents, id: \.self) { recent in
                            Button(recent) {
                                name = recent
                                submit()
                            }
                            .font(.system(size: recentFont))
                        }
                    }
                }

                HStack(spacing: 24) {
                    Button("Cancel") { coordinator.cancel() }
                    Button("Done") { submit() }
                }
                .font(.system(size: buttonFont, weight: .semibold))
            }
            .padding(outerPadding)
        }
        .onAppear {
            name = coordinator.request?.current ?? ""
            focused = true
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let final = trimmed.isEmpty ? (coordinator.request?.current ?? "") : trimmed
        coordinator.submit(String(final.prefix(8)))
    }
}
#endif
