import Contacts
import Foundation
import SwiftData

/// CRM-1 (D72): il ponte con Apple Contacts. Import selettivo nella rubrica
/// di produzione e aggiornamento (telefono/email) dei contatti collegati.
/// Zero backend: tutto on-device via CNContactStore.
enum ContactsImportService {
    /// Un contatto del dispositivo, ridotto ai campi che ci servono.
    struct DeviceContact: Identifiable, Hashable, Sendable {
        let id: String          // CNContact.identifier
        let fullName: String
        let organization: String
        let phone: String
        let email: String
    }

    static var isAuthorized: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized, .limited: return true
        default: return false
        }
    }

    static var isDenied: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        return status == .denied || status == .restricted
    }

    static func requestAccess() async -> Bool {
        if isAuthorized { return true }
        let store = CNContactStore()
        return (try? await store.requestAccess(for: .contacts)) ?? false
    }

    private static var fetchKeys: [CNKeyDescriptor] {
        [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
    }

    /// Tutta la rubrica del device (chiamare fuori dal main thread).
    static func fetchDeviceContacts() throws -> [DeviceContact] {
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: fetchKeys)
        request.sortOrder = .givenName
        var result: [DeviceContact] = []
        try store.enumerateContacts(with: request) { contact, _ in
            if let device = deviceContact(from: contact) {
                result.append(device)
            }
        }
        return result
    }

    private static func deviceContact(from contact: CNContact) -> DeviceContact? {
        let name = CNContactFormatter.string(from: contact, style: .fullName)
            ?? contact.organizationName
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return DeviceContact(
            id: contact.identifier,
            fullName: trimmed,
            organization: contact.organizationName,
            phone: contact.phoneNumbers.first?.value.stringValue ?? "",
            email: (contact.emailAddresses.first?.value as String?) ?? ""
        )
    }

    /// Importa i contatti scelti nello spazio: dedupe per identifier, poi per
    /// email (la stessa chiave naturale del dedupe CloudKit). Ritorna quanti
    /// sono stati creati (gli altri sono stati collegati/aggiornati).
    @MainActor
    @discardableResult
    static func importContacts(
        _ picks: [DeviceContact],
        workspaceID: UUID,
        into context: ModelContext
    ) throws -> Int {
        let existing = try context.fetch(FetchDescriptor<Contact>(
            predicate: #Predicate { $0.deletedAt == nil }
        )).filter { $0.workspaceID == workspaceID }

        var created = 0
        for pick in picks {
            if let linked = existing.first(where: { $0.contactIdentifier == pick.id }) {
                update(linked, from: pick)
            } else if let byEmail = existing.first(where: {
                !pick.email.isEmpty
                    && $0.email.caseInsensitiveCompare(pick.email) == .orderedSame
            }) {
                byEmail.contactIdentifier = pick.id
                update(byEmail, from: pick)
            } else {
                let contact = Contact(
                    workspaceID: workspaceID,
                    name: pick.fullName,
                    kind: .person,
                    phone: pick.phone,
                    email: pick.email,
                    notes: pick.organization
                )
                contact.contactIdentifier = pick.id
                context.insert(contact)
                created += 1
            }
        }
        try context.save()
        return created
    }

    private static func update(_ contact: Contact, from device: DeviceContact) {
        var changed = false
        if !device.phone.isEmpty, contact.phone != device.phone {
            contact.phone = device.phone
            changed = true
        }
        if !device.email.isEmpty, contact.email != device.email {
            contact.email = device.email
            changed = true
        }
        if changed {
            contact.updatedAt = .now
        }
    }

    /// "Aggiorna dai Contatti": rilegge telefono/email del contatto collegato.
    /// Ritorna false se il contatto di sistema non esiste più.
    @MainActor
    @discardableResult
    static func refresh(_ contact: Contact, in context: ModelContext) -> Bool {
        guard let identifier = contact.contactIdentifier else { return false }
        let store = CNContactStore()
        guard let device = try? store.unifiedContact(
            withIdentifier: identifier, keysToFetch: fetchKeys
        ), let deviceContact = deviceContact(from: device) else {
            return false
        }
        update(contact, from: deviceContact)
        try? context.save()
        return true
    }
}
