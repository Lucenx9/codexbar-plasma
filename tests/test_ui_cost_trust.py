"""Static UI checks for shared cost trust notices and dismissal ownership."""

import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    cost_trust_notice_qml,
    full_representation_qml,
    id_block,
    root,
    spend_view_qml,
)


# Surface checks follow the applet owner across extracted popup components.
class CostTrustNoticeTest(unittest.TestCase):
    def setUp(self):
        self.applet = Surface("applet", root)
        self.notice_text = cost_trust_notice_qml.read_text(encoding="utf-8")
        self.spend_text = spend_view_qml.read_text(encoding="utf-8")
        self.popup_text = full_representation_qml.read_text(encoding="utf-8")

    def test_cost_views_delegate_to_shared_trust_notice_and_policy(self):
        token_cost_section_body = id_block(self.applet.text, "tokenCostSection")
        for trust_owner_source, trust_owner_text in (
            ("ProviderCostSection.qml", token_cost_section_body),
            ("SpendView.qml", self.spend_text),
        ):
            self.assertTrue(
                code_contains(trust_owner_text, "Components.CostTrustNotice"),
                f"{trust_owner_source} must render the shared cost-trust notice",
            )
            self.assertTrue(
                code_contains(trust_owner_text, "CostTrust.costTrustSummary("),
                f"{trust_owner_source} must delegate cost-trust policy to CostTrust",
            )

    def test_applet_preserves_scoped_notice_dismissals(self):
        for persistent_notice_fragment in (
            "property var costTrustNoticeStates: ({})",
            "function updateCostTrustNoticeState(",
            "CostTrust.costTrustNoticeStoreTransition(",
        ):
            self.assertTrue(
                code_contains(self.applet.text, persistent_notice_fragment),
                "the applet root must preserve scoped cost-notice dismissals across popup recreation; "
                f"missing {persistent_notice_fragment!r}",
            )

    def test_cost_trust_notice_owns_localized_message_and_style(self):
        for cost_trust_fragment in (
            "PlainNote {",
            "property var summary: null",
            "property var stateOwner: null",
            'property string noticeScope: ""',
            "property bool presentationVisible: false",
            "showCloseButton: true",
            "stateOwner.updateCostTrustNoticeState(",
            "onNoticeScopeChanged:",
            "onStateOwnerChanged:",
            'typeof stateOwner.updateCostTrustNoticeState !== "function"',
            "onSummaryChanged: scheduleRefreshNoticeState()",
            "onStateOwnerChanged: scheduleRefreshNoticeState()",
            "function scheduleRefreshNoticeState()",
            "noticeRefresh.restart()",
            "onTriggered: noticeRoot.refreshNoticeState()",
            'i18n("%1 %2"',
            'i18n("The total',
            'i18np(',
            "lacked final usage",
            "function incompleteText()",
        ):
            self.assertTrue(
                code_contains(self.notice_text, cost_trust_fragment),
                "CostTrustNotice must own the shared localized message and standard styling; "
                f"missing {cost_trust_fragment!r}",
            )

    def test_cost_trust_notice_coalesces_shared_state_changes(self):
        for non_atomic_notice_fragment in (
            "onSummaryChanged: refreshNoticeState()",
            "onNoticeScopeChanged: refreshNoticeState()",
            "onStateOwnerChanged: refreshNoticeState()",
        ):
            self.assertNotIn(
                non_atomic_notice_fragment,
                self.notice_text,
                "cost notice scope and summary changes must be coalesced before mutating shared dismissal state; "
                f"found {non_atomic_notice_fragment!r}",
            )

    def test_provider_notice_uses_persistent_scope_and_popup_visibility(self):
        token_cost_section_body = id_block(self.applet.text, "tokenCostSection")
        for provider_notice_fragment in (
            'noticeScope: "provider:" +',
            "stateOwner: tokenCostSection.applet",
            "presentationVisible: tokenCostSection.presentationVisible",
        ):
            self.assertTrue(
                code_contains(token_cost_section_body, provider_notice_fragment),
                "provider cost notices must use a persistent provider scope and visible context; "
                f"missing {provider_notice_fragment!r}",
            )
        self.assertTrue(
            code_contains(self.popup_text, "presentationVisible: fullRoot.visible && !applet.globalViewSelected"),
            "the provider cost section must receive the popup visibility context",
        )

    def test_spend_notice_uses_persistent_aggregate_scope_and_visibility(self):
        for spend_notice_fragment in (
            'noticeScope: "spend"',
            "stateOwner: view.applet",
            "presentationVisible: view.visible",
        ):
            self.assertTrue(
                code_contains(self.spend_text, spend_notice_fragment),
                "Spend cost notices must use a persistent aggregate scope and visible context; "
                f"missing {spend_notice_fragment!r}",
            )


if __name__ == "__main__":
    unittest.main()
