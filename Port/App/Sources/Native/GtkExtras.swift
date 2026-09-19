// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Native GTK pieces SwiftCrossUI 0.9.0 does not provide, attached to its
// widgets through the backend's inspection hook:
//   - `.contextMenu(...)`: right-click opens a popover with actions
//     (upstream: RecordingContextMenu);
//   - `.recordingDragSource(id)` / `.recordingDropTarget { id in }`: drag a
//     recording row onto a sidebar folder (upstream: .draggable/.dropDestination);
//   - `SystemIcon`: the desktop's own symbolic icon theme.
// Linux only; the Windows build supplies WinUI equivalents.

#if canImport(GtkBackend)
import CGtk
import Foundation
import Gtk
import GtkBackend
import SwiftCrossUI

// MARK: - Context menus

struct ContextMenuItem {
    let title: String
    let isDestructive: Bool
    let action: () -> Void

    init(_ title: String, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isDestructive = destructive
        self.action = action
    }
}

/// Per-widget state: the latest items, and the gesture and popover once made.
/// Reinterpret a GObject pointer as the concrete GTK struct a C call expects.
@inline(__always)
private func cast<T>(_ pointer: UnsafeMutableRawPointer) -> UnsafeMutablePointer<T> {
    pointer.assumingMemoryBound(to: T.self)
}

@MainActor
private final class ContextMenuBinding {
    var items: [ContextMenuItem] = []
    var gesture: GestureClick?
    var popover: UnsafeMutablePointer<GtkPopover>?
    var buttons: [Gtk.Button] = []
    var box: Gtk.Box?
}

@MainActor
private var contextMenus: [UnsafeMutableRawPointer: ContextMenuBinding] = [:]

extension View {
    /// Right-click (or long-press on touch) shows `items` in a popover at the
    /// pointer. The items are refreshed on every update, so they always act on
    /// the current value of whatever they capture.
    func contextMenu(_ items: [ContextMenuItem]) -> some View {
        inspect([.onCreate, .afterUpdate]) { widget in
            let key = UnsafeMutableRawPointer(widget.widgetPointer)
            let binding = contextMenus[key] ?? ContextMenuBinding()
            contextMenus[key] = binding
            binding.items = items
            guard binding.gesture == nil else { return }

            let gesture = GestureClick()
            gtk_gesture_single_set_button(OpaquePointer(gesture.gobjectPointer), 3)
            gesture.pressed = { [weak widget] _, _, x, y in
                guard let widget else { return }
                showPopover(binding: binding, over: widget, x: x, y: y)
            }
            widget.addEventController(gesture)
            binding.gesture = gesture
        }
    }
}

@MainActor
private func showPopover(binding: ContextMenuBinding, over widget: Gtk.Widget, x: Double, y: Double) {
    if let old = binding.popover {
        gtk_widget_unparent(cast(UnsafeMutableRawPointer(old)))
        binding.popover = nil
    }
    let box = Gtk.Box(orientation: .vertical, spacing: 0)
    var buttons: [Gtk.Button] = []
    guard let popoverWidget = gtk_popover_new() else { return }
    let popover: UnsafeMutablePointer<GtkPopover> = cast(UnsafeMutableRawPointer(popoverWidget))
    for item in binding.items {
        let button = Gtk.Button(label: item.title)
        gtk_button_set_has_frame(cast(UnsafeMutableRawPointer(button.gobjectPointer)), 0)
        if item.isDestructive { gtk_widget_add_css_class(button.widgetPointer, "destructive-action") }
        button.clicked = { _ in
            gtk_popover_popdown(popover)
            item.action()
        }
        box.add(button)
        buttons.append(button)
    }
    gtk_popover_set_child(popover, box.widgetPointer)
    gtk_widget_set_parent(popoverWidget, widget.widgetPointer)
    var rect = GdkRectangle(x: Int32(x), y: Int32(y), width: 1, height: 1)
    gtk_popover_set_pointing_to(popover, &rect)
    gtk_popover_set_has_arrow(popover, 0)
    binding.popover = popover
    binding.buttons = buttons
    binding.box = box
    gtk_popover_popup(popover)
}

// MARK: - Drag and drop of recordings

/// G_TYPE_STRING: fundamental type 16, shifted by G_TYPE_FUNDAMENTAL_SHIFT (2).
private let gTypeString = GType(16 << 2)
private let dragPrefix = "openmila-recording:"

@MainActor
private final class DropBinding {
    var onDrop: (UUID) -> Void = { _ in }
    var attached = false
}

@MainActor
private var dropTargets: [UnsafeMutableRawPointer: DropBinding] = [:]
@MainActor
private var dragSources: [UnsafeMutableRawPointer: String] = [:]

extension View {
    /// Lets this view be dragged as the recording `id`.
    func recordingDragSource(_ id: UUID) -> some View {
        inspect([.onCreate, .afterUpdate]) { widget in
            let key = UnsafeMutableRawPointer(widget.widgetPointer)
            let payload = dragPrefix + id.uuidString
            let firstTime = dragSources[key] == nil
            dragSources[key] = payload
            guard firstTime else { return }
            attachDragSource(to: widget, payload: payload)
        }
    }

    /// (declared below)
    /// Accepts dropped recordings and calls `onDrop` with each one's id.
    func recordingDropTarget(_ onDrop: @escaping (UUID) -> Void) -> some View {
        inspect([.onCreate, .afterUpdate]) { widget in
            let key = UnsafeMutableRawPointer(widget.widgetPointer)
            let binding = dropTargets[key] ?? DropBinding()
            dropTargets[key] = binding
            binding.onDrop = onDrop
            guard !binding.attached, let target = gtk_drop_target_new(gTypeString, GDK_ACTION_MOVE) else { return }
            binding.attached = true
            let userData = Unmanaged.passRetained(binding).toOpaque()
            let handler: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<GValue>?, Double, Double, UnsafeMutableRawPointer?) -> gboolean = {
                _, value, _, _, data in
                guard let value, let data, let cString = g_value_get_string(value) else { return 0 }
                let text = String(cString: cString)
                guard text.hasPrefix(dragPrefix), let id = UUID(uuidString: String(text.dropFirst(dragPrefix.count))) else { return 0 }
                let binding = Unmanaged<DropBinding>.fromOpaque(data).takeUnretainedValue()
                MainActor.assumeIsolated { binding.onDrop(id) }
                return 1
            }
            g_signal_connect_data(UnsafeMutableRawPointer(target), "drop",
                                  unsafeBitCast(handler, to: GCallback.self), userData, nil, GConnectFlags(rawValue: 0))
            gtk_widget_add_controller(widget.widgetPointer, target)
        }
    }
}

@MainActor
private func attachDragSource(to widget: Gtk.Widget, payload: String) {
    guard let source = gtk_drag_source_new() else { return }
    gtk_drag_source_set_actions(source, GDK_ACTION_MOVE)
    let value = UnsafeMutablePointer<GValue>.allocate(capacity: 1)
    value.initialize(to: GValue())
    defer { g_value_unset(value); value.deinitialize(count: 1); value.deallocate() }
    g_value_init(value, gTypeString)
    g_value_set_string(value, payload)
    if let provider = gdk_content_provider_new_for_value(value) {
        gtk_drag_source_set_content(source, provider)
        g_object_unref(UnsafeMutableRawPointer(provider))
    }
    gtk_widget_add_controller(widget.widgetPointer, source)
}

// MARK: - Icons

/// An icon from the desktop's symbolic icon theme, sized like body text.
struct SystemIcon: GtkWidgetRepresentable {
    let name: String
    var size: Int = 16

    func makeGtkWidget(context: Context) -> Gtk.Image {
        let image = Gtk.Image(iconName: name)
        gtk_image_set_pixel_size(OpaquePointer(image.gobjectPointer), Int32(size))
        return image
    }

    func updateGtkWidget(_ image: Gtk.Image, context: Context) {
        gtk_image_set_from_icon_name(OpaquePointer(image.gobjectPointer), name)
        gtk_image_set_pixel_size(OpaquePointer(image.gobjectPointer), Int32(size))
    }
}
#endif
