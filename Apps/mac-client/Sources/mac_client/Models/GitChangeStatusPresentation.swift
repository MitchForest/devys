import Git

extension GitChangeStatus {
    var appIconName: String {
        switch self {
        case .modified:
            "pencil.circle.fill"
        case .added:
            "plus.circle.fill"
        case .deleted:
            "minus.circle.fill"
        case .renamed:
            "arrow.right.circle.fill"
        case .copied:
            "doc.on.doc.fill"
        case .untracked:
            "questionmark.circle.fill"
        case .ignored:
            "eye.slash.circle.fill"
        case .unmerged:
            "exclamationmark.triangle.fill"
        }
    }
}
