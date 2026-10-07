"""Static UI checks for the Sessions view."""

import re
import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    copyable_value_qml,
    function_body,
    root,
    session_labels_qml,
    sessions_view_qml,
)

# The popup UI rules below belong to the plasmoid surface, not to main.qml
# specifically, so read the surface as one text. Extracting the popup into a
# component keeps these assertions meaningful instead of silently unhooking them.
applet = Surface("applet", root)
main_text = applet.text
sessions_view_text = sessions_view_qml.read_text(encoding="utf-8")
session_labels_text = session_labels_qml.read_text(encoding="utf-8")
copyable_value_text = copyable_value_qml.read_text(encoding="utf-8")


class SessionsTest(unittest.TestCase):
    def test_session_labels_are_localized(self):
        applet.require("text: sessionLabels.sessionStateText(modelData.state)", "session states must use localized labels")
        applet.require("details.push(root.sessionSourceText(item.source))", "session sources must use localized labels")

        applet.require_definition_where_used("sessionStateText")
        applet.require_definition_where_used("sessionSourceText")

        applet.reject("view.applet.capitalize(modelData.state)", "session states must not bypass translations")

    def test_sessions_lifecycle(self):
        for session_contract_fragment in (
            '"sessions", "--json-v2"',
            "SessionResponse.response(stdoutText, stderrText)",
            "maximumSessions = 128",
            "function normalizeSession(item)",
        ):
            if not code_contains(main_text, session_contract_fragment):
                raise AssertionError(f"sessions lifecycle is missing {session_contract_fragment!r}")
        for forbidden_session_value in ("transcriptPath", "cwd"):
            if forbidden_session_value in sessions_view_text:
                raise AssertionError(
                    "SessionsView must never render or follow local session paths; "
                    f"found {forbidden_session_value!r}"
                )

        normalize_session_body = function_body(main_text, "normalizeSession")
        for activity_fallback_fragment in (
            "item.lastActivityAt",
            "item.startedAt",
            "activityAt: activityAt",
            "activityMs: activityMs",
        ):
            if not code_contains(normalize_session_body, activity_fallback_fragment):
                raise AssertionError(
                    "session activity must prefer lastActivityAt and safely fall back to startedAt; "
                    f"missing {activity_fallback_fragment!r}"
                )
        if "lastActivityMs" in main_text:
            raise AssertionError("session ordering must use the normalized activity fallback")

        # The shape check lives in the normalizer and the error text in the applet, so
        # the rule is asserted on both halves: an unrecognized payload must return the
        # "unsupported" sentinel rather than an empty list, and the caller must turn that
        # sentinel into a visible error instead of an empty successful snapshot.
        normalize_sessions_body = function_body(main_text, "normalizeSessions")
        for rejected_shape_fragment in (
            "Array.isArray(payload)",
            "Array.isArray(payload.sessions)",
            "return null",
        ):
            if not code_contains(normalize_sessions_body, rejected_shape_fragment):
                raise AssertionError(
                    "unexpected session payload shapes must be rejected, not emptied; "
                    f"missing {rejected_shape_fragment!r}"
                )
        if ": []" in normalize_sessions_body:
            raise AssertionError("unexpected session payload shapes must not become an empty successful snapshot")

        applet.require("codexbar sessions returned an unsupported JSON payload.",
                       "unsupported Sessions output must have a localized error")
        # SessionResponse QtTests distinguish failed output from confirmed empty data;
        # the controller tests verify that only a successful result replaces a snapshot.

    def test_session_clipboard(self):
        for shared_copy_fragment in (
            "function copySessionValue(text, valueKey)",
            "id: clipboardBuffer",
            "id: copiedTimer",
        ):
            if not code_contains(sessions_view_text, shared_copy_fragment):
                raise AssertionError(
                    "SessionsView must own one shared clipboard lifecycle; "
                    f"missing {shared_copy_fragment!r}"
                )
        if not re.search(
            r"Connections\s*\{.*?target:\s*view\.applet.*?"
            r"function\s+onSessionsChanged\(\)\s*\{\s*"
            r'view\.copiedValueKey\s*=\s*"";?\s*\}',
            sessions_view_text,
            re.S,
        ):
            raise AssertionError(
                "SessionsView must clear copy feedback when the sessions snapshot is replaced"
            )
        if not code_contains(sessions_view_text, 'readonly property string titleCopyKey: "title:" + index'):
            raise AssertionError(
                "session copy keys must remain index-scoped inside one unchanged snapshot"
            )
        if sessions_view_text.count("Controls.TextField {") != 1 or sessions_view_text.count("Timer {") != 2:
            raise AssertionError("SessionsView must instantiate exactly one clipboard field and two shared timers")
        for per_delegate_copy_fragment in ("Controls.TextField {", "Timer {"):
            if per_delegate_copy_fragment in copyable_value_text:
                raise AssertionError(
                    "CopyableValue delegates must not allocate clipboard controls or timers; "
                    f"found {per_delegate_copy_fragment!r}"
                )
        if not code_contains(copyable_value_text, "valueRow.copyRevealed || valueRow.copied || hovered || activeFocus"):
            raise AssertionError(
                "the copy action must stay reachable by keyboard and while confirming a copy, "
                "not only while the owning row is hovered"
            )
        if not code_contains(copyable_value_text, "PlainPlasmaLabel {"):
            raise AssertionError("CopyableValue must render untrusted CLI values as plain text")
        if sessions_view_text.count("PlainPlasmaLabel {") < 3:
            raise AssertionError("all direct session labels must render CLI-derived text as plain text")
        if sessions_view_text.count("copyRevealed: sessionCardHover.hovered") != 1:
            raise AssertionError(
                "the single session copy action must be revealed by the shared card hover handler "
                "instead of crowding every card permanently"
            )
        if "Copy session details" in sessions_view_text:
            raise AssertionError(
                "session details are secondary metadata; only the session title offers a copy action"
            )
        if not code_contains(sessions_view_text, "? Kirigami.Theme.positiveTextColor"):
            raise AssertionError(
                "session state must use the theme's meaning color, not the provider accent, "
                "so the same state reads the same for every provider"
            )
        for active_session_state in (
            'modelData.state === "active"',
            'modelData.state === "running"',
        ):
            if not code_contains(sessions_view_text, active_session_state):
                raise AssertionError(
                    "SessionsView must highlight both live state spellings accepted from the CLI; "
                    f"missing {active_session_state!r}"
                )
        for optional_session_details_fragment in (
            "readonly property string subtitle: sessionLabels.sessionSubtitle( modelData, view.applet.sessionHostsVary)",
            "visible: sessionCard.subtitle.length > 0",
            "text: sessionCard.subtitle",
        ):
            if not code_contains(sessions_view_text, optional_session_details_fragment):
                raise AssertionError(
                    "sessions without optional detail fields must not render an empty details line; "
                    f"missing {optional_session_details_fragment!r}"
                )

        if not code_contains(sessions_view_text, "sessionCardHover.hovered ? 0.075 : 0.035"):
            raise AssertionError("session cards must confirm hover on the surface that reveals their copy actions")

    def test_session_ages(self):
        session_activity_body = function_body(session_labels_text, "sessionActivityText")
        if not code_contains(session_activity_body, "root.applet.elapsedText(Number(item.activityMs), nowMs)"):
            raise AssertionError("session ages must use the shared elapsedText helper with the live clock")
        elapsed_body = function_body(main_text, "elapsedText")
        for live_age_fragment in (
            "Number(nowMs)",
            "currentTimeMs - sinceMs",
        ):
            if not code_contains(elapsed_body, live_age_fragment):
                raise AssertionError(
                    "relative session ages must depend on a periodically updated clock; "
                    f"missing {live_age_fragment!r}"
                )
        for session_clock_fragment in (
            "property double sessionClockMs: Date.now()",
            "id: sessionAgeTimer",
            "sessionActivityText(modelData, view.sessionClockMs)",
        ):
            if not code_contains(sessions_view_text, session_clock_fragment):
                raise AssertionError(
                    "SessionsView must refresh relative ages even when CLI refresh is manual; "
                    f"missing {session_clock_fragment!r}"
                )


if __name__ == "__main__":
    unittest.main()
