import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkConnectivity {
    private(set) var isConnected: Bool?
    private(set) var reconnectionCount = 0
    @ObservationIgnored private let monitor = NWPathMonitor()

    init(startMonitoring: Bool = true) {
        guard startMonitoring else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in self?.receive(connected) }
        }
        monitor.start(queue: DispatchQueue(label: "dispatch.network-path"))
    }

    /// Initial connectivity and changes between available interfaces do not request another sync.
    func receive(_ connected: Bool) {
        if isConnected == false && connected { reconnectionCount += 1 }
        isConnected = connected
    }

    deinit { monitor.cancel() }
}
