import Foundation
import StoreKit

/// Product identifiers for TierTap subscriptions (must match App Store Connect).
enum TierTapProductId: String, CaseIterable {
    case monthly = "com.app.subs.tiertap.monthly"
    case quarterly = "com.app.subs.tiertap.quarterly"
    case yearly = "com.app.subs.tiertap.yearly"

    /// Subscription group identifier.
    var subscriptionGroupId: String { "com.app.subs.tiertap" }
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
        print("[SubscriptionStore] loadProducts bundleId=\(bundleId) version=\(version) (\(build)) requestedIds=\(ids)")
        do {
            products = try await Product.products(for: ids)
            // Sort by price, but keep stable ordering otherwise.
            products.sort { p1, p2 in
                (p1.price as Decimal) < (p2.price as Decimal)
            }
            let loadedIds = products.map(\.id)
            print("[SubscriptionStore] loadProducts OK count=\(products.count) loadedIds=\(loadedIds)")
            // StoreKit returns [] (without throwing) for unknown IDs — typical when App Store Connect
            // product IDs don’t match the app, or subscriptions aren’t cleared for sale yet.
            if products.isEmpty, !Self.isTestFlightOrSandboxBuild {
                errorMessage =
                    "Couldn’t load subscription plans. Check your connection and try again. "
                    + "If this persists, confirm in App Store Connect that these product IDs exist for this app: "
                    + ids.joined(separator: ", ")
            }
        } catch {
            errorMessage = error.localizedDescription
            print("[SubscriptionStore] loadProducts failed error=\(error.localizedDescription)")
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

