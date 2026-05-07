#if os(tvOS)
import SwiftUI

struct NameEntryOverlay: View {
    @ObservedObject var coordinator: NameEntryCoordinator
    @State private var name: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 30) {
                Text("PLAYER \((coordinator.request?.slot ?? 0) + 1) NAME")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)

                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 600)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .focused($focused)
                    .onSubmit { submit() }

                let recents = Array(RecentNames.all.prefix(4))
                if !recents.isEmpty {
                    VStack(spacing: 8) {
                        Text("RECENT")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.gray)
                        ForEach(recents, id: \.self) { recent in
                            Button(recent) {
                                name = recent
                                submit()
                            }
                            .font(.system(size: 28))
                        }
                    }
                }

                HStack(spacing: 24) {
                    Button("Cancel") { coordinator.cancel() }
                    Button("Done") { submit() }
                }
                .font(.system(size: 28, weight: .semibold))
            }
            .padding(60)
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
