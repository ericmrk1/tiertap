import Foundation
import StoreKit

/// Product identifiers for TierTap subscriptions and consumables (must match App Store Connect / `.storekit`).
enum TierTapProductId: String, CaseIterable {
    /// Must match App Store Connect Product IDs (not Reference Names).
    case monthly = "pro.monthly"
    case quarterly = "pro"
    case yearly = "pro.yearly"
    case credits = "Credits"

    var subscriptionGroupId: String { "com.app.subs.tiertap" }

    var isSubscription: Bool {
        switch self {
        case .monthly, .quarterly, .yearly: return true
        case .credits: return false
        }
    }

    static let creditsPackTokenAmount: Int = 250_000
}

@MainActor
final class SubscriptionStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIds: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var updateListenerTask: Task<Void, Error>?

    /// Whether the user has TierTap Pro access: an active subscription, or a TestFlight / sandbox build
    /// (sandbox receipt path) where Pro is enabled by default for beta testers.
    var isPro: Bool {
        Self.isTestFlightOrSandboxBuild || !purchasedProductIds.isEmpty
    }

    /// TestFlight and Xcode installs use a sandbox receipt; production App Store uses `receipt`.
    private static var isTestFlightOrSandboxBuild: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// Pro is unlocked without a StoreKit purchase (TestFlight / sandbox receipt). Used for UI that hides IAP when the catalog is empty.
    var hasComplimentaryBetaProAccess: Bool {
        Self.isTestFlightOrSandboxBuild
    }

    var subscriptionProducts: [Product] {
        products.filter { TierTapProductId(rawValue: $0.id)?.isSubscription == true }
    }

    var creditsProduct: Product? {
        products.first { $0.id == TierTapProductId.credits.rawValue }
    }

    init() {
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
        let ids = TierTapProductId.allCases.map(\.rawValue)
        let bundleId = Bundle.main.bundleIdentifier ?? "nil"
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "nil"
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "nil"
        let isSimulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
        print("[SubscriptionStore] loadProducts starting. bundleId=\(bundleId) version=\(version) (\(build)) ids=\(ids) isSimulator=\(isSimulator)")
        do {
            products = try await Product.products(for: ids)
            // Sort by price, but keep stable ordering otherwise.
            products.sort { p1, p2 in
                (p1.price as Decimal) < (p2.price as Decimal)
            }
            let loadedIds = products.map(\.id)
            print("[SubscriptionStore] loadProducts succeeded. requestedIds=\(ids) loadedIds=\(loadedIds) count=\(products.count)")
        } catch {
            errorMessage = error.localizedDescription
            print("[SubscriptionStore] loadProducts failed. requestedIds=\(ids) error=\(error.localizedDescription)")
            products = []
        }
        isLoading = false
    }

    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updatePurchasedState()
                return true
            case .userCancelled:
                return false
            case .pending:
                errorMessage = "Purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
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

