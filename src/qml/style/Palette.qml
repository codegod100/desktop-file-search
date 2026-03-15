import QtQuick
import "palette.tokens.js" as Tokens

QtObject {
    readonly property var tokens: Tokens.tokens.color

    function tokenColor(group, name) {
        return tokens[group][name].$value.hex
    }

    readonly property color backgroundCanvas: tokenColor("background", "canvas")
    readonly property color backgroundElevated: tokenColor("background", "elevated")
    readonly property color surfaceLeft: tokenColor("surface", "left")
    readonly property color surfaceRight: tokenColor("surface", "right")
    readonly property color surfaceRaised: tokenColor("surface", "raised")
    readonly property color borderStrong: tokenColor("border", "strong")
    readonly property color borderSoft: tokenColor("border", "soft")
    readonly property color textPrimary: tokenColor("text", "primary")
    readonly property color textSecondary: tokenColor("text", "secondary")
    readonly property color accentPrimary: tokenColor("accent", "primary")
}
