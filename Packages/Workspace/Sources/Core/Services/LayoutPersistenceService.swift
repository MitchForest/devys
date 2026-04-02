// LayoutPersistenceService.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation

@MainActor
@Observable
public final class LayoutPersistenceService {
    private let key = "com.devys.defaultPanelLayout"

    public init() {}

    public func loadDefaultLayout() -> PanelLayout {
        guard let data = UserDefaults.standard.data(forKey: key),
              let layout = try? JSONDecoder().decode(PanelLayout.self, from: data) else {
            return .default
        }
        return layout
    }

    public func saveDefaultLayout(_ layout: PanelLayout) {
        if let data = try? JSONEncoder().encode(layout) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
