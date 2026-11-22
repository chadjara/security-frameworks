import SwiftUI

/// Loading, empty, and error states shared by every screen.
enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)
}

struct LoadingStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: DS.Space.s) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.dsCallout)
                .foregroundStyle(Color.dsTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateView<Actions: View>: View {
    let title: String
    let message: String
    let systemImage: String
    @ViewBuilder var actions: () -> Actions

    init(title: String, message: String, systemImage: String, @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actions = actions
    }

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title).font(.dsTitle3)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(Color.dsTextTertiary)
            }
        } description: {
            Text(message).font(.dsCallout)
        } actions: {
            actions()
        }
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(title: String, message: String, systemImage: String) {
        self.init(title: title, message: message, systemImage: systemImage) { EmptyView() }
    }
}

struct ErrorStateView: View {
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        EmptyStateView(title: title, message: message, systemImage: "exclamationmark.triangle") {
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.dsSecondary)
            }
        }
    }
}
