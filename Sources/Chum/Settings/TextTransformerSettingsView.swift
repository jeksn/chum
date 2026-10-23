import SwiftUI
import ChumCore

struct TextTransformerSettingsView: View {
    @State private var order: [String] = AppSettings.transformOrder
    @State private var disabled: Set<String> = Set(AppSettings.disabledTransforms)

    /// Drag-to-reorder state (playlist style): the dragged row follows the
    /// cursor and rows swap once the drag crosses half a row's height.
    @State private var draggingRaw: String?
    @State private var dragOffset: CGFloat = 0

    private let rowHeight: CGFloat = 36
    private let reorderAnimation = Animation.spring(response: 0.25, dampingFraction: 1)

    var body: some View {
        Form {
            Section {
                HotkeyRecorderView("Open Text Transformer:", name: HotkeyManager.openTextTransformer)
            } header: {
                Text("Hotkey")
            } footer: {
                Text("Opens the Launcher on the Text Transformer. Select text in any app first — it reads the selection and replaces it in place when you pick a transformation. Your clipboard is untouched.")
            }

            Section {
                ForEach(Array(order.enumerated()), id: \.element) { _, raw in
                    transformRow(raw: raw)
                        .offset(y: draggingRaw == raw ? dragOffset : 0)
                        .zIndex(draggingRaw == raw ? 1 : 0)
                }
            } header: {
                Text("Transformations")
            } footer: {
                Text("Drag the handle to reorder — the tool shows the transformations in this order. Disable the ones you never use to keep the list short.")
            }
        }
        .formStyle(.grouped)
    }

    private func transformRow(raw: String) -> some View {
        let name = TextTransform(rawValue: raw)?.name ?? raw
        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            handleDrag(raw: raw, translation: value.translation.height)
                        }
                        .onEnded { _ in
                            withAnimation(reorderAnimation) {
                                draggingRaw = nil
                                dragOffset = 0
                            }
                            AppSettings.saveTransformOrder(order)
                        }
                )
            Toggle(name, isOn: enabledBinding(for: raw))
        }
        .frame(height: rowHeight)
    }

    /// Keeps the dragged row under the cursor and swaps it with the neighbor
    /// once the drag passes half a row; the layout jump from the swap is
    /// folded back into the offset so the row never snaps.
    private func handleDrag(raw: String, translation: CGFloat) {
        if draggingRaw != raw {
            draggingRaw = raw
            dragOffset = translation
            return
        }
        dragOffset = translation
        guard let index = order.firstIndex(of: raw) else { return }
        let half = rowHeight / 2
        if translation < -half, index > 0 {
            withAnimation(reorderAnimation) {
                order.swapAt(index, index - 1)
            }
            dragOffset += rowHeight
        } else if translation > half, index < order.count - 1 {
            withAnimation(reorderAnimation) {
                order.swapAt(index, index + 1)
            }
            dragOffset -= rowHeight
        }
    }

    private func enabledBinding(for raw: String) -> Binding<Bool> {
        Binding(
            get: { !disabled.contains(raw) },
            set: { isEnabled in
                if isEnabled {
                    disabled.remove(raw)
                } else {
                    disabled.insert(raw)
                }
                AppSettings.saveDisabledTransforms(Array(disabled))
            }
        )
    }
}
