import QtQuick

// Base text node. NativeRendering keeps glyph edges on pixel boundaries,
// which matters a lot for box-drawing characters -- with the default
// distance-field renderer, adjacent ─ characters develop visible seams.
Text {
    color: Theme.fg
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    font.hintingPreference: Font.PreferFullHinting
    renderType: Text.NativeRendering
    textFormat: Text.PlainText
    verticalAlignment: Text.AlignVCenter
}
