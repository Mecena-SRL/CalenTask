import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Receives notification taps and routes them to the task detail.
/// Swift 5 mode: delegate callbacks arrive off the main actor, hop explicitly.
final class AppDelegate: NSObject, UNUserNotificationCenterDelegate {
    private func registerAsDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard
            let raw = response.notification.request.content.userInfo["taskID"] as? String,
            let taskID = UUID(uuidString: raw)
        else { return }
        await MainActor.run {
            AppRouter.shared.open(taskID: taskID)
        }
    }
}

#if os(iOS)
extension AppDelegate: UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerAsDelegate()
        return true
    }
}
#else
extension AppDelegate: NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        registerAsDelegate()
    }

    /// Chiusura normale: il prossimo avvio non è "sicuro".
    func applicationWillTerminate(_ notification: Notification) {
        LaunchGuard.markLaunchCompleted()
    }
}
#endif
