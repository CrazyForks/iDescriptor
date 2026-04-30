import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import com.kdab.cxx_qt.demo 1.0

Item {
    id: root
    property int currentIndex : 0


    DeviceTab {
        id : device
        anchors.fill: parent
        visible : currentIndex == 0
        opacity: root.currentIndex === 0 ? 1 : 0
        property real slideY: root.currentIndex === 0 ? 0 : 20
        transform: Translate { y: device.slideY }

        Behavior on opacity {
            NumberAnimation { duration: 167; easing.type: Easing.OutCubic }
        }
        Behavior on slideY {
            NumberAnimation { duration: 167; easing.type: Easing.OutCubic }
        }
    }

}
