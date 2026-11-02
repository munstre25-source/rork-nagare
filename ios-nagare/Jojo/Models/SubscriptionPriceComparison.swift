import Foundation

/// Compare the same currency and exact one-year / one-month billing periods.
/// The monthly plan is a comparison baseline, not a former price for the annual SKU.
nonisolated struct SubscriptionPriceComparison: Equatable, Sendable {
    let annualPrice: Decimal
    let monthlyPrice: Decimal
    let annualMonthlyEquivalent: Decimal
    let twelveMonthsAtMonthlyPrice: Decimal
    let annualSavings: Decimal
    let savingsPercent: Int

    init?(annualPrice: Decimal, monthlyPrice: Decimal, annualCurrency: String?, monthlyCurrency: String?, annualMonths: Int, monthlyMonths: Int) {
        guard let annualCurrency, let monthlyCurrency,
              !annualCurrency.isEmpty, annualCurrency == monthlyCurrency,
              annualMonths == 12, monthlyMonths == 1,
              annualPrice > 0, monthlyPrice > 0 else { return nil }
        let baseline = monthlyPrice * 12
        let saving = max(Decimal.zero, baseline - annualPrice)
        let percentage = saving / baseline * 100
        self.annualPrice = annualPrice
        self.monthlyPrice = monthlyPrice
        annualMonthlyEquivalent = annualPrice / 12
        twelveMonthsAtMonthlyPrice = baseline
        annualSavings = saving
        savingsPercent = Int((percentage as NSDecimalNumber).doubleValue.rounded(.down))
    }

    var hasSavings: Bool { annualSavings > 0 }
}
