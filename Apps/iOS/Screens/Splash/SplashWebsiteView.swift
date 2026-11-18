import SwiftUI
import WebKit

struct SplashWebsiteView: View {
    let website: SplashWebsite
    let isPreview: Bool
    let action: (SplashWebsiteAction) -> Void
    @State private var session: SplashWebsiteSession
    @State private var owner = UUID()
    @State private var recoveryPresented = false
    @State private var visible = false
    @State private var recoveryCollapsed = false
    @Namespace private var recoveryTransition
    @Environment(\.appReduceMotion) private var reduceMotion

    init(website: SplashWebsite, session: SplashWebsiteSession? = nil, isPreview: Bool = false, action: @escaping (SplashWebsiteAction) -> Void) {
        self.website = website
        self.isPreview = isPreview
        self.action = action
        _session = State(initialValue: session ?? SplashWebsiteSession())
    }

    var body: some View {
        ZStack {
            if session.owner != owner {
                Text("This website is open in another window.")
                    .multilineTextAlignment(.center).padding()
            } else if let page = session.page {
                WebView(page)
                    .webViewBackForwardNavigationGestures(.disabled)
                    .webViewMagnificationGestures(.disabled)
                    .scrollBounceBehavior(.basedOnSize)
                    .allowsHitTesting(!session.loading)
                    .accessibilityHidden(session.loading)
            }
            if session.owner == owner {
                if let failure = session.failure {
                    VStack(spacing: AM.Spacing.l) {
                        if failure == .closed {
                            Text("This website has closed.").multilineTextAlignment(.center)
                        } else {
                            Text("The website could not load.").multilineTextAlignment(.center)
                            Button("Retry website") { collapseRecovery(); open() }.buttonStyle(.bordered)
                        }
                        Button("Continue for now") { session.continueForNow(owner: owner) }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(AM.Spacing.xl)
                } else if session.loading {
                    ProgressView("Loading website")
                        .padding(AM.Spacing.xl)
                        .accessibilityIdentifier("Splash.Web.Loading")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color.clear.contentShape(Rectangle()).onTapGesture(perform: collapseRecovery)
        }
        .onChange(of: session.interactionCount) { _, _ in collapseRecovery() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if session.owner == owner && !recoveryCollapsed { recoveryControl }
        }
        .overlay(alignment: .bottomTrailing) {
            if session.owner == owner && recoveryCollapsed { recoveryControl }
        }
        .onAppear { visible = true; open() }
        .onChange(of: session.owner) { _, newOwner in if visible && newOwner == nil && !session.finished { open() } }
        .onDisappear { visible = false; session.stop(owner: owner) }
    }

    private var recoveryControl: some View {
        Button { recoveryPresented = true } label: {
            HStack {
                Image(systemName: "questionmark.circle")
                if !recoveryCollapsed { Text("Having trouble?") }
            }
        }
        .accessibilityLabel("Having trouble?")
        .buttonStyle(.bordered)
        .foregroundStyle(Color.primary)
        .tint(Color.primary)
        .buttonBorderShape(recoveryCollapsed ? .circle : .capsule)
        .controlSize(.large)
        .background {
            if recoveryCollapsed { Circle().fill(.regularMaterial) }
        }
        .matchedGeometryEffect(id: "recovery", in: recoveryTransition)
        .accessibilityIdentifier("Splash.Web.Recovery")
        .padding(AM.Spacing.l)
        .frame(maxWidth: recoveryCollapsed ? nil : .infinity)
        .background {
            if !recoveryCollapsed { Rectangle().fill(.regularMaterial) }
        }
        .confirmationDialog("Website options", isPresented: $recoveryPresented, titleVisibility: .visible) {
            Button("Retry website", action: open)
            Button("Continue for now") { session.continueForNow(owner: owner) }
            Button("Keep filling out") { recoveryPresented = false }
        } message: {
            Text(verbatim: recoveryMessage)
        }
    }

    private var recoveryMessage: String {
        if isPreview {
            return String(localized: "Retrying may discard unsent answers. Continue for now advances or closes this preview without scheduling a reminder.")
        }
        return String(localized: "Retrying may discard unsent answers. Continue for now leaves this form pending for your next app opening.")
    }

    private func collapseRecovery() {
        withOptionalAnimation(reduceMotion ? nil : AppMotion.quick) { recoveryCollapsed = true }
    }

    private func open() {
        session.open(website, owner: owner, action: action)
    }
}
