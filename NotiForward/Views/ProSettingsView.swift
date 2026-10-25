import SwiftUI
#if APP_STORE
import StoreKit
#endif

/// Marks controls that need Pro. Only shown in the App Store build, where Pro is sold.
struct ProBadge: View {
    var body: some View {
        if PurchaseService.isStoreBuild {
            Text(verbatim: "PRO")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.15), in: Capsule())
                .foregroundStyle(.purple)
        }
    }
}

#if APP_STORE
struct ProSettingsView: View {
    @Bindable var model: AppModel
    private var purchases: PurchaseService { model.purchases }

    private var comparison: [(feature: String, free: String, pro: String)] {
        [
            (L("Forwarding strategy"), L("Allow list only"), L("Allow or block list")),
            (L("Apps"), L("1 app"), L("Unlimited")),
            (L("Keyword filtering"), L("Not included"), L("Included")),
        ]
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(L("\(appName) Pro")).font(.title3.bold())
                    Spacer()
                    Text(purchases.entitlement.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((purchases.isPro ? Color.green : Color.secondary).opacity(0.15), in: Capsule())
                        .foregroundStyle(purchases.isPro ? .green : .secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text(L("Feature"))
                        Text(L("Free"))
                        Text(verbatim: "Pro")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    ForEach(comparison, id: \.feature) { row in
                        GridRow {
                            Text(row.feature)
                            Text(row.free).foregroundStyle(.secondary)
                            Text(row.pro)
                        }
                    }
                }
            }

            Section(L("Purchase Options")) {
                if let product = purchases.lifetimeProduct {
                    productRow(product, title: L("One-time purchase"), detail: L("Unlock once and keep Pro on your Mac."),
                               buttonTitle: L("Unlock – \(product.displayPrice)"))
                }
                ForEach(purchases.subscriptionProducts, id: \.id) { product in
                    productRow(product, title: product.displayName, detail: product.description,
                               buttonTitle: L("Subscribe – \(product.displayPrice)"))
                }
                if purchases.lifetimeProduct == nil && purchases.subscriptionProducts.isEmpty {
                    if purchases.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(L("Purchase options are not available right now.")).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button(L("Restore Purchases")) { Task { await purchases.restore() } }
                    if !purchases.subscriptionProducts.isEmpty {
                        Button(L("Manage Subscriptions")) { purchases.openManageSubscriptions() }
                    }
                }
                .disabled(purchases.isLoading || purchases.purchasingProductID != nil)
                if let message = purchases.statusMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Text(L("Payment is charged to your App Store account. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period, and can be managed or cancelled in your App Store account settings."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Link(L("Privacy Policy"), destination: StoreConfig.privacyPolicyURL)
                    Link(L("Terms of Use (EULA)"), destination: StoreConfig.termsOfUseURL)
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .task { await purchases.refresh() }
    }

    private func productRow(_ product: Product, title: String, detail: String, buttonTitle: String) -> some View {
        let isCurrent = (product.id == StoreConfig.lifetimeProductID && purchases.entitlement == .lifetime)
            || (product.id == StoreConfig.monthlyProductID && purchases.entitlement == .monthly)
            || (product.id == StoreConfig.yearlyProductID && purchases.entitlement == .yearly)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Text(L("Current Plan")).font(.caption.weight(.semibold)).foregroundStyle(.green)
            } else if purchases.purchasingProductID == product.id {
                ProgressView().controlSize(.small)
            } else {
                Button(buttonTitle) { Task { await purchases.purchase(product) } }
                    .disabled(purchases.isPro || purchases.purchasingProductID != nil)
            }
        }
    }
}
#endif
