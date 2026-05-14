import Foundation
import StoreKit
#if canImport(StoreKitTest)
import StoreKitTest
#endif

/// Product identifiers for TierTap subscriptions and consumables (must match App Store Connect / `.storekit`).
enum TierTapProductId: String, CaseIterable {
    case monthly = "com.app.subs.tiertap.monthly"
    case quarterly = "com.app.subs.tiertap.quarterly"
    case yearly = "com.app.subs.tiertap.yearly"
    /// TierTapSession consumable — adds purchasable AI token balance (`SettingsStore.grantTierTapSessionCreditsPack`).
    case credits = "Credits"

    /// Subscription group identifier (subscriptions only; unused for consumables).
    var subscriptionGroupId: String { "com.app.subs.tiertap" }

    var isSubscription: Bool {
        switch self {
        case .monthly, .quarterly, .yearly: return true
        case .credits: return false
        }
    }

    static let subscriptionPlans: [TierTapProductId] = [.monthly, .quarterly, .yearly]

    var paywallPeriodTitle: String {
        switch self {
        case .monthly: return "Monthly"
        case .quarterly: return "3 Months"
        case .yearly: return "Yearly"
        case .credits: return ""
        }
    }

    /// Display-only fallback when StoreKit has not returned a live `Product` yet (matches `TierTapStoreKitConfig.storekit`).
    var catalogDisplayPrice: String {
        switch self {
        case .monthly: return "$14.99"
        case .quarterly: return "$39.99"
        case .yearly: return "$149.00"
        case .credits: return "$4.99"
        }
    }

    /// Tokens credited to the user for one successful **Credits** purchase (bundled fallback; live value is ``SettingsStore/effectiveCreditsPackTokenAmount``).
    static let creditsPackTokenAmount: Int = TierTapRemoteDefaultFallbacks.creditsPackTokenAmount

    /// TierTap Pro “included” Gemini token allowance per calendar month before **purchased** TierTap Plus pack balance is drawn down (bundled fallback; live value is ``SettingsStore/effectiveProPlanIncludedTokensPerCalendarMonth``).
    static let proPlanIncludedTokensPerCalendarMonth: Int = TierTapRemoteDefaultFallbacks.proPlanIncludedTokensPerCalendarMonth
}

@MainActor
final class SubscriptionStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIds: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var subscriptionCatalogAvailable = false

    private var updateListenerTask: Task<Void, Error>?

    /// TestFlight builds include TierTap Pro while subscription products are not yet returned by App Store Connect.
    var hasComplimentaryBetaProAccess: Bool {
        SupabaseConfig.isTestFlight && !subscriptionCatalogAvailable
    }

    /// Whether the user has an active TierTap Pro subscription entitlement from StoreKit.
    var isPro: Bool {
        hasComplimentaryBetaProAccess || !purchasedProductIds.isEmpty
    }

    /// Subscription products only (excludes consumables like **Credits**).
    var subscriptionProducts: [Product] {
        products.filter { TierTapProductId(rawValue: $0.id)?.isSubscription == true }
    }

    /// **TierTapSession** consumable when returned by StoreKit.
    var creditsProduct: Product? {
        products.first { $0.id == TierTapProductId.credits.rawValue }
    }

    init() {
        TierTapStoreKitLocalTesting.activateIfNeeded()
        updateListenerTask = listenForTransactions()
        Task {
            await loadProducts()
            await updatePurchasedState()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        let subscriptionIds = TierTapProductId.subscriptionPlans.map(\.rawValue)
        let consumableIds = [TierTapProductId.credits.rawValue]
        let bundleId = Bundle.main.bundleIdentifier ?? "nil"
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "nil"
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "nil"
        print(
            "[SubscriptionStore] loadProducts bundleId=\(bundleId) version=\(version) (\(build)) "
            + "subscriptionIds=\(subscriptionIds) consumableIds=\(consumableIds)"
        )
        defer { isLoading = false }
        do {
            async let subscriptionProductsRequest = Product.products(for: subscriptionIds)
            async let consumableProductsRequest = Product.products(for: consumableIds)
            let loadedSubscriptionProducts = try await subscriptionProductsRequest
            let loadedConsumableProducts = try await consumableProductsRequest
            products = loadedSubscriptionProducts + loadedConsumableProducts
            products.sort { p1, p2 in
                (p1.price as Decimal) < (p2.price as Decimal)
            }
            let loadedIds = products.map(\.id)
            let loadedSubscriptionIds = loadedSubscriptionProducts.map(\.id)
            subscriptionCatalogAvailable = !loadedSubscriptionIds.isEmpty
            print(
                "[SubscriptionStore] loadProducts OK count=\(products.count) loadedIds=\(loadedIds) "
                + "subscriptionIds=\(loadedSubscriptionIds)"
            )
            // StoreKit returns [] (without throwing) for unknown IDs — typical when App Store Connect
            // product IDs don’t match the app, or subscriptions aren’t cleared for sale yet.
            if loadedSubscriptionIds.isEmpty {
                if SupabaseConfig.isTestFlight {
                    errorMessage =
                        "Subscription products are not available from App Store Connect yet. "
                        + "TierTap Pro is included on this TestFlight build while subscriptions are being set up. "
                        + "To test purchases, add these product IDs in App Store Connect: "
                        + subscriptionIds.joined(separator: ", ")
                } else if SupabaseConfig.prefersBundledStoreKitTesting {
                    if TierTapStoreKitLocalTesting.isActive {
                        errorMessage =
                            "Couldn’t load subscription plans from the bundled StoreKit test catalog. "
                            + "Pull down to refresh, or run from Xcode with TierTapStoreKitConfig.storekit selected."
                    } else {
                        errorMessage =
                            "Couldn’t load subscription plans from the bundled StoreKit test catalog. "
                            + "Pull down to refresh, or run from Xcode with TierTapStoreKitConfig.storekit selected."
                    }
                } else {
                    errorMessage =
                        "Couldn’t load subscription plans. Check your connection and try again. "
                        + "If this persists, confirm in App Store Connect that these product IDs exist for this app: "
                        + subscriptionIds.joined(separator: ", ")
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            print("[SubscriptionStore] loadProducts failed error=\(error.localizedDescription)")
            products = []
        }
    }

    /// - Returns: StoreKit transaction id string on verified success, or `nil` otherwise.
    func purchase(_ product: Product) async -> String? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                let id = String(transaction.id)
                await transaction.finish()
                await updatePurchasedState()
                return id
            case .userCancelled:
                return nil
            case .pending:
                errorMessage = "Purchase is pending approval."
                return nil
            @unknown default:
                return nil
            }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        do {
            try await AppStore.sync()
            await updatePurchasedState()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func updatePurchasedState() async {
        var activeIds: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate == nil {
                activeIds.insert(transaction.productID)
            }
        }
        purchasedProductIds = activeIds
    }

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self.updatePurchasedState()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreError.failedVerification
        }
    }
}

enum StoreError: Error {
    case failedVerification
}

/// Activates the bundled `TierTapStoreKitConfig.storekit` catalog for simulator and debug installs.
enum TierTapStoreKitLocalTesting {
    #if canImport(StoreKitTest)
    private static var session: SKTestSession?
    #endif

    static var isActive: Bool {
        #if canImport(StoreKitTest)
        return session != nil
        #else
        return false
        #endif
    }

    static func activateIfNeeded() {
        guard SupabaseConfig.prefersBundledStoreKitTesting else { return }
        #if canImport(StoreKitTest)
        guard session == nil else { return }
        #endif
        guard Bundle.main.url(forResource: "TierTapStoreKitConfig", withExtension: "storekit") != nil else {
            print("[StoreKit] Bundled TierTapStoreKitConfig.storekit not found in app resources.")
            return
        }

        #if canImport(StoreKitTest)
        do {
            let testSession = try SKTestSession(configurationFileNamed: "TierTapStoreKitConfig")
            testSession.resetToDefaultState()
            testSession.disableDialogs = false
            session = testSession
            print("[StoreKit] Activated bundled StoreKit test catalog TierTapStoreKitConfig.storekit")
        } catch {
            print("[StoreKit] Failed to activate bundled StoreKit test catalog: \(error.localizedDescription)")
        }
        #else
        print("[StoreKit] StoreKitTest is unavailable in this build; bundled catalog cannot be activated.")
        #endif
    }
}

