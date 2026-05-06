#if os(tvOS)
import SwiftUI

struct NameEntryOverlay: View {
    @ObservedObject var coordinator: NameEntryCoordinator
    @State private var name: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 40) {
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
