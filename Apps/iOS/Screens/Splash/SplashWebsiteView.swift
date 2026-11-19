import SwiftUI
import WebKit

struct SplashWebsiteView: View {
    let website: SplashWebsite
    let advance: () -> Void
    @State private var session = SplashWebsiteSession()

    var body: some View {
        ZStack {
            if let page = session.page {
                WebView(page)
                    .webViewBackForwardNavigationGestures(.disabled)
                    .allowsHitTesting(!session.loading)
                    .accessibilityHidden(session.loading)
            }
            if let failure = session.failure {
                VStack(spacing: AM.Spacing.l) {
                    if failure == .closed {
                        Text("This website has closed.").multilineTextAlignment(.center)
                    } else {
                        Text("The website could not load.").multilineTextAlignment(.center)
                        Button("Retry", action: open).buttonStyle(.bordered)
                    }
                    Button("Continue to update", action: continueWithoutWebsite).buttonStyle(.borderedProminent)
                }
                .padding(AM.Spacing.xl)
            } else if session.loading {
                ProgressView("Loading website")
                    .padding(AM.Spacing.xl)
                    .accessibilityIdentifier("Splash.Web.Loading")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if session.page != nil, !session.loading {
                Menu {
                    Button("Keep filling out") {}
                    Button("Continue for now", action: continueWithoutWebsite)
                } label: {
                    Label("Website help", systemImage: "questionmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityIdentifier("Splash.Web.Recovery")
                .padding(AM.Spacing.l)
            }
        }
        .onAppear(perform: open)
        .onDisappear(perform: session.stop)
    }

    private func continueWithoutWebsite() {
        session.stop()
        advance()
    }

    private func open() {
        session.open(website, advance: advance)
    }
}
