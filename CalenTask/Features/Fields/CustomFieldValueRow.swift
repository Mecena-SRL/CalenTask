import SwiftUI
import SwiftData

/// Editor di un valore di campo custom per una task (D32). Crea il valore
/// alla prima modifica; ogni tipo ha il suo controllo, sempre su DSFieldRow.
struct CustomFieldValueRow: View {
    @Environment(\.modelContext) private var modelContext
    let field: CustomFieldDefinition
    let task: TodoTask

    @Query private var values: [CustomFieldValue]

    init(field: CustomFieldDefinition, task: TodoTask) {
        self.field = field
        self.task = task
        let fieldID = field.id
        let taskID = task.id
        _values = Query(filter: #Predicate<CustomFieldValue> {
            $0.fieldID == fieldID && $0.taskID == taskID && $0.deletedAt == nil
        })
    }

    private var value: CustomFieldValue? { values.first }

    var body: some View {
        DSFieldRow(
            label: field.name,
            systemImage: field.type.systemImage,
            tint: hasContent ? .indigo : Color.secondary.opacity(0.55)
        ) {
            editor
        }
    }

    private var hasContent: Bool {
        guard let value else { return false }
        return !value.valueRaw.isEmpty
    }

    @ViewBuilder
    private var editor: some View {
        switch field.type {
        case .text, .url:
            TextField(field.type == .url ? "https://…" : "Aggiungi", text: rawBinding)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .foregroundStyle(.secondary)
                #if os(iOS)
                .keyboardType(field.type == .url ? .URL : .default)
                #endif

        case .number:
            TextField("0", text: rawBinding)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 120)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif

        case .date:
            HStack(spacing: DS.xs) {
                DatePicker(
                    field.name,
                    selection: Binding(
                        get: { value?.dateValue ?? .now },
                        set: { newDate in withValue { $0.dateValue = newDate } }
                    ),
                    displayedComponents: [.date]
                )
                .labelsHidden()
                if hasContent {
                    Button {
                        withValue { $0.valueRaw = "" }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

        case .select:
            Menu {
                Picker(field.name, selection: rawBinding) {
                    Text("—").tag("")
                    ForEach(field.options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            } label: {
                Text(value?.valueRaw.isEmpty == false ? value!.valueRaw : "Scegli")
                    .font(.dsMeta)
                    .foregroundStyle(hasContent ? Color.indigo : Color.secondary)
                    .padding(.horizontal, DS.s)
                    .padding(.vertical, 3)
                    .background(
                        (hasContent ? Color.indigo : Color.secondary).opacity(0.12),
                        in: Capsule()
                    )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

        case .checkbox:
            Toggle("", isOn: Binding(
                get: { value?.boolValue ?? false },
                set: { newValue in withValue { $0.boolValue = newValue } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }

    private var rawBinding: Binding<String> {
        Binding(
            get: { value?.valueRaw ?? "" },
            set: { newValue in withValue { $0.valueRaw = newValue } }
        )
    }

    /// Fetch-or-create: il valore nasce alla prima modifica.
    private func withValue(_ mutate: (CustomFieldValue) -> Void) {
        if let value {
            mutate(value)
            value.updatedAt = .now
        } else {
            let created = CustomFieldValue(
                workspaceID: task.workspaceID, fieldID: field.id, taskID: task.id
            )
            mutate(created)
            modelContext.insert(created)
        }
        task.updatedAt = .now
    }
}
