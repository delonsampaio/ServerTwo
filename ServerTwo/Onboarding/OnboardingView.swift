import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page {
        let title: String
        let body: String
        let systemImage: String
    }

    private let pages: [Page] = [
        Page(
            title: "Welcome to Server Two",
            body: "Server Two keeps score so you don't have to think about the tricky parts of pickleball's rules.",
            systemImage: "figure.pickleball"
        ),
        Page(
            title: "The First Game Starts at Server 2",
            body: "In doubles, every game after the first starts with Server 1. But the very first game of a match is the one exception: it starts at Server 2, since there's no partner who already served and lost their turn.",
            systemImage: "2.circle.fill"
        ),
        Page(
            title: "You're Ready",
            body: "Set up a match, flip for first serve, and start playing. Server Two tracks the score, the server, and when to switch sides.",
            systemImage: "checkmark.circle.fill"
        )
    ]

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if page == pages.count - 1 {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("Done")
                    } else {
                        Button("Skip") { dismiss() }
                            .accessibilityIdentifier("Skip")
                    }
                }
            }
        }
    }

    private func pageView(_ page: Page) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: page.systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text(page.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(page.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
            Spacer()
        }
        .padding()
    }
}

#Preview {
    OnboardingView()
}
