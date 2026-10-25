import AppKit
import Foundation
import Observation
#if APP_STORE
import StoreKit
#endif

enum StoreConfig {
    static let lifetimeProductID = "com.ct106.notiforward.pro"
    /// Create both subscriptions in the same subscription group in App Store Connect.
    static let monthlyProductID = "com.ct106.notiforward.pro.monthly"
    static let yearlyProductID = "com.ct106.notiforward.pro.yearly"
    static let subscriptionProductIDs = [monthlyProductID, yearlyProductID]
    static let allProductIDs = Set([lifetimeProductID] + subscriptionProductIDs)

    static let privacyPolicyURL = URL(string: "https://notiforward.ct106.com/privacy.html")!
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

enum ProEntitlement: String {
    case none, lifetime, monthly, yearly

    var title: String {
        switch self {
        case .none: L("Free")
        case .lifetime: L("One-time purchase")
        case .monthly: L("Monthly subscription")
        case .yearly: L("Yearly subscription")
        }
    }
}

/// Pro purchase state. Only the App Store build sells Pro; direct downloads are always unlocked.
@MainActor
@Observable
final class PurchaseService {
    static var isStoreBuild: Bool {
#if APP_STORE
        true
#else
        false
#endif
    }

    /// The last known entitlement is cached so a launch doesn't briefly apply free limits
    /// while StoreKit is still loading.
    private(set) var entitlement = ProEntitlement(rawValue: UserDefaults.standard.string(forKey: "proEntitlement") ?? "") ?? .none {
        didSet {
            UserDefaults.standard.set(entitlement.rawValue, forKey: "proEntitlement")
            if entitlement != oldValue { onChange?() }
        }
    }
    private(set) var isLoading = false
    private(set) var purchasingProductID: String?
    private(set) var statusMessage: String?
    @ObservationIgnored var onChange: (() -> Void)?

    var isPro: Bool { !Self.isStoreBuild || entitlement != .none }

#if APP_STORE
    private(set) var lifetimeProduct: Product?
    private(set) var subscriptionProducts: [Product] = []
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
#endif

    func start() {
#if APP_STORE
        guard !hasStarted else { return }
        hasStarted = true
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? Self.verified(result) {
                    await self.refreshEntitlement()
                    await transaction.finish()
                } else {
                    self.statusMessage = L("Could not verify the purchase.")
                }
            }
        }
        Task { await refresh() }
#endif
    }

    func refresh() async {
#if APP_STORE
        isLoading = true
        defer { isLoading = false }
        do {
            let products = try await Product.products(for: StoreConfig.allProductIDs)
            lifetimeProduct = products.first { $0.id == StoreConfig.lifetimeProductID }
            subscriptionProducts = StoreConfig.subscriptionProductIDs.compactMap { id in products.first { $0.id == id } }
        } catch {
            statusMessage = L("Could not load purchase options.")
        }
        await refreshEntitlement()
#endif
    }

    func restore() async {
#if APP_STORE
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            statusMessage = isPro ? L("\(appName) Pro is unlocked.") : L("No Pro purchase was found.")
        } catch {
            statusMessage = L("Could not restore purchases.")
        }
#endif
    }

    func openManageSubscriptions() {
        NSWorkspace.shared.open(URL(string: "https://apps.apple.com/account/subscriptions")!)
    }

#if APP_STORE
    func purchase(_ product: Product) async {
        purchasingProductID = product.id
        defer { purchasingProductID = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try Self.verified(verification)
                await refreshEntitlement()
                await transaction.finish()
                statusMessage = isPro ? L("\(appName) Pro is unlocked.") : nil
            case .pending:
                statusMessage = L("Purchase is pending approval.")
            case .userCancelled:
                statusMessage = nil
            @unknown default:
                statusMessage = L("Purchase could not be completed.")
            }
        } catch {
            statusMessage = L("Purchase could not be completed.")
        }
    }

    private func refreshEntitlement() async {
        var lifetime = false
        var latest: (id: String, expiry: Date?)?
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.verified(result),
                  StoreConfig.allProductIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            if transaction.productID == StoreConfig.lifetimeProductID {
                lifetime = true
            } else if latest == nil || (transaction.expirationDate ?? .distantPast) > (latest?.expiry ?? .distantPast) {
                latest = (transaction.productID, transaction.expirationDate)
            }
        }
        if lifetime {
            entitlement = .lifetime
        } else if let latest {
            entitlement = latest.id == StoreConfig.yearlyProductID ? .yearly : .monthly
        } else {
            entitlement = .none
        }
        Log.forward.info("Pro entitlement: \(self.entitlement.rawValue, privacy: .public)")

        // Re-check when the subscription runs out, so free limits apply without a relaunch.
        expiryTask?.cancel()
        if !lifetime, let expiry = latest?.expiry {
            expiryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, expiry.timeIntervalSinceNow) + 1))
                guard !Task.isCancelled else { return }
                await self?.refreshEntitlement()
            }
        }
    }

    nonisolated private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        guard case .verified(let value) = result else { throw StoreKitError.notEntitled }
        return value
    }
#endif
}
