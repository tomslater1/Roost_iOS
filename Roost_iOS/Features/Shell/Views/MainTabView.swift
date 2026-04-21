import SwiftUI

struct MainTabView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(HomeManager.self) private var homeManager
    @Environment(NotificationsViewModel.self) private var notificationsViewModel
    @Environment(NotificationRouter.self) private var notificationRouter
    @Environment(SettingsViewModel.self) private var settingsViewModel
    @Environment(DashboardViewModel.self) private var dashboardViewModel
    @Environment(ShoppingViewModel.self) private var shoppingViewModel
    @Environment(ExpensesViewModel.self) private var expensesViewModel
    @Environment(BudgetViewModel.self) private var budgetViewModel
    @Environment(ChoresViewModel.self) private var choresViewModel
    @Environment(CalendarViewModel.self) private var calendarViewModel
    @Environment(ActivityViewModel.self) private var activityViewModel
    @Environment(PinboardViewModel.self) private var pinboardViewModel
    @Environment(BudgetTemplateViewModel.self) private var budgetTemplateViewModel
    @Environment(MonthlyMoneyViewModel.self) private var monthlyMoneyViewModel
    @Environment(MoneySettingsViewModel.self) private var moneySettingsViewModel
    @Environment(MemberNamesHelper.self) private var memberNamesHelper
    @Environment(ScrambleModeEnvironment.self) private var scrambleModeEnvironment
    @Environment(SavingsGoalsViewModel.self) private var savingsGoalsViewModel
    @Environment(AppBootManager.self) private var appBootManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var loadedTabs: Set<NotificationRouter.AppTab> = [.home, .money, .shopping, .chores, .more]
    @State private var warmedHomeId: UUID?
    @State private var tabBarHidden = false
    @State private var showIncomeSetup = false

    var body: some View {
        ZStack(alignment: .bottom) {
            currentTabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.roostBackground)
                .safeAreaPadding(.bottom, tabBarHidden ? 0 : DesignSystem.Size.tabBarHeight + DesignSystem.Spacing.tabContentBottomInset)
                .overlay(alignment: .bottom) {
                    if let error = homeManager.errorMessage {
                        Text(error)
                            .font(.roostCaption)
                            .foregroundStyle(Color.roostCard)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 10)
                            .background(Color.roostDestructive, in: Capsule())
                            .padding(.bottom, DesignSystem.Size.toastBottomOffset)
                    }
                }

            if !tabBarHidden {
                FigmaTabBar(
                    selectedTab: Binding(
                        get: { notificationRouter.selectedTab },
                        set: { notificationRouter.selectedTab = $0 }
                    )
                )
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .transaction { transaction in
                    transaction.disablesAnimations = true
                    transaction.animation = nil
                }
            }
        }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .animation(nil, value: tabBarHidden)
            .task(id: authManager.homeId) {
                guard let homeId = authManager.homeId,
                      let userId = authManager.currentUser?.id else { return }
                if appBootManager.isBooted(homeId: homeId, userId: userId) {
                    await restartRealtime(homeId: homeId, userId: userId)
                    warmedHomeId = homeId
                    // Delay so any auth loading / transition animation fully completes
                    // before a fullScreenCover can appear on top.
                    try? await Task.sleep(for: .seconds(0.7))
                    if shouldShowIncomeSetup() { showIncomeSetup = true }
                    loadedTabs.insert(notificationRouter.selectedTab)
                    return
                }

                await homeManager.loadHome(homeId: homeId, userId: userId)
                await homeManager.startRealtime(homeId: homeId, userId: userId)
                if warmedHomeId != homeId {
                    async let pageWarm: Void = warmPageData(homeId: homeId, userId: userId)
                    async let userWarm: Void = warmUserData(userId: userId)
                    _ = await (pageWarm, userWarm)
                    warmedHomeId = homeId
                    appBootManager.markBooted(homeId: homeId, userId: userId)
                    // Delay so the auth loading cross-fade completes before cover appears.
                    try? await Task.sleep(for: .seconds(0.7))
                    if shouldShowIncomeSetup() { showIncomeSetup = true }
                }
                loadedTabs.insert(notificationRouter.selectedTab)
            }
            .onChange(of: scenePhase) { _, newValue in
                notificationsViewModel.isAppActive = newValue == .active
            }
            .onChange(of: moneySettingsViewModel.settings.scrambleMode) { _, _ in
                scrambleModeEnvironment.sync(from: moneySettingsViewModel.settings)
            }
            .onChange(of: notificationRouter.selectedTab) { _, newValue in
                loadedTabs.insert(newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: .roostTabBarHiddenChanged)) { notification in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                transaction.animation = nil
                withTransaction(transaction) {
                    tabBarHidden = (notification.object as? Bool) ?? false
                }
            }
            .onDisappear {
                Task {
                    await notificationsViewModel.stopRealtime()
                    await homeManager.stopRealtime()
                    await stopPagePolling()
                    warmedHomeId = nil
                }
            }
            .fullScreenCover(isPresented: $showIncomeSetup) {
                IncomeSetupView { showIncomeSetup = false }
                    .interactiveDismissDisabled(true)
            }
    }

    @ViewBuilder
    private var currentTabContent: some View {
        ZStack {
            if loadedTabs.contains(.home) {
                tabContainer(for: .home) {
                    NavigationStack(path: Binding(
                        get: { notificationRouter.homePath },
                        set: { notificationRouter.homePath = $0 }
                    )) {
                        DashboardView()
                            .navigationDestination(for: NotificationRouter.MoreDestination.self) { destination in
                                switch destination {
                                case .notifications:
                                    NotificationsView()
                                case .notificationSettings:
                                    NotificationSettingsView()
                                default:
                                    EmptyView()
                                }
                            }
                    }
                }
            }

            if loadedTabs.contains(.money) {
                tabContainer(for: .money) {
                    NavigationStack {
                        MoneyHomeView()
                    }
                }
            }

            if loadedTabs.contains(.shopping) {
                tabContainer(for: .shopping) {
                    NavigationStack {
                        ShoppingListView()
                    }
                }
            }

            if loadedTabs.contains(.chores) {
                tabContainer(for: .chores) {
                    NavigationStack {
                        ChoresView()
                    }
                }
            }

            if loadedTabs.contains(.more) {
                tabContainer(for: .more) {
                    NavigationStack(path: Binding(
                        get: { notificationRouter.morePath },
                        set: { notificationRouter.morePath = $0 }
                    )) {
                        MoreMenuView()
                            .navigationDestination(for: NotificationRouter.MoreDestination.self) { destination in
                                switch destination {
                                case .household:
                                    HouseholdSettingsView()
                                case .rooms:
                                    RoomsView()
                                case .pinboard:
                                    PinboardView()
                                case .appearance:
                                    AppearanceSettingsView()
                                case .activity:
                                    ActivityFeedView()
                                case .notifications:
                                    NotificationsView()
                                case .notificationSettings:
                                    NotificationSettingsView()
                                case .hazel:
                                    HazelView()
                                case .subscription:
                                    SubscriptionView()
                                case .profile:
                                    ProfileSettingsView()
                                case .account:
                                    AccountSettingsView()
                                case .money:
                                    MoneySettingsView()
                                case .calendar:
                                    CalendarView()
                                case .settings:
                                    MoreSettingsView()
                                case .security:
                                    SecuritySettingsView()
                                case .preferences:
                                    PreferencesSettingsView()
                                }
                            }
                    }
                }
            }
        }
    }

    private func tabContainer<Content: View>(
        for tab: NotificationRouter.AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(notificationRouter.selectedTab == tab ? 1 : 0)
            .allowsHitTesting(notificationRouter.selectedTab == tab)
            .accessibilityHidden(notificationRouter.selectedTab != tab)
    }

    private func shouldShowIncomeSetup() -> Bool {
        // Re-prompt after 7 days if user only snoozed; permanently dismissed stores a far-future timestamp
        let snoozedAt = UserDefaults.standard.double(forKey: "roost-income-setup-dismissed-at")
        if snoozedAt > 0 {
            let elapsed = Date().timeIntervalSince1970 - snoozedAt
            if elapsed < 7 * 24 * 3600 { return false } // still within snooze window
        }
        return !homeManager.members.contains { ($0.personalIncome ?? 0) > 0 }
    }

    private func warmPageData(homeId: UUID, userId: UUID) async {
        async let dashboardLoad: Void = dashboardViewModel.load(homeId: homeId)
        async let shoppingLoad: Void = shoppingViewModel.loadItems(homeId: homeId)
        async let expensesLoad: Void = expensesViewModel.loadExpenses(homeId: homeId)
        async let budgetLoad: Void = budgetViewModel.load(homeId: homeId)
        async let choresLoad: Void = choresViewModel.load(homeId: homeId)
        async let calendarLoad: Void = calendarViewModel.load(homeId: homeId)
        async let activityLoad: Void = activityViewModel.loadActivity(homeId: homeId)
        async let pinboardLoad: Void = pinboardViewModel.load(homeId: homeId, userId: userId)
        async let templateLoad: Void = budgetTemplateViewModel.load(homeId: homeId)
        async let monthlyLoad: Void = monthlyMoneyViewModel.loadSummary(homeId: homeId, members: homeManager.members)
        async let settingsLoad: Void = moneySettingsViewModel.load(homeId: homeId)
        async let goalsLoad: Void = savingsGoalsViewModel.load(homeId: homeId)

        _ = await (dashboardLoad, shoppingLoad, expensesLoad, budgetLoad, choresLoad, calendarLoad, activityLoad, pinboardLoad)
        _ = await (templateLoad, monthlyLoad, settingsLoad, goalsLoad)

        // Resolve member names once members are loaded
        if let uid = authManager.currentUser?.id {
            memberNamesHelper.load(currentUserId: uid, homeMembers: homeManager.members)
        }
        // Sync scramble mode from settings
        scrambleModeEnvironment.sync(from: moneySettingsViewModel.settings)

        async let dashboardRealtime: Void = dashboardViewModel.startRealtime(homeId: homeId)
        async let shoppingRealtime: Void = shoppingViewModel.startRealtime(homeId: homeId)
        async let expensesRealtime: Void = expensesViewModel.startRealtime(homeId: homeId)
        async let budgetRealtime: Void = budgetViewModel.startRealtime(homeId: homeId)
        async let choresRealtime: Void = choresViewModel.startRealtime(homeId: homeId)
        async let calendarRealtime: Void = calendarViewModel.startRealtime(homeId: homeId)
        async let activityRealtime: Void = activityViewModel.startRealtime(homeId: homeId)
        async let pinboardRealtime: Void = pinboardViewModel.startRealtime(homeId: homeId, userId: userId)
        async let templateRealtime: Void = budgetTemplateViewModel.startRealtime(homeId: homeId)
        async let monthlyRealtime: Void = monthlyMoneyViewModel.startRealtime(homeId: homeId)
        async let settingsRealtime: Void = moneySettingsViewModel.startRealtime(homeId: homeId)
        async let goalsRealtime: Void = savingsGoalsViewModel.startRealtime(homeId: homeId)

        _ = await (dashboardRealtime, shoppingRealtime, expensesRealtime, budgetRealtime, choresRealtime, calendarRealtime, activityRealtime, pinboardRealtime)
        _ = await (templateRealtime, monthlyRealtime, settingsRealtime, goalsRealtime)
    }

    private func warmUserData(userId: UUID) async {
        notificationsViewModel.isAppActive = scenePhase == .active

        async let notificationsLoad: Void = notificationsViewModel.load(userId: userId)
        async let settingsLoad: Void = settingsViewModel.loadPreferences(for: userId)
        async let notificationAuth: Void = LocalNotificationManager.shared.requestAuthorization()

        _ = await (notificationsLoad, settingsLoad, notificationAuth)

        await notificationsViewModel.startRealtime(userId: userId)
    }

    private func restartRealtime(homeId: UUID, userId: UUID) async {
        await homeManager.startRealtime(homeId: homeId, userId: userId)
        memberNamesHelper.load(currentUserId: userId, homeMembers: homeManager.members)
        scrambleModeEnvironment.sync(from: moneySettingsViewModel.settings)
        notificationsViewModel.isAppActive = scenePhase == .active

        async let dashboardRealtime: Void = dashboardViewModel.startRealtime(homeId: homeId)
        async let shoppingRealtime: Void = shoppingViewModel.startRealtime(homeId: homeId)
        async let expensesRealtime: Void = expensesViewModel.startRealtime(homeId: homeId)
        async let budgetRealtime: Void = budgetViewModel.startRealtime(homeId: homeId)
        async let choresRealtime: Void = choresViewModel.startRealtime(homeId: homeId)
        async let calendarRealtime: Void = calendarViewModel.startRealtime(homeId: homeId)
        async let activityRealtime: Void = activityViewModel.startRealtime(homeId: homeId)
        async let pinboardRealtime: Void = pinboardViewModel.startRealtime(homeId: homeId, userId: userId)
        async let templateRealtime: Void = budgetTemplateViewModel.startRealtime(homeId: homeId)
        async let monthlyRealtime: Void = monthlyMoneyViewModel.startRealtime(homeId: homeId)
        async let settingsRealtime: Void = moneySettingsViewModel.startRealtime(homeId: homeId)
        async let goalsRealtime: Void = savingsGoalsViewModel.startRealtime(homeId: homeId)
        async let notificationsRealtime: Void = notificationsViewModel.startRealtime(userId: userId)

        _ = await (dashboardRealtime, shoppingRealtime, expensesRealtime, budgetRealtime, choresRealtime, calendarRealtime, activityRealtime, pinboardRealtime)
        _ = await (templateRealtime, monthlyRealtime, settingsRealtime, goalsRealtime, notificationsRealtime)
    }

    private func stopPagePolling() async {
        async let dashboardStop: Void = dashboardViewModel.stopRealtime()
        async let shoppingStop: Void = shoppingViewModel.stopRealtime()
        async let expensesStop: Void = expensesViewModel.stopRealtime()
        async let budgetStop: Void = budgetViewModel.stopRealtime()
        async let choresStop: Void = choresViewModel.stopRealtime()
        async let calendarStop: Void = calendarViewModel.stopRealtime()
        async let activityStop: Void = activityViewModel.stopRealtime()
        async let pinboardStop: Void = pinboardViewModel.stopRealtime()
        async let templateStop: Void = budgetTemplateViewModel.stopRealtime()
        async let monthlyStop: Void = monthlyMoneyViewModel.stopRealtime()
        async let settingsStop: Void = moneySettingsViewModel.stopRealtime()
        async let goalsStop: Void = savingsGoalsViewModel.stopRealtime()

        _ = await (dashboardStop, shoppingStop, expensesStop, budgetStop, choresStop, calendarStop, activityStop, pinboardStop)
        _ = await (templateStop, monthlyStop, settingsStop, goalsStop)
    }
}
