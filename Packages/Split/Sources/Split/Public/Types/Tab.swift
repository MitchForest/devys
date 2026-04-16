import Foundation

/// Activity indicator state for a tab.
public enum TabActivityIndicator: String, Codable, Sendable {
    case idle
    case busy
}

/// Represents a tab's metadata (read-only snapshot for library consumers)
public struct Tab: Identifiable, Hashable, Sendable {
    public let id: TabID
    public let title: String
    public let icon: String?
    public let isPreview: Bool
    public let isDirty: Bool
    public let activityIndicator: TabActivityIndicator?

    public init(
        id: TabID = TabID(),
        title: String,
        icon: String? = nil,
        isPreview: Bool = false,
        isDirty: Bool = false,
        activityIndicator: TabActivityIndicator? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.isPreview = isPreview
        self.isDirty = isDirty
        self.activityIndicator = activityIndicator
    }

    internal init(from tabItem: TabItem) {
        self.id = TabID(id: tabItem.id)
        self.title = tabItem.title
        self.icon = tabItem.icon
        self.isPreview = tabItem.isPreview
        self.isDirty = tabItem.isDirty
        self.activityIndicator = tabItem.activityIndicator
    }
}
