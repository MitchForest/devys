// SidebarResizeHandle.swift
// Devys - Draggable resize handle for sidebar panels.
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import SwiftUI
import UI

struct SidebarResizeHandle: View {
    @Environment(\.devysTheme) private var theme

    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let persistenceKey: String

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var dragStartWidth: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(theme.surface)
            .frame(width: 6)
            .overlay {
                if isHovered || isDragging {
                    Rectangle()
                        .fill(theme.visibleAccent.opacity(0.4))
                        .frame(width: 2)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartWidth = width
                        }
                        let newWidth = min(maxWidth, max(minWidth, dragStartWidth + value.translation.width))
                        // Update the binding directly but using global coordinate space
                        // to avoid layout feedback loops
                        width = newWidth
                    }
                    .onEnded { _ in
                        isDragging = false
                        if !isHovered {
                            NSCursor.pop()
                        }
                        UserDefaults.standard.set(Double(width), forKey: persistenceKey)
                    }
            )
    }
}
