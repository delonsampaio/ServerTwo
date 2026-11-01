import CloudKit
import CoreData
import Foundation
import Observation
import os
import PickleballKit

/// What iCloud sync last did, so Settings can show it. SwiftData mirrors the
/// history store through CloudKit without any visible sign: a failed upload
/// (a schema that was never deployed to Production, a full iCloud, no account)
/// looks exactly like "no data" on the next install. This listens to the
/// mirroring events the system already posts and keeps the latest import and
/// export of this launch, plus the iCloud account status.
@MainActor
@Observable
final class CloudSyncMonitor {
    struct Outcome: Equatable {
        let finished: Date
        /// `nil` when the event succeeded.
        let failure: String?
    }

    private(set) var accountStatus = "Checking..."
    /// Latest download from iCloud and upload to it since the app launched.
    private(set) var lastImport: Outcome?
    private(set) var lastExport: Outcome?

    @ObservationIgnored private let log = Logger(subsystem: "com.delonsampaio.ServerTwo", category: "CloudSync")
    /// Lives as long as the app, so the observer is never removed.
    init() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            guard let event = notification.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                  let finished = event.endDate
            else { return }
            let failure = event.error.map { error -> String in
                let nsError = error as NSError
                return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
            }
            let type = event.type
            MainActor.assumeIsolated { self?.record(type: type, finished: finished, failure: failure) }
        }
    }

    func refreshAccountStatus() async {
        let container = CKContainer(identifier: PersistenceContainer.cloudKitContainerIdentifier)
        do {
            switch try await container.accountStatus() {
            case .available: accountStatus = "Signed in to iCloud"
            case .noAccount: accountStatus = "Not signed in to iCloud"
            case .restricted: accountStatus = "iCloud is restricted on this device"
            case .couldNotDetermine: accountStatus = "iCloud status unknown"
            case .temporarilyUnavailable: accountStatus = "iCloud is temporarily unavailable"
            @unknown default: accountStatus = "iCloud status unknown"
            }
        } catch {
            accountStatus = "iCloud check failed: \(error.localizedDescription)"
        }
        log.info("iCloud account: \(self.accountStatus, privacy: .public)")
    }

    private func record(type: NSPersistentCloudKitContainer.EventType, finished: Date, failure: String?) {
        let outcome = Outcome(finished: finished, failure: failure)
        switch type {
        case .import: lastImport = outcome
        case .export: lastExport = outcome
        case .setup: break
        @unknown default: break
        }
        if let failure {
            log.error("Sync \(String(describing: type), privacy: .public) failed: \(failure, privacy: .public)")
        } else {
            log.info("Sync \(String(describing: type), privacy: .public) succeeded")
        }
    }
}
