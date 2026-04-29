import SwiftUI

// MARK: - Feature Context

struct ProFeatureContext {
    let icon: String
    let title: String
    let description: String

    static let budgetHistory = ProFeatureContext(
        icon: "calendar.badge.clock",
        title: "Budget History",
        description: "Navigate through past months to review your full spending history."
    )
    static let budgetInsights = ProFeatureContext(
        icon: "sparkles",
        title: "Hazel Budget Insights",
        description: "Get AI-written plain-English summaries of your monthly spending."
    )
    static let calendarSync = ProFeatureContext(
        icon: "calendar.badge.plus",
        title: "Calendar Sync",
        description: "Sync your household calendar with Apple Calendar so nothing slips through."
    )
    static let hazelExpenses = ProFeatureContext(
        icon: "sparkles",
        title: "Auto-Categorize Expenses",
        description: "Let Hazel tag and clean up your expenses automatically as you log them."
    )
    static let advancedBudgeting = ProFeatureContext(
        icon: "chart.pie",
        title: "Advanced Budgeting",
        description: "Set category limits, carry budgets forward, and track recurring spend."
    )
    static let roomGroups = ProFeatureContext(
        icon: "square.grid.2x2",
        title: "Room Groups",
        description: "Organise your home by room so chores and shopping are easier to manage."
    )
    static let choreSuggestions = ProFeatureContext(
        icon: "lightbulb.fill",
        title: "AI Chore Suggestions",
        description: "Hazel suggests new chores for the month based on your household routine."
    )
    static let hazelBulkCategorize = ProFeatureContext(
        icon: "sparkles",
        title: "Smart Expense Sorting",
        description: "Let Hazel automatically categorize all your uncategorized expenses in one tap."
    )
    static let hazelInsights = ProFeatureContext(
        icon: "sparkles",
        title: "Hazel Budget Insights",
        description: "Get AI-written plain-English summaries of your monthly spending."
    )
}

// Backward compatibility
typealias NestFeatureContext = ProFeatureContext

// MARK: - Pro Upsell Sheet

struct ProUpsellSheet: View {
    let feature: ProFeatureContext

    @Environment(AuthManager.self) private var authManager
    @Environment(HomeManager.self) private var homeManager
    @Environment(SubscriptionPricingStore.self) private var pricingStore
    @Environment(NotificationRouter.self) private var notificationRouter
    @Environment(\.dismiss) private var dismiss

    @State private var isStartingCheckout = false
    @State private var errorMessage: String?
    @State private var browserSession = SubscriptionBrowserSession()

    // Animations
    @State private var glowPulsing = false
    @State private var headerAppeared = false
    @State private var shimmerPhase: CGFloat = -1.0
    @State private var featuresVisible = false

    private var hasUsedTrial: Bool { homeManager.home?.hasUsedTrialValue ?? false }
    private var monthlyPrice: String { pricingStore.prices.monthly.formattedAmount }

    private var upgradeTitle: String {
        hasUsedTrial ? "Upgrade to Roost Pro" : "Start Free Trial"
    }
    private var upgradeSubtitle: String {
        hasUsedTrial
            ? "Billed at \(monthlyPrice)/mo."
            : "14 days free, then \(monthlyPrice)/mo. Cancel anytime."
    }

    private let proHighlights: [(icon: String, title: String)] = [
        ("sparkles",             "Hazel AI — categorize, narrate, and sort"),
        ("lightbulb.fill",       "AI chore suggestions each month"),
        ("calendar.badge.clock", "Full budget history, every month"),
        ("chart.pie.fill",       "Advanced budgeting with category limits"),
        ("square.grid.2x2.fill", "Room groups for organised chores"),
        ("person.2.fill",        "Unlimited household members"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerSection
                    .zIndex(1)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        lockedFeatureCard
                        proHighlightsSection
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.roostMeta)
                                .foregroundStyle(Color.roostDestructive)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 4)
                        }
                        actionButtons
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .background(Color.roostBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowPulsing = true
            }
            withAnimation(.interpolatingSpring(stiffness: 55, damping: 9).delay(0.08)) {
                headerAppeared = true
            }
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false).delay(0.6)) {
                shimmerPhase = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                featuresVisible = true
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack {
            // Gradient
            LinearGradient(
                colors: [Color.roostPrimary, Color.roostSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Radial glow
            RadialGradient(
                colors: [Color.white.opacity(0.15), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 100
            )
            .scaleEffect(glowPulsing ? 1.5 : 0.9)

            // Decorative circles
            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 140, height: 140)
                .offset(x: 100, y: -30)

            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 80, height: 80)
                .offset(x: -80, y: 30)

            // Content
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 64, height: 64)
                        .scaleEffect(glowPulsing ? 1.3 : 1.0)

                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 48, height: 48)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(headerAppeared ? 1.0 : 0.3)
                        .opacity(headerAppeared ? 1 : 0)
                }

                VStack(spacing: 5) {
                    Text("Roost Pro")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(headerAppeared ? 1.0 : 0.85)
                        .opacity(headerAppeared ? 1 : 0)

                    Text("Unlock the full household experience")
                        .font(.roostCaption)
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .opacity(headerAppeared ? 1 : 0)
                }
            }
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }

    // MARK: - Locked Feature Card

    private var lockedFeatureCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.roostPrimary.opacity(0.18), Color.roostSecondary.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: feature.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.roostPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(feature.title)
                        .font(.roostBody.weight(.semibold))
                        .foregroundStyle(Color.roostForeground)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.roostMutedForeground)
                }

                Text(feature.description)
                    .font(.roostCaption)
                    .foregroundStyle(Color.roostMutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(Color.roostCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.roostPrimary.opacity(0.35), Color.roostSecondary.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
    }

    // MARK: - Pro Highlights

    private var proHighlightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Everything in Roost Pro")
                .font(.roostLabel)
                .foregroundStyle(Color.roostMutedForeground)
                .tracking(0.3)

            VStack(spacing: 8) {
                ForEach(Array(proHighlights.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.roostPrimary.opacity(0.15), Color.roostSecondary.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 30, height: 30)

                            Image(systemName: item.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.roostPrimary)
                        }

                        Text(item.title)
                            .font(.roostCaption)
                            .foregroundStyle(Color.roostForeground)

                        Spacer(minLength: 0)
                    }
                    .opacity(featuresVisible ? 1 : 0)
                    .offset(x: featuresVisible ? 0 : -10)
                    .animation(.easeOut(duration: 0.35).delay(Double(index) * 0.05), value: featuresVisible)
                }
            }
        }
        .padding(16)
        .background(Color.roostCard, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .strokeBorder(Color.roostBorderLight, lineWidth: 1)
        )
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Gradient primary CTA
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await openCheckout() }
            } label: {
                ZStack {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.18), .clear],
                        startPoint: UnitPoint(x: shimmerPhase - 0.5, y: 0.5),
                        endPoint: UnitPoint(x: shimmerPhase + 0.5, y: 0.5)
                    )

                    HStack(spacing: 8) {
                        if isStartingCheckout {
                            ProgressView().tint(.white).controlSize(.small)
                        } else {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 13, weight: .bold))
                        }
                        Text(upgradeTitle)
                            .font(.roostLabel)
                    }
                    .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: DesignSystem.Size.buttonHeight)
                .background(
                    LinearGradient(
                        colors: [Color.roostPrimary, Color.roostSecondary],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: RoostTheme.controlCornerRadius, style: .continuous))
                .shadow(color: Color.roostPrimary.opacity(0.3), radius: 10, y: 3)
            }
            .buttonStyle(ProCTAButtonStyle())
            .disabled(isStartingCheckout)

            Text(upgradeSubtitle)
                .font(.roostMeta)
                .foregroundStyle(Color.roostMutedForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            // Secondary — see full Pro page
            Button {
                dismiss()
                notificationRouter.selectedTab = .more
                notificationRouter.morePath = [.subscription]
            } label: {
                HStack(spacing: 5) {
                    Text("See all features")
                        .font(.roostBody.weight(.medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.roostPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: DesignSystem.Size.inputHeight)
                .background(Color.roostPrimary.opacity(0.06), in: RoundedRectangle(cornerRadius: RoostTheme.controlCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RoostTheme.controlCornerRadius, style: .continuous)
                        .strokeBorder(Color.roostPrimary.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Checkout

    private func openCheckout() async {
        errorMessage = nil
        isStartingCheckout = true
        defer { isStartingCheckout = false }

        let accessToken: String
        do {
            accessToken = try await authManager.validAccessToken()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        guard let home = homeManager.home, let user = authManager.currentUser else {
            errorMessage = "No household found."
            return
        }

        let service = SubscriptionService()
        do {
            let url = try await service.createCheckoutSession(
                plan: .monthly,
                homeId: home.id,
                customerEmail: user.email,
                accessToken: accessToken
            )
            let callbackURL = try await browserSession.start(url: url)
            if callbackURL.host == "subscription" {
                await homeManager.refreshCurrentHome()
                dismiss()
            }
        } catch SubscriptionBrowserError.cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// Backward compatibility alias
typealias NestUpsellSheet = ProUpsellSheet

// MARK: - Pro CTA Button Style (shared)

struct ProCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.interpolatingSpring(stiffness: 300, damping: 20), value: configuration.isPressed)
    }
}

// MARK: - View Modifier

private struct ProUpsellModifier: ViewModifier {
    @Binding var isPresented: Bool
    let feature: ProFeatureContext

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            ProUpsellSheet(feature: feature)
        }
    }
}

extension View {
    func proUpsell(isPresented: Binding<Bool>, feature: ProFeatureContext) -> some View {
        modifier(ProUpsellModifier(isPresented: isPresented, feature: feature))
    }

    func nestUpsell(isPresented: Binding<Bool>, feature: ProFeatureContext) -> some View {
        proUpsell(isPresented: isPresented, feature: feature)
    }
}
