import SwiftUI
import SwiftData
import RevenueCat

@main
struct RoostApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var lockManager = AppLockManager()
    @State private var authManager = AuthManager()
    @State private var homeManager = HomeManager()
    @State private var networkMonitor = NetworkMonitor()
    @State private var notificationsViewModel = NotificationsViewModel()
    @State private var notificationRouter = NotificationRouter()
    @State private var settingsViewModel = SettingsViewModel()
    @State private var dashboardViewModel = DashboardViewModel()
    @State private var shoppingViewModel = ShoppingViewModel()
    @State private var expensesViewModel = ExpensesViewModel()
    @State private var budgetViewModel = BudgetViewModel()
    @State private var choresViewModel = ChoresViewModel()
    @State private var calendarViewModel = CalendarViewModel()
    @State private var activityViewModel = ActivityViewModel()
    @State private var pinboardViewModel = PinboardViewModel()
    @State private var subscriptionPricingStore = SubscriptionPricingStore()
    @State private var appearanceSettings = AppearanceSettings()
    @State private var budgetCarrySettings = BudgetCarrySettings()
    @State private var hazelViewModel = HazelViewModel()
    // Money rebuild — Session 1A data foundation
    @State private var budgetTemplateViewModel = BudgetTemplateViewModel()
    @State private var monthlyMoneyViewModel = MonthlyMoneyViewModel()
    @State private var moneySettingsViewModel = MoneySettingsViewModel()
    @State private var memberNamesHelper = MemberNamesHelper()
    @State private var scrambleModeEnvironment = ScrambleModeEnvironment()
    @State private var appBootManager = AppBootManager()
    // Money rebuild — Session 6 savings goals
    @State private var savingsGoalsViewModel = SavingsGoalsViewModel()
    // Offline foundation — Phase 1
    @State private var syncStatusStore = SyncStatusStore.shared

    @State private var lastBackgroundedAt: Date?

    @Environment(\.scenePhase) private var scenePhase

    init() {
        RevenueCatService.configure(apiKey: Config.revenueCatAPIKey)
    }

    /// True when there is live sensitive content on screen that must be hidden
    /// from the app switcher: authenticated, app lock not showing, boot complete,
    /// AND the auth-loading dawn animation has finished (MainTabView visible).
    /// The `authLoadingComplete` gate is critical — without it the shield can
    /// arm over `AuthLoadingView` during the window between boot-done and
    /// animation-done, which caused the black-flash bug on login.
    private var privacyShieldEnabled: Bool {
        authManager.isAuthenticated
            && !lockManager.isLocked
            && appBootManager.bootedHomeId != nil
            && appBootManager.authLoadingComplete
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(lockManager)
                .environment(authManager)
                .environment(homeManager)
                .environment(networkMonitor)
                .environment(notificationsViewModel)
                .environment(notificationRouter)
                .environment(settingsViewModel)
                .environment(dashboardViewModel)
                .environment(shoppingViewModel)
                .environment(expensesViewModel)
                .environment(budgetViewModel)
                .environment(choresViewModel)
                .environment(calendarViewModel)
                .environment(activityViewModel)
                .environment(pinboardViewModel)
                .environment(subscriptionPricingStore)
                .environment(appearanceSettings)
                .environment(budgetCarrySettings)
                .environment(hazelViewModel)
                .environment(budgetTemplateViewModel)
                .environment(monthlyMoneyViewModel)
                .environment(moneySettingsViewModel)
                .environment(memberNamesHelper)
                .environment(scrambleModeEnvironment)
                .environment(appBootManager)
                .environment(savingsGoalsViewModel)
                .environment(syncStatusStore)
                .modelContainer(LocalDataManager.shared.container)
                .onOpenURL { url in
                    authManager.handle(url: url)
                    notificationRouter.handle(url: url)
                }
                .task {
                    authManager.startSessionListener()
                    LocalNotificationManager.shared.configure(router: notificationRouter)
                    await subscriptionPricingStore.refresh()
                    AppPrivacyShield.shared.isEnabled = privacyShieldEnabled
                    // Offline foundation — wire sync coordinator dependencies
                    // and try an initial drain if we launched online. The
                    // coordinator itself is idempotent and gates on connectivity.
                    SyncCoordinator.shared.configure(
                        networkMonitor: networkMonitor,
                        authManager: authManager
                    )
                    // Phase 2 — register per-domain mutation handlers. Each
                    // handler owns the replay path for one `entityType`.
                    SyncCoordinator.shared.register(ExpenseMutationHandler())
                    SyncCoordinator.shared.register(BudgetMutationHandler())
                    SyncCoordinator.shared.register(CustomCategoryMutationHandler())
                    SyncCoordinator.shared.register(SavingsGoalMutationHandler())
                    SyncCoordinator.shared.register(HouseholdIncomeMutationHandler())
                    await SyncCoordinator.shared.drainIfOnline()
                }
                .onChange(of: authManager.currentUser?.id) { _, userId in
                    Task {
                        if let userId {
                            try? await RevenueCatService.shared.logIn(userId: userId.uuidString)
                        } else {
                            try? await RevenueCatService.shared.logOut()
                        }
                    }
                }
                .onChange(of: scenePhase) { _, newValue in
                    switch newValue {
                    case .background:
                        lockManager.appDidBackground()
                        lastBackgroundedAt = Date()
                    case .active:
                        lockManager.appDidForeground()
                        if let bg = lastBackgroundedAt, Date().timeIntervalSince(bg) >= 180 {
                            notificationRouter.selectedTab = .home
                            notificationRouter.morePath = []
                        }
                        lastBackgroundedAt = nil
                        // Confirmed foreground — safe to remove the privacy cover.
                        // Using scenePhase rather than didBecomeActiveNotification
                        // because that notification can fire spuriously for background
                        // apps; scenePhase == .active is the stable, reliable signal.
                        AppPrivacyShield.shared.deactivate()
                        // Drain any mutations that were queued while backgrounded.
                        Task { await SyncCoordinator.shared.drainIfOnline() }
                    default:
                        break
                    }
                }
                // Keep UIKit shield state in sync with auth/lock/boot changes.
                .onChange(of: authManager.isAuthenticated) { _, _ in
                    AppPrivacyShield.shared.isEnabled = privacyShieldEnabled
                }
                .onChange(of: lockManager.isLocked) { _, _ in
                    // Only sync when the app is in the foreground. When the app
                    // backgrounds while a PIN is set, appDidBackground() flips
                    // isLocked → true, which would make privacyShieldEnabled false
                    // and tear down the cover that was just added on
                    // willResignActiveNotification. The cover must persist until
                    // scenePhase == .active fires deactivate().
                    guard scenePhase == .active else { return }
                    AppPrivacyShield.shared.isEnabled = privacyShieldEnabled
                }
                .onChange(of: appBootManager.bootedHomeId) { _, _ in
                    AppPrivacyShield.shared.isEnabled = privacyShieldEnabled
                }
                .onChange(of: appBootManager.authLoadingComplete) { _, _ in
                    AppPrivacyShield.shared.isEnabled = privacyShieldEnabled
                }
                // SwiftUI-layer privacy overlay — belt-and-suspenders cover for scene
                // transitions that happen while the app is active (e.g. returning from
                // a background task). The UIKit AppPrivacyShield handles the timing-
                // critical app switcher snapshot; this handles the visual state inside
                // the SwiftUI hierarchy.
                //
                // Conditions mirror privacyShieldEnabled exactly — only covers when
                // there is live authenticated content, never over the lock screen
                // (which handles its own privacy) or during initial boot.
                .overlay {
                    // Only the `.background` phase — `.inactive` happens during
                    // every foreground transition (Face ID sheet dismissal, PIN
                    // unlock handoff), and letting the overlay fire there was
                    // the cause of black-flashes over the auth-loading screen.
                    // The UIKit AppPrivacyShield still covers the app-switcher
                    // snapshot itself, which is the real privacy surface.
                    if scenePhase == .background && privacyShieldEnabled {
                        Color.roostBackground
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                            .transaction { $0.animation = nil }
                    }
                }
        }
    }
}
