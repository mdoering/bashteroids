import Foundation
import Combine

@MainActor
final class NameEntryCoordinator: ObservableObject {
    static let shared = NameEntryCoordinator()

    struct Request: Identifiable {
        let id = UUID()
        let slot: Int
        let current: String
        let completion: (String?) -> Void
    }

    @Published private(set) var request: Request?

    func requestName(forSlot slot: Int, current: String,
                     completion: @escaping (String?) -> Void) {
        request = Request(slot: slot, current: current, completion: completion)
    }

    func submit(_ name: String) {
        let req = request
        request = nil
        req?.completion(name)
    }

    func cancel() {
        let req = request
        request = nil
        req?.completion(nil)
    }
}
