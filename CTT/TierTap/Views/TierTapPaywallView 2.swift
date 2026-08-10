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

private func subscriptionSavingsPercent(
    plan: TierTapProductId,
    product: Product?,
    monthlyProduct: Product?
) -> Int? {
    guard let product else { return nil }
    return subscriptionSavingsPercent(plan: product, monthlyProduct: monthlyProduct)
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

    private var showsAiBudgetExhaustedPaywall: Bool {
        settingsStore.isProTokenBackedAccessBlocked(hasProAccess: hasProAccess)
    }

    var body: some View {
        NavigationView {
            ZStack {
                settingsStore.primaryGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        if showsAiBudgetExhaustedPaywall {
                            aiBudgetExhaustedNoticeSection
                            tierTapPlusSection
                            requirementsSection
                            legalLinksRow
                            restoreSection
                            legalSection
                        } else {
                            requirementsSection
                            benefitsSection
                            productsSection
                            legalLinksRow
                            tierTapPlusSection
                            restoreSection
                            legalSection
                        }

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
            .localizedNavigationTitle(showsAiBudgetExhaustedPaywall ? "TierTap Pro usage" : "TierTap Pro")
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
            if showsAiBudgetExhaustedPaywall {
                L10nText("TierTap Pro usage limit reached")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                L10nText("Buy TierTap+ tokens to continue using your TierTap Pro subscription and advanced features.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.9))
            } else {
                L10nText("Unlock TierTap Pro")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                L10nText("Smarter play decisions, powered by AI.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var aiBudgetExhaustedNoticeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            L10nText("You have used your TierTap Pro AI allowance and any TierTap+ token balance for this month.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            L10nText("Your included AI budget resets at the start of the next calendar month.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.15))
        .cornerRadius(12)
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
                    icon: "plus.forwardslash.minus",
                    title: "Loyalty Calculators + AI Insights",
                    subtitle: "Theo, ADT, comps, and tier calculators with TierTap AI Insights on Analytics."
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

    private struct PaywallSubscriptionPlanRow: Identifiable {
        let plan: TierTapProductId
        let product: Product?

        var id: String { plan.rawValue }

        var isProductAvailable: Bool { product != nil }

        var displayPrice: String {
            product?.displayPrice ?? plan.catalogDisplayPrice
        }
    }

    private var paywallSubscriptionPlanRows: [PaywallSubscriptionPlanRow] {
        TierTapProductId.subscriptionPlans.map { plan in
            PaywallSubscriptionPlanRow(
                plan: plan,
                product: subscriptionStore.subscriptionProducts.first { $0.id == plan.rawValue }
            )
        }
    }

    private var productsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            L10nText("Choose your plan")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)

            if subscriptionStore.isLoading && subscriptionStore.subscriptionProducts.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            if !subscriptionStore.isLoading && subscriptionStore.subscriptionProducts.isEmpty {
                if SupabaseConfig.isTestFlight {
                    L10nText("Subscription products are not available from App Store Connect yet. TierTap Pro is included on this TestFlight build while subscriptions are being set up.")
                        .font(.caption)
                        .foregroundColor(.orange.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                } else if SupabaseConfig.prefersBundledStoreKitTesting {
                    L10nText("Couldn’t load the bundled StoreKit test plans. Pull down to refresh, or run from Xcode with TierTapStoreKitConfig.storekit selected.")
                        .font(.caption)
                        .foregroundColor(.orange.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    L10nText("Subscription plans aren’t available from the App Store right now. Pull down to refresh, or try again in a moment.")
                        .font(.caption)
                        .foregroundColor(.orange.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                ForEach(paywallSubscriptionPlanRows) { row in
                    PaywallPlanBox(
                        plan: row.plan,
                        displayPrice: row.displayPrice,
                        showsEstimatedPrice: !row.isProductAvailable,
                        savingsPercent: subscriptionSavingsPercent(
                            plan: row.plan,
                            product: row.product,
                            monthlyProduct: monthlySubscriptionProduct
                        ),
                        isCurrent: subscriptionStore.purchasedProductIds.contains(row.id),
                        isPurchasing: purchasingProductId == row.id,
                        isBusy: purchasingProductId != nil || subscriptionStore.isLoading,
                        canPurchase: row.isProductAvailable,
                        hasProAccess: hasProAccess,
                        accentColor: settingsStore.primaryColor
                    ) {
                        purchaseSubscriptionPlan(row)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .frame(maxWidth: .infinity)
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
                if showsAiBudgetExhaustedPaywall {
                    L10nText("Add TierTap+ tokens to unlock AI, Community, Tax Prep, and other advanced TierTap Pro features for the rest of this month.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    L10nText("Need more AI power? Buy TierTap+ token packs anytime—no subscription required. With Pro, packs extend usage beyond your monthly plan.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }

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
                    .disabled(isPurchasingCreditsPack || purchasingProductId != nil || subscriptionStore.isLoading)
                } else {
                    L10nText("Token packs aren’t available in the store yet. Check back after the Credits product is configured.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.75))
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
        switch TierTapProductId(rawValue: id) {
        case .monthly: return 0
        case .quarterly: return 1
        case .yearly: return 2
        default: return 3
        }
    }

    private func isPurchaseDisabled(for product: Product) -> Bool {
        if purchasingProductId != nil { return true }
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

    /// Compact Terms + Privacy row placed near subscription offers (Guideline 3.1.2).
    private var legalLinksRow: some View {
        HStack(spacing: 10) {
            PaywallLegalLinkBubble(title: "Terms of Use (EULA)", destination: appleEULAURL)
            PaywallLegalLinkBubble(title: "Privacy Policy", destination: privacyPolicyURL)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            L10nText("Legal")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)

            HStack(spacing: 10) {
                PaywallLegalLinkBubble(title: "Terms of Use (EULA)", destination: appleEULAURL)
                PaywallLegalLinkBubble(title: "Privacy Policy", destination: privacyPolicyURL)
            }
            .accessibilityElement(children: .contain)

            L10nText("Subscriptions automatically renew unless canceled at least 24 hours before the end of the current period. You can manage and cancel subscriptions in your device Settings under Apple ID → Subscriptions.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }

    private func purchaseSubscriptionPlan(_ row: PaywallSubscriptionPlanRow) {
        if let product = row.product {
            purchase(product)
            return
        }
        guard purchasingProductId == nil, !subscriptionStore.isLoading else { return }

        purchasingProductId = row.id
        Task {
            await subscriptionStore.loadProducts()
            let refreshedProduct = subscriptionStore.subscriptionProducts.first { $0.id == row.id }
            purchasingProductId = nil
            if let refreshedProduct {
                purchase(refreshedProduct)
            }
        }
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

private struct PaywallLegalLinkBubble: View {
    let title: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Image(systemName: "arrow.up.right.square")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.22))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
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
    let plan: TierTapProductId
    let displayPrice: String
    let showsEstimatedPrice: Bool
    let savingsPercent: Int?
    let isCurrent: Bool
    let isPurchasing: Bool
    let isBusy: Bool
    let canPurchase: Bool
    let hasProAccess: Bool
    let accentColor: Color
    let action: () -> Void

    private var periodLabel: String {
        plan.paywallPeriodTitle
    }

    private var lengthLabel: String {
        switch plan {
        case .monthly: return "1 month"
        case .quarterly: return "3 months"
        case .yearly: return "1 year"
        case .credits: return ""
        }
    }

    private var actionTitle: String {
        if isPurchasing {
            return "Loading…"
        }
        if !canPurchase {
            return "Unavailable"
        }
        return hasProAccess ? "Change plan" : "Subscribe"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TierTap Pro")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white.opacity(0.85))
            Text(periodLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Text(lengthLabel)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.75))
            Text(displayPrice)
                .font(.caption)
                .foregroundColor(.white.opacity(showsEstimatedPrice ? 0.65 : 0.9))
            if showsEstimatedPrice {
                Text("Estimated price")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
            }

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
                .disabled(isBusy || (!canPurchase && (SupabaseConfig.isTestFlight || !SupabaseConfig.prefersBundledStoreKitTesting)))
                .opacity(isBusy || (!canPurchase && (SupabaseConfig.isTestFlight || !SupabaseConfig.prefersBundledStoreKitTesting)) ? 0.65 : 1)
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

