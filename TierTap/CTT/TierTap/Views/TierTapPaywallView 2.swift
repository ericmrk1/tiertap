import SwiftUI
import StoreKit

private let appleEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
private let privacyPolicyURL = URL(string: "https://travelzork.com/privacy-policy/")!

/// Rounded percent saved vs paying the monthly plan each month for the same duration (`monthsInPlan`).
private func subscriptionSavingsPercentComparedToMonthly(
    planPrice: Decimal,
    monthlyPrice: Decimal,
    monthsInPlan: Int
) -> Int? {
    guard monthsInPlan > 0, monthlyPrice > 0 else { return nil }
    let baseline = monthlyPrice * Decimal(monthsInPlan)
    guard baseline > 0, planPrice < baseline else { return nil }
    let pctDecimal = (baseline - planPrice) / baseline * 100
    let pct = NSDecimalNumber(decimal: pctDecimal).doubleValue
    guard pct.isFinite else { return nil }
    let rounded = Int(pct.rounded())
    return rounded > 0 ? rounded : nil
}

private func subscriptionSavingsPercent(plan: Product, monthlyProduct: Product?) -> Int? {
    guard let monthlyProduct, monthlyProduct.id == TierTapProductId.monthly.rawValue else { return nil }
    let months: Int?
    switch TierTapProductId(rawValue: plan.id) {
    case .quarterly: months = 3
    case .yearly: months = 12
    default: months = nil
    }
    guard let months else { return nil }
    return subscriptionSavingsPercentComparedToMonthly(
        planPrice: plan.price,
        monthlyPrice: monthlyProduct.price,
        monthsInPlan: months
    )
}

/// Subscription paywall for TierTap Pro.
struct TierTapPaywallView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var purchasingProductId: String?
    @State private var showConfetti = false
    @State private var showAccountSheet = false
    @State private var emailInput: String = ""
    @State private var isPurchasingCreditsPack = false
    @State private var isRequirementsExpanded = false
    @State private var isBenefitsExpanded = false

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
                        productsSection
                        tierTapPlusSection
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
                .refreshable {
                    await subscriptionStore.loadProducts()
                }
            }
            .localizedNavigationTitle("TierTap Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Account") {
                        showAccountSheet = true
                    }
                    .foregroundColor(.white)
                }
            }
            .task {
                await subscriptionStore.loadProducts()
            }
        }
        .navigationViewStyle(.stack)
        .adaptiveSheet(isPresented: $showAccountSheet) {
            CommunityAuthSheet(
                emailInput: $emailInput,
                onDismiss: { showAccountSheet = false }
            )
            .environmentObject(authStore)
            .environmentObject(settingsStore)
            .environmentObject(subscriptionStore)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            L10nText("Unlock TierTap Pro")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
            L10nText("Smarter play decisions, powered by AI.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var requirementsSection: some View {
        paywallCollapsibleSection(
            isExpanded: $isRequirementsExpanded,
            cornerRadius: 14
        ) {
            LocalizedLabel(title: "Requirements", systemImage: "lock.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: hasProAccess ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(hasProAccess ? .green : .white.opacity(0.8))
                    L10nText("Active TierTap Pro subscription.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
                HStack(spacing: 8) {
                    Image(systemName: authStore.isSignedIn ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(authStore.isSignedIn ? .green : .white.opacity(0.8))
                    L10nText("Signed in with a TierTap account (email, Apple, or Google).")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }

                if !authStore.isSignedIn {
                    Button {
                        showAccountSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle")
                            L10nText("Go to Account to sign in")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.18))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
    }

    private var benefitsSection: some View {
        paywallCollapsibleSection(
            isExpanded: $isBenefitsExpanded,
            cornerRadius: 16
        ) {
            L10nText("What you get")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                ProBenefitRow(
                    icon: "wand.and.stars",
                    title: "AI Play Analysis",
                    subtitle: "Ask TierTap to analyze your sessions and patterns."
                )
                ProBenefitRow(
                    icon: "camera.viewfinder",
                    title: "Chip Estimator",
                    subtitle: "Estimate chip stacks from a photo with AI before you cash out."
                )
                ProBenefitRow(
                    icon: "photo",
                    title: "Comp Estimator",
                    subtitle: "Estimate comps from a photo with AI."
                )
                ProBenefitRow(
                    icon: "text.viewfinder",
                    title: "Slot Reader",
                    subtitle: "Read slot machine details from a photo with AI."
                )
                ProBenefitRow(
                    icon: "person.3.sequence.fill",
                    title: "Community Feed",
                    subtitle: "See and share real-world sessions from other players."
                )
                ProBenefitRow(
                    icon: "doc.text.fill",
                    title: "Tax Preparation Documentation",
                    subtitle: "Generate US-focused tax assistance for your records."
                )
            }
        }
    }

    private func paywallCollapsibleSection<Header: View, Content: View>(
        isExpanded: Binding<Bool>,
        cornerRadius: CGFloat,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: isExpanded.wrappedValue ? 8 : 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    header()
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white.opacity(0.8))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.15))
        .cornerRadius(cornerRadius)
        .padding(.horizontal, -16)
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
            } else if subscriptionStore.products.isEmpty {
                if hasProAccess {
                    if subscriptionStore.hasComplimentaryBetaProAccess {
                        L10nText("TierTap Pro is included on this TestFlight build.")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.95))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(12)
                    }
                } else {
                    VStack(spacing: 12) {
                        L10nText("No plans loaded yet.")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.95))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Button {
                            Task { await subscriptionStore.loadProducts() }
                        } label: {
                            Text("Retry")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(settingsStore.primaryColor.opacity(0.85))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(12)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    L10nText("Choose your plan")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)

                    HStack(alignment: .top, spacing: 8) {
                        ForEach(sortedSubscriptionProducts, id: \.id) { product in
                            PaywallPlanBox(
                                product: product,
                                savingsPercent: subscriptionSavingsPercent(plan: product, monthlyProduct: monthlySubscriptionProduct),
                                isCurrent: subscriptionStore.purchasedProductIds.contains(product.id),
                                isPurchasing: purchasingProductId == product.id,
                                isBusy: purchasingProductId != nil || subscriptionStore.isLoading,
                                hasProAccess: hasProAccess,
                                accentColor: settingsStore.primaryColor
                            ) {
                                purchase(product)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var sortedSubscriptionProducts: [Product] {
        subscriptionStore.subscriptionProducts.sorted { lhs, rhs in
            productSortOrder(lhs.id) < productSortOrder(rhs.id)
        }
    }

    private var monthlySubscriptionProduct: Product? {
        sortedSubscriptionProducts.first { $0.id == TierTapProductId.monthly.rawValue }
    }

    private var tierTapPlusSection: some View {
        Group {
            TierTapPlusMark(font: .subheadline.weight(.semibold), weight: .semibold, foreground: .white)

            VStack(alignment: .leading, spacing: 10) {
                L10nText("Need more AI power? Add token packs to extend usage beyond your TierTap Pro plan.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if let creditsProduct = subscriptionStore.creditsProduct {
                    TierTapPlusTokenStatBubbles(
                        packBalance: settingsStore.aiPurchasedTokenBalance,
                        lifetimePurchased: settingsStore.lifetimeTierTapPlusTokensPurchased,
                        packUsage: settingsStore.tierTapPlusTokensConsumedFromPurchases,
                        compact: true
                    )

                    Button {
                        purchaseCreditsPack(creditsProduct)
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            if isPurchasingCreditsPack {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            let packCount = settingsStore.effectiveCreditsPackTokenAmount.formatted(.number.grouping(.automatic))
                            TierTapPlusTokenPackPurchaseLabel(
                                language: settingsStore.appLanguage,
                                tokenCountFormatted: packCount,
                                displayPrice: creditsProduct.displayPrice,
                                font: .caption.weight(.semibold)
                            )
                        }
                        .tierTapPlusPurchaseButtonChrome(compact: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .accessibilityLabel(
                        String(
                            format: L10n.tr(
                                "Buy TierTap Plus Tokens (%@) — %@",
                                language: settingsStore.appLanguage
                            ),
                            settingsStore.effectiveCreditsPackTokenAmount.formatted(.number.grouping(.automatic)),
                            creditsProduct.displayPrice
                        )
                    )
                    .disabled(!hasProAccess || isPurchasingCreditsPack || purchasingProductId != nil || subscriptionStore.isLoading)
                } else {
                    L10nText("Token packs aren’t available in the store yet. Check back after the Credits product is configured.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !hasProAccess {
                    L10nText("Subscribe to TierTap Pro to use AI features, then you can buy token packs here.")
                        .font(.caption2)
                        .foregroundColor(.orange.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.15))
            .cornerRadius(12)
        }
    }

    private func productSortOrder(_ id: String) -> Int {
        if id.contains("monthly") { return 0 }
        if id.contains("quarterly") { return 1 }
        if id.contains("yearly") { return 2 }
        return 3
    }

    private func isPurchaseDisabled(for product: Product) -> Bool {
        if purchasingProductId != nil || subscriptionStore.isLoading { return true }
        if subscriptionStore.purchasedProductIds.contains(product.id) { return true }
        return false
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
            L10nText("Subscriptions automatically renew unless canceled at least 24 hours before the end of the current period. You can manage and cancel subscriptions in your device Settings under Apple ID → Subscriptions.")
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

    private func purchase(_ product: Product) {
        guard !isPurchaseDisabled(for: product) else { return }
        purchasingProductId = product.id
        Task {
            let success = await subscriptionStore.purchase(product)
            await MainActor.run {
                purchasingProductId = nil
                if success != nil {
                    showConfetti = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func purchaseCreditsPack(_ product: Product) {
        guard hasProAccess else { return }
        guard purchasingProductId == nil, !subscriptionStore.isLoading, !isPurchasingCreditsPack else { return }
        isPurchasingCreditsPack = true
        Task {
            let success = await subscriptionStore.purchase(product)
            await MainActor.run {
                isPurchasingCreditsPack = false
            }
            if let tid = success {
                await settingsStore.grantTierTapSessionCreditsPack(
                    storeTransactionId: tid,
                    supabaseUserId: authStore.session?.user.id
                )
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

private struct PaywallPlanBox: View {
    let product: Product
    let savingsPercent: Int?
    let isCurrent: Bool
    let isPurchasing: Bool
    let isBusy: Bool
    let hasProAccess: Bool
    let accentColor: Color
    let action: () -> Void

    private var periodLabel: String {
        if product.id.contains("yearly") { return "Yearly" }
        if product.id.contains("quarterly") { return "3 Months" }
        return "Monthly"
    }

    private var actionTitle: String {
        hasProAccess ? "Change plan" : "Subscribe"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(periodLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Text(product.displayPrice)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))

            if let savingsPercent {
                Text("Save \(savingsPercent)% vs monthly")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.green.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Save \(savingsPercent) percent compared to paying monthly")
            }

            Spacer(minLength: 0)

            if isCurrent {
                Text("Current plan")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
            } else {
                Button(action: action) {
                    HStack(spacing: 6) {
                        if isPurchasing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(actionTitle)
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.14))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .padding(9)
        .background(isCurrent ? accentColor.opacity(0.34) : Color.white.opacity(0.15))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrent ? accentColor : Color.white.opacity(0.2), lineWidth: isCurrent ? 2 : 1)
        )
    }
}

