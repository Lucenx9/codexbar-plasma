import QtQuick
import "../ProviderCostPresentation.js" as ProviderCostPresentation
import "../CostPresentation.js" as CostPresentation

// Localized cost and credit details. Cost/reset inputs are classified by the
// pure module; monthly credit limits arrive normalized by ProviderNormalizer.
// The applet supplies its regional number format, without sharing root state.
QtObject {
    id: root

    property var numberFormat: ({})

    function costSection(providerID, cost) {
        var section = ProviderCostPresentation.section(providerID, cost)
        if (section === null) {
            return null
        }
        var title = i18n("Extra usage")
        switch (section.titleKey) {
        case "zenBalance":
            title = i18n("Zen balance")
            break
        case "credits":
            title = i18n("Credits")
            break
        case "quotaUsage":
            title = i18n("Quota usage")
            break
        case "apiSpend":
            title = i18n("API spend")
            break
        }
        var result = {
            title: title,
            percentUsed: section.percentUsed,
            spendLine: "",
            percentLine: "",
            personalSpendLine: ""
        }
        if (section.kind === "balance" || section.kind === "pointsBalance") {
            result.spendLine = i18n("Balance: %1", section.kind === "pointsBalance"
                ? Math.round(section.used) : amountString(section.used, section.currency))
        } else {
            var period = section.period === null ? i18n("This month") : localizedPeriod(section.period)
            if (section.kind === "allowance") {
                result.spendLine = i18n("%1: %2 / %3", period,
                    amountString(section.used, section.currency), amountString(section.limit, section.currency))
                result.percentLine = i18n("%1% used", Math.round(section.percentUsed))
                if (section.personalUsed !== null) {
                    result.personalSpendLine = i18n("Your spend: %1", amountString(section.personalUsed, section.currency))
                }
            } else {
                result.spendLine = i18n("%1: %2", period, amountString(section.used, section.currency))
            }
        }
        return result
    }

    function resetSection(providerID, resetCredits) {
        var count = ProviderCostPresentation.resetCount(providerID, resetCredits)
        return count === null ? null : {
            title: i18n("Reset credits"),
            line: i18np("%1 available", "%1 available", count)
        }
    }

    function creditLimitRow(creditLimit) {
        if (!creditLimit) {
            return null
        }
        return {
            lane: "monthlyCredits",
            label: creditLimit.title.length > 0
                ? creditLimit.title
                : i18n("Monthly credit limit"),
            hasPercent: true,
            usedPercent: creditLimit.usedPercent,
            leftPercent: creditLimit.leftPercent,
            pacePercent: -1,
            paceOnTop: true,
            paceEtaSeconds: 0,
            resetsAt: creditLimit.resetsAt,
            resetDescription: "",
            reset: "",
            pace: "",
            summaryText: i18n("Used: %1, remaining: %2 of %3",
                formatNumber(creditLimit.used),
                formatNumber(creditLimit.remaining),
                formatNumber(creditLimit.limit))
        }
    }

    function localizedPeriod(value) {
        var text = String(value || "").trim()
        switch (text.toLowerCase()) {
        case "last 30 days":
            return i18n("Last 30 days")
        case "this month":
            return i18n("This month")
        case "today":
            return i18n("Today")
        default:
            return text
        }
    }

    function amountString(value, currency) {
        return CostPresentation.amountString(root.numberFormat, value, currency)
    }

    function formatNumber(value) {
        return CostPresentation.formatCount(root.numberFormat, value)
    }
}
