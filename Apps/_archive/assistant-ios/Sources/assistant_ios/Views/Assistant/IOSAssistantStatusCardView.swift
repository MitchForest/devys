import SwiftUI
import UI

struct IOSAssistantStatusCardView: View {
    @Environment(\.devysTheme) private var theme

    let mode: IOSAssistantMode
    let density: IOSAssistantCardDensity
    let namespace: Namespace.ID
    let maxExpandedHeight: CGFloat
    let integrationStatus: IOSAssistantIntegrationStatus
    let onConnectTap: () -> Void
    @State private var celebrationScale: CGFloat = 1

    var body: some View {
        Group {
            switch density {
            case .compact:
                compactCard
            case .medium:
                mediumCard
            case .expanded:
                expandedCard
            }
        }
    }

    private var compactCard: some View {
        HStack(spacing: DevysSpacing.space2) {
            modeIcon
            Spacer(minLength: 0)
            metricText(compactMetric)
        }
        .padding(.horizontal, DevysSpacing.space4)
        .frame(height: 44)
        .cardStyle(radius: DevysSpacing.radiusXl, theme: theme)
        .matchedGeometryEffect(id: "ios-assistant-status-card", in: namespace)
    }

    private var mediumCard: some View {
        HStack(spacing: DevysSpacing.space3) {
            RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                .fill(mode.accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: DevysSpacing.space1) {
                HStack(spacing: DevysSpacing.space2) {
                    modeIcon
                    Text(mode.shortTitle.uppercased())
                        .font(DevysTypography.heading)
                        .foregroundStyle(mode.accent)
                    Spacer(minLength: 0)
                    metricText(compactMetric)
                }

                Text(headline)
                    .font(DevysTypography.body)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Text(detail)
                    .font(DevysTypography.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(DevysSpacing.space4)
        .frame(minHeight: 72)
        .cardStyle(radius: DevysSpacing.radiusLg, theme: theme)
        .matchedGeometryEffect(id: "ios-assistant-status-card", in: namespace)
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space4) {
            HStack(spacing: DevysSpacing.space2) {
                modeIcon
                Text(mode.title)
                    .font(DevysTypography.label)
                    .foregroundStyle(theme.text)
                Spacer(minLength: 0)
                metricText(compactMetric)
            }

            expandedContent
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .padding(DevysSpacing.space4)
        .frame(maxWidth: .infinity, maxHeight: maxExpandedHeight, alignment: .topLeading)
        .cardStyle(radius: DevysSpacing.radius, theme: theme)
        .matchedGeometryEffect(id: "ios-assistant-status-card", in: namespace)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(mode.title) detail")
    }

    @ViewBuilder
    private var expandedContent: some View {
        if integrationStatus != .connected {
            disconnectedState
        } else if !mode.hasData {
            allCaughtUpState
        } else {
            switch mode {
            case .calendar:
                calendarState
            case .gmail:
                gmailState
            case .gchat:
                gchatState
            }
        }
    }
}

private extension IOSAssistantStatusCardView {
    var modeIcon: some View {
        Image(systemName: mode.icon)
            .font(.system(size: DevysSpacing.iconMd))
            .foregroundStyle(mode.accent)
    }

    func metricText(_ text: String) -> some View {
        Text(text)
            .font(DevysTypography.xl)
            .foregroundStyle(mode.accent)
            .id(text)
            .transition(
                .asymmetric(
                    insertion: .offset(y: 4).combined(with: .opacity),
                    removal: .offset(y: -4).combined(with: .opacity)
                )
            )
            .animation(DevysAnimation.fast, value: text)
    }

    var compactMetric: String {
        switch integrationStatus {
        case .connected:
            return mode.status.metric
        case .disconnected:
            return "connect"
        case .error:
            return "error"
        }
    }

    var headline: String {
        switch integrationStatus {
        case .connected:
            return mode.status.headline
        case .disconnected:
            return mode.emptyStatePrompt
        case .error:
            return "Connection needs attention."
        }
    }

    var detail: String {
        switch integrationStatus {
        case .connected:
            return mode.status.detail
        case .disconnected:
            return "No account linked."
        case .error:
            return "Open integrations to reconnect."
        }
    }

    var disconnectedState: some View {
        VStack(alignment: .center, spacing: DevysSpacing.space3) {
            Spacer(minLength: DevysSpacing.space1)
            Image(systemName: mode.icon)
                .font(.system(size: DevysSpacing.iconXl))
                .foregroundStyle(theme.textTertiary)

            Text(mode.emptyStatePrompt)
                .font(DevysTypography.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)

            Button("Connect") {
                onConnectTap()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DevysSpacing.space3)
            .padding(.vertical, DevysSpacing.space2)
            .background(mode.accent.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
            .foregroundStyle(mode.accent)
            .accessibilityLabel("Connect \(mode.title)")
            .accessibilityHint("Open integration settings")
            Spacer(minLength: DevysSpacing.space1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var allCaughtUpState: some View {
        VStack(alignment: .center, spacing: DevysSpacing.space3) {
            Spacer(minLength: DevysSpacing.space1)
            Image(systemName: "checkmark.circle")
                .font(.system(size: DevysSpacing.iconXl))
                .foregroundStyle(mode.accent)
                .scaleEffect(celebrationScale)
                .onAppear {
                    animateCelebrationPop()
                }

            Text(mode.noDataLabel)
                .font(DevysTypography.body)
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: DevysSpacing.space1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var calendarState: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            monthGrid

            ScrollView {
                VStack(alignment: .leading, spacing: DevysSpacing.space2) {
                    ForEach(Array(mode.events.enumerated()), id: \.element.id) { index, event in
                        HStack(spacing: DevysSpacing.space2) {
                            RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                                .fill(mode.accent)
                                .frame(width: 3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(DevysTypography.body)
                                    .foregroundStyle(theme.text)
                                Text("\(event.timeRange) · \(event.duration)")
                                    .font(DevysTypography.caption)
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .animation(DevysAnimation.default.delay(Double(index) * 0.03), value: density)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    var gmailState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DevysSpacing.space2) {
                ForEach(Array(mode.threads.enumerated()), id: \.element.id) { index, thread in
                    HStack(alignment: .top, spacing: DevysSpacing.space2) {
                        Circle()
                            .fill(mode.accent.opacity(0.2))
                            .frame(width: 24, height: 24)
                            .overlay {
                                Text(initials(for: thread.sender))
                                    .font(DevysTypography.xs)
                                    .foregroundStyle(mode.accent)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(thread.sender)
                                    .font(DevysTypography.caption)
                                    .foregroundStyle(theme.textSecondary)
                                Spacer(minLength: 0)
                                Text(thread.time)
                                    .font(DevysTypography.caption)
                                    .foregroundStyle(theme.textTertiary)
                            }

                            Text(thread.subject)
                                .font(DevysTypography.body)
                                .foregroundStyle(theme.text)
                                .fontWeight(thread.isUnread ? .semibold : .regular)

                            Text(thread.snippet)
                                .font(DevysTypography.caption)
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(DevysAnimation.default.delay(Double(index) * 0.03), value: density)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    var gchatState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DevysSpacing.space2) {
                ForEach(Array(mode.spaces.enumerated()), id: \.element.id) { index, space in
                    HStack(alignment: .top, spacing: DevysSpacing.space2) {
                        Image(systemName: "number.square")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(mode.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(space.name)
                                    .font(DevysTypography.body)
                                    .foregroundStyle(theme.text)
                                Spacer(minLength: 0)
                                Text(space.time)
                                    .font(DevysTypography.caption)
                                    .foregroundStyle(theme.textTertiary)
                            }

                            Text(space.preview)
                                .font(DevysTypography.caption)
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                        }

                        if space.unreadCount > 0 {
                            Text("\(space.unreadCount)")
                                .font(DevysTypography.xs)
                                .foregroundStyle(mode.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(mode.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(DevysAnimation.default.delay(Double(index) * 0.03), value: density)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    var monthGrid: some View {
        let calendar = Calendar.current
        let date = Date()
        let days = monthDays(calendar: calendar, date: date)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let today = calendar.component(.day, from: date)

        return VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            Text(currentMonthLabel(date: date))
                .font(DevysTypography.heading)
                .foregroundStyle(mode.accent)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { label in
                    Text(label)
                        .font(DevysTypography.xs)
                        .foregroundStyle(theme.textTertiary)
                }

                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        Text("\(day)")
                            .font(DevysTypography.xs)
                            .foregroundStyle(day == today ? theme.base : theme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 20)
                            .background(Circle().fill(day == today ? mode.accent : Color.clear))
                    } else {
                        Text("").frame(maxWidth: .infinity, minHeight: 20)
                    }
                }
            }
        }
    }

    func monthDays(calendar: Calendar, date: Date) -> [Int?] {
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let dayRange = calendar.range(of: .day, in: .month, for: date) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let mondayShifted = (firstWeekday + 5) % 7
        let prefix = Array(repeating: Optional<Int>.none, count: mondayShifted)
        return prefix + dayRange.map { Optional($0) }
    }

    func currentMonthLabel(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).uppercased()
    }

    func initials(for sender: String) -> String {
        let words = sender.split(separator: " ").prefix(2)
        return String(words.compactMap { $0.first })
    }

    func animateCelebrationPop() {
        celebrationScale = 1
        withAnimation(DevysAnimation.spring) {
            celebrationScale = 1.1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(DevysAnimation.spring) {
                celebrationScale = 1
            }
        }
    }
}

private extension View {
    func cardStyle(radius: CGFloat, theme: DevysTheme) -> some View {
        background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(theme.borderSubtle, lineWidth: 1)
            }
    }
}
