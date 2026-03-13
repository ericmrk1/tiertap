import SwiftUI
import StoreKit

private let appleEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
private let privacyPolicyURL = URL(string: "https://travelzork.com/privacy-policy/")!

/// Subscription paywall for TierTap Pro.
struct TierTapPaywallView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var showConfetti = false

    private var hasProAccess: Bool {
        subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
    }

    var body: some View {
        NavigationView {
            ZStack {
                settingsStore.primaryGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        requirementsSection
                        benefitsSection
                        currentPlanSection
                        productsSection
                        purchaseSection
                        restoreSection
                        legalSection

                        if let message = subscriptionStore.errorMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("TierTap Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                // Try to select a sensible default on first appear.
                selectDefaultProductIfNeeded()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unlock TierTap Pro")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
            Text("Smarter play decisions, powered by AI.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Requirements", systemImage: "lock.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: hasProAccess ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(hasProAccess ? .green : .white.opacity(0.8))
                    Text("Active TierTap Pro subscription.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
                HStack(spacing: 8) {
                    Image(systemName: authStore.isSignedIn ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(authStore.isSignedIn ? .green : .white.opacity(0.8))
                    Text("Signed in with a valid TierTap account (email, Apple, or Google).")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.15))
        .cornerRadius(14)
        // Extend the requirements "bubble" to the screen edges.
        .padding(.horizontal, -16)
    }

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What you get")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 6) {
                ProBenefitRow(
                    icon: "wand.and.stars",
                    title: "AI Play Analysis",
                    subtitle: "Ask TierTap to analyze your sessions and patterns."
                )
                ProBenefitRow(
                    icon: "camera.viewfinder",
                    title: "Chip Estimator at Close Out",
                    subtitle: "Estimate chip stacks with AI before you cash out."
                )
                ProBenefitRow(
                    icon: "person.3.sequence.fill",
                    title: "Community Feed",
                    subtitle: "See and share real-world sessions from other players."
                )
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.15))
        .cornerRadius(16)
        // Extend the "What you get" bubble to the screen edges.
        .padding(.horizontal, -16)
    }

    private var currentProduct: Product? {
        guard let id = subscriptionStore.purchasedProductIds.first else { return nil }
        return subscriptionStore.products.first(where: { $0.id == id })
    }

    private func selectDefaultProductIfNeeded() {
        guard selectedProduct == nil else { return }
        guard !subscriptionStore.products.isEmpty else { return }

        // Prefer yearly plan by default, otherwise fall back to first product.
        if let yearly = subscriptionStore.products.first(where: { $0.id.contains("yearly") }) {
            selectedProduct = yearly
        } else {
            selectedProduct = subscriptionStore.products.first
        }
    }

    private func currentPlanLabel(for product: Product) -> String {
        if product.id.contains("yearly") { return "Yearly plan" }
        if product.id.contains("quarterly") { return "3‑month plan" }
        return "Monthly plan"
    }

    private var currentPlanSection: some View {
        Group {
            if let product = currentProduct {
                VStack(alignment: .leading, spacing: 6) {
                    Text("You're currently subscribed")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                    Text("\(currentPlanLabel(for: product)) • \(product.displayPrice)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                    Text("To change your subscription, choose a different plan below and tap \"Change plan\".")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color.white.opacity(0.18))
                .cornerRadius(14)
            }
        }
    }

    private var productsSection: some View {
        Group {
            if subscriptionStore.isLoading && subscriptionStore.products.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Spacer()
                }
                .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(subscriptionStore.products, id: \.id) { product in
                        PaywallProductRow(
                            product: product,
                            isSelected: selectedProduct?.id == product.id,
                            isCurrent: subscriptionStore.purchasedProductIds.contains(product.id),
                            accentColor: settingsStore.primaryColor
                        ) {
                            selectedProduct = product
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
                // Extend product "bubbles" to the horizontal edges of the screen.
                .padding(.horizontal, -16)
                // When the products actually render, ensure we pick a default.
                .onAppear {
                    selectDefaultProductIfNeeded()
                }
            }
        }
    }

    private var purchaseButtonTitle: String {
        guard let selected = selectedProduct else { return "Select a plan" }
        if subscriptionStore.purchasedProductIds.contains(selected.id) {
            return "Current plan"
        }
        return hasProAccess ? "Change plan" : "Subscribe"
    }

    private var isPurchaseDisabled: Bool {
        if selectedProduct == nil { return true }
        if isPurchasing || subscriptionStore.isLoading { return true }
        if let selected = selectedProduct,
           subscriptionStore.purchasedProductIds.contains(selected.id) {
            return true
        }
        return false
    }

    private var purchaseSection: some View {
        Button(action: purchaseSelected) {
            HStack {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(purchaseButtonTitle)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isPurchaseDisabled ? Color.gray : settingsStore.primaryColor)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(isPurchaseDisabled)
        // Extend the subscribe button to the screen edges.
        .padding(.horizontal, -16)
    }

    private var restoreSection: some View {
        Button("Restore Purchases") {
            Task {
                await subscriptionStore.restorePurchases()
            }
        }
        .font(.footnote)
        .foregroundColor(settingsStore.primaryColor)
        .frame(maxWidth: .infinity)
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subscriptions automatically renew unless canceled at least 24 hours before the end of the current period. You can manage and cancel subscriptions in your device Settings under Apple ID → Subscriptions.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Link("Apple EULA", destination: appleEULAURL)
                    .font(.caption)
                    .foregroundColor(settingsStore.primaryColor)
                Link("Privacy Policy", destination: privacyPolicyURL)
                    .font(.caption)
                    .foregroundColor(settingsStore.primaryColor)
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }

    private func purchaseSelected() {
        guard let product = selectedProduct else { return }
        if subscriptionStore.purchasedProductIds.contains(product.id) {
            return
        }
        isPurchasing = true
        Task {
            let success = await subscriptionStore.purchase(product)
            await MainActor.run {
                isPurchasing = false
                if success {
                    showConfetti = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ProBenefitRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.green)
                .frame(width: 20, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
            }
        }
    }
}

private struct PaywallProductRow: View {
    let product: Product
    let isSelected: Bool
    let isCurrent: Bool
    let accentColor: Color
    let action: () -> Void

    private var periodLabel: String {
        if product.id.contains("yearly") { return "Yearly" }
        if product.id.contains("quarterly") { return "3 Months" }
        return "Monthly"
    }

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(periodLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text(product.displayPrice)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.9))

                    if isCurrent {
                        Text("Current plan")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.18))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.headline)
                    .foregroundColor(isSelected ? accentColor : .white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                isSelected
                ? accentColor.opacity(0.3)
                : (isCurrent ? Color.white.opacity(0.12) : Color.white.opacity(0.15))
            )
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isCurrent ? Color.white : (isSelected ? accentColor : Color.clear),
                        lineWidth: (isCurrent || isSelected) ? 1.5 : 0
                    )
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

