import QtQuick

// Ambxst's halftone background: a fine grid of 2px dots on a dark base.
Canvas {
    id: cv
    property color base: Theme.background
    property color dot: Theme.dot
    property int step: 4
    onBaseChanged: requestPaint()
    onDotChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const g = getContext("2d");
        g.fillStyle = base;
        g.fillRect(0, 0, width, height);
        g.fillStyle = dot;
        for (let y = 3; y < height - 2; y += step)
            for (let x = 1; x < width - 2; x += step)
                g.fillRect(x, y, 2, 2);
    }
}
