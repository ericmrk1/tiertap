#if os(iOS)
import SwiftUI

// MARK: - Adaptive sheet: full-screen on iPad, sheet on iPhone

extension View {
    /// Presents content as full-screen cover on iPad (uses entire screen) and as sheet on iPhone.
    func adaptiveSheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(AdaptiveSheetModifier(isPresented: isPresented, onDismiss: onDismiss, sheetContent: content))
    }

    /// Presents content by item as full-screen cover on iPad and as sheet on iPhone.
    func adaptiveSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        modifier(AdaptiveSheetItemModifier(item: item, onDismiss: onDismiss, content: content))
    }
}

private struct AdaptiveSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var onDismiss: (() -> Void)?
    @ViewBuilder let sheetContent: () -> SheetContent

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    func body(content: Content) -> some View {
        if isIPad {
            content.fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss, content: sheetContent)
        } else {
            content.sheet(isPresented: $isPresented, onDismiss: onDismiss, content: sheetContent)
        }
    }
}

private struct AdaptiveSheetItemModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    var onDismiss: (() -> Void)?
    @ViewBuilder let content: (Item) -> SheetContent

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    func body(content view: Content) -> some View {
        if isIPad {
            view.fullScreenCover(item: $item, onDismiss: onDismiss, content: content)
        } else {
            view.sheet(item: $item, onDismiss: onDismiss, content: content)
        }
    }
}
#endif
