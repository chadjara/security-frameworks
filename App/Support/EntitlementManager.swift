import Foundation
import Observation
import StoreKit

/// Features that may become part of a paid tier.
enum PremiumFeature: String, CaseIterable {
    /// More than one assessment on the device.
    case multipleAssessments
    /// PDF reports that combine several frameworks.
    case combinedReports
    /// Applying an answer to NIST-mapped requirements in other frameworks.
    case crossFrameworkReuse
}

/// The single place that decides whether a premium feature is available.
///
/// Everything is free today (`freeTierUnlocksEverything`), so no purchase UI exists and StoreKit is not
/// queried. To introduce the paid tier: create the product in App Store Connect, set the flag to `false`,
/// and add a purchase screen that calls `purchase(_:)`.
@MainActor
@Observable
final class EntitlementManager {
    static let freeTierUnlocksEverything = true
    static let premiumProductIDs: Set<String> = ["com.cjaratech.securityframework.premium"]

    private(set) var purchasedProductIDs: Set<String> = []
    @ObservationIgnored private var updates: Task<Void, Never>?

    func isUnlocked(_ feature: PremiumFeature) -> Bool {
        Self.freeTierUnlocksEverything || !purchasedProductIDs.isDisjoint(with: Self.premiumProductIDs)
    }

    /// Starts listening for purchases and refunds. Does nothing while everything is free.
    func start() {
        guard !Self.freeTierUnlocksEverything, updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.revocationDate == nil {
                owned.insert(transaction.productID)
            }
        }
        purchasedProductIDs = owned
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        if case .success(.verified(let transaction)) = result {
            await transaction.finish()
            await refresh()
        }
    }
}
