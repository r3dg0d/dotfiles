import QtQuick

Text {
    property string icon: ""
    property int size: 18
    text: icon
    font.family: Theme.icons
    font.pixelSize: size
    color: Theme.primary
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
}
