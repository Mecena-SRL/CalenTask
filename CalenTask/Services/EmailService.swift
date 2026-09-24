import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
import MessageUI
#endif

/// Invio dell'ODG (call sheet) alla troupe (D58): compositore email di
/// sistema PRECOMPILATO — destinatari, oggetto, testo e PDF allegato.
/// "Automatico" senza backend = un tap e la mail è pronta da inviare;
/// l'invio schedulato vero arriverà con Supabase (D45).
@MainActor
enum EmailService {
    static var canCompose: Bool {
        #if os(macOS)
        NSSharingService(named: .composeEmail) != nil
        #else
        MFMailComposeViewController.canSendMail()
        #endif
    }

    #if os(macOS)
    static func compose(
        to recipients: [String], subject: String, body: String, attachment: URL?
    ) {
        guard let service = NSSharingService(named: .composeEmail) else { return }
        service.recipients = recipients
        service.subject = subject
        var items: [Any] = [body]
        if let attachment { items.append(attachment) }
        service.perform(withItems: items)
    }
    #endif
}

#if os(iOS)
/// Wrapper SwiftUI del compositore Mail con allegato (iOS).
struct MailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    let attachment: URL?

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        if let attachment, let data = try? Data(contentsOf: attachment) {
            controller.addAttachmentData(
                data, mimeType: "application/pdf",
                fileName: attachment.lastPathComponent
            )
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: MFMailComposeViewController, context: Context
    ) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult, error: Error?
        ) {
            controller.dismiss(animated: true)
        }
    }
}
#endif
