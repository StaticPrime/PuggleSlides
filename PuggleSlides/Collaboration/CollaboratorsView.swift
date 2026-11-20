import AppKit
import PuggleSlidesKit
import SwiftUI

/// A round badge with someone's initials, colored by their name as comment avatars are, with a green dot while they
/// have the presentation open.
struct CollaboratorBadge: View {
    let person: Collaborator
    var size: CGFloat = 28
    var isViewing = false

    private var color: Color {
        let name = person.displayName
        return AvatarView.colors[abs(name.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % AvatarView.colors.count]
    }

    var body: some View {
        Text(person.initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
            .overlay(Circle().stroke(Color.white, lineWidth: size > 30 ? 2 : 1.5))
            .overlay(alignment: .bottomTrailing) {
                if isViewing {
                    Circle()
                        .fill(Color(red: 0.13, green: 0.66, blue: 0.33))
                        .frame(width: size * 0.32, height: size * 0.32)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .offset(x: 1, y: 1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(person.displayName + (isViewing ? ", viewing now" : ""))
    }
}

/// The people a presentation is shared with, as round badges in the header; clicking one tells more about them.
struct CollaboratorAvatars: View {
    let state: CollaborationState
    @State private var shown: String?

    var body: some View {
        let others = state.others
        if state.isShared, !others.isEmpty {
            HStack(spacing: -6) {
                ForEach(others.prefix(5)) { person in
                    Button { shown = person.id } label: {
                        CollaboratorBadge(person: person, isViewing: state.isViewing(person))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help(person.displayName + (state.isViewing(person) ? " is viewing" : ""))
                    .popover(isPresented: Binding(get: { shown == person.id }, set: { if !$0 { shown = nil } }), arrowEdge: .bottom) {
                        CollaboratorBubble(person: person, state: state)
                    }
                }
                if others.count > 5 {
                    Text("+\(others.count - 5)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.toolbarFill))
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .help(others.dropFirst(5).map(\.displayName).joined(separator: ", "))
                }
            }
            .padding(.trailing, 4)
        }
    }
}

/// What the header tells about one person: who they are in iCloud, what they can do, and whether they're here.
struct CollaboratorBubble: View {
    let person: Collaborator
    let state: CollaborationState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CollaboratorBadge(person: person, size: 44, isViewing: state.isViewing(person))
            VStack(alignment: .leading, spacing: 4) {
                Text(person.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                if let address = person.address, address != person.displayName {
                    Text(address)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .textSelection(.enabled)
                }
                Label("iCloud", systemImage: "icloud")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                Divider().padding(.vertical, 2)
                Label(person.roleDescription, systemImage: person.isOwner ? "crown" : (person.permission == .edit ? "pencil" : "text.bubble"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.primaryText)
                Label(activity, systemImage: state.isViewing(person) ? "eye" : "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(state.isViewing(person) ? Color(red: 0.09, green: 0.50, blue: 0.22) : Theme.secondaryText)
            }
        }
        .padding(14)
        .frame(minWidth: 240, alignment: .leading)
    }

    private var activity: String {
        if state.isViewing(person) { return "Viewing now" }
        if person.status == .invited { return "Invited, not joined yet" }
        guard let seen = state.lastSeen(person) else { return "Hasn’t opened it here yet" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last here " + formatter.localizedString(for: seen, relativeTo: state.clock)
    }
}
