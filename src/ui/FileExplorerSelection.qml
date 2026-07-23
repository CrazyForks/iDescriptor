import QtQuick
import "." as App

Item {
    id: root

    required property var targetView
    required property int itemCount
    required property real rowHeight
    required property var isItemSelected
    required property var setItemSelected

    signal selectionUpdated()

    property point anchorContentPosition: Qt.point(0, 0)
    property point pressViewportPosition: Qt.point(0, 0)
    property point pointerViewportPosition: Qt.point(0, 0)
    property var selectionSnapshot: []
    property bool additiveSelection: false
    property bool selecting: false
    property bool hasDragged: false
    property int selectionAnchorIndex: -1

    readonly property real edgeScrollMargin: 48
    readonly property real maximumEdgeScrollStep: 20

    clip: true

    function reset() {
        cancelSelection()
        selectionAnchorIndex = -1
    }

    function hasAdditiveModifier(modifiers) {
        return Boolean(modifiers & (Qt.ControlModifier | Qt.MetaModifier))
    }

    function itemRect(index) {
        const item = targetView.itemAtIndex(index)
        if (item)
            return Qt.rect(item.x, item.y, item.width, item.height)

        return Qt.rect(
            0,
            targetView.originY + index * (rowHeight + targetView.spacing),
            targetView.width,
            rowHeight
        )
    }

    function selectionRectInContent() {
        const current = Qt.point(
            pointerViewportPosition.x + targetView.contentX,
            pointerViewportPosition.y + targetView.contentY
        )
        return Qt.rect(
            Math.min(anchorContentPosition.x, current.x),
            Math.min(anchorContentPosition.y, current.y),
            Math.abs(current.x - anchorContentPosition.x),
            Math.abs(current.y - anchorContentPosition.y)
        )
    }

    function applyMarqueeSelection() {
        if (!selecting || !hasDragged)
            return

        const selection = selectionRectInContent()
        selectionRectangle.x = selection.x - targetView.contentX
        selectionRectangle.y = selection.y - targetView.contentY
        selectionRectangle.width = selection.width
        selectionRectangle.height = selection.height

        let changed = false
        for (let index = 0; index < itemCount; ++index) {
            const item = itemRect(index)
            const intersects = item.x < selection.x + selection.width
                    && item.x + item.width > selection.x
                    && item.y < selection.y + selection.height
                    && item.y + item.height > selection.y
            const shouldSelect = (additiveSelection && selectionSnapshot[index]) || intersects
            if (isItemSelected(index) !== shouldSelect) {
                setItemSelected(index, shouldSelect)
                changed = true
            }
        }

        if (changed)
            selectionUpdated()
    }

    function beginSelection(mouse) {
        selectionSnapshot = []
        for (let index = 0; index < itemCount; ++index)
            selectionSnapshot.push(isItemSelected(index))

        pressViewportPosition = Qt.point(mouse.x, mouse.y)
        pointerViewportPosition = pressViewportPosition
        anchorContentPosition = Qt.point(
            mouse.x + targetView.contentX,
            mouse.y + targetView.contentY
        )
        additiveSelection = hasAdditiveModifier(mouse.modifiers)
        selecting = true
        hasDragged = false
        selectionRectangle.visible = false
    }

    function updatePointer(mouse) {
        pointerViewportPosition = Qt.point(mouse.x, mouse.y)
        if (!hasDragged) {
            hasDragged = Math.abs(mouse.x - pressViewportPosition.x) >= 2
                    || Math.abs(mouse.y - pressViewportPosition.y) >= 2
            if (hasDragged) {
                selectionAnchorIndex = -1
                selectionRectangle.visible = true
            }
        }
        applyMarqueeSelection()
    }

    function endSelection(mouse) {
        if (!selecting)
            return

        updatePointer(mouse)
        selecting = false
        selectionRectangle.visible = false
        selectionSnapshot = []
    }

    function cancelSelection() {
        selecting = false
        hasDragged = false
        selectionRectangle.visible = false
        selectionSnapshot = []
    }

    function clearSelection() {
        let changed = false
        for (let index = 0; index < itemCount; ++index) {
            if (!isItemSelected(index))
                continue
            setItemSelected(index, false)
            changed = true
        }
        selectionAnchorIndex = -1
        if (changed)
            selectionUpdated()
    }

    function selectOnly(index) {
        let changed = false
        for (let current = 0; current < itemCount; ++current) {
            const shouldSelect = current === index
            if (isItemSelected(current) !== shouldSelect) {
                setItemSelected(current, shouldSelect)
                changed = true
            }
        }
        selectionAnchorIndex = index
        if (changed)
            selectionUpdated()
    }

    function selectIndex(index, modifiers) {
        const additive = hasAdditiveModifier(modifiers)
        const rangeSelection = Boolean(modifiers & Qt.ShiftModifier)
        const validAnchor = selectionAnchorIndex >= 0 && selectionAnchorIndex < itemCount
        const rangeStart = rangeSelection && validAnchor
                ? Math.min(selectionAnchorIndex, index) : index
        const rangeEnd = rangeSelection && validAnchor
                ? Math.max(selectionAnchorIndex, index) : index
        let changed = false

        for (let current = 0; current < itemCount; ++current) {
            let shouldSelect
            if (rangeSelection) {
                const inRange = current >= rangeStart && current <= rangeEnd
                shouldSelect = additive ? isItemSelected(current) || inRange : inRange
            } else if (additive) {
                shouldSelect = current === index
                        ? !isItemSelected(current) : isItemSelected(current)
            } else {
                shouldSelect = current === index
            }

            if (isItemSelected(current) !== shouldSelect) {
                setItemSelected(current, shouldSelect)
                changed = true
            }
        }

        if (!rangeSelection || !validAnchor)
            selectionAnchorIndex = index
        if (changed)
            selectionUpdated()
    }

    function handleClick(mouse) {
        if (hasDragged)
            return

        const index = targetView.indexAt(
            mouse.x + targetView.contentX,
            mouse.y + targetView.contentY
        )
        if (index >= 0 && index < itemCount)
            selectIndex(index, mouse.modifiers)
        else if (!hasAdditiveModifier(mouse.modifiers)
                 && !(mouse.modifiers & Qt.ShiftModifier))
            clearSelection()
    }

    Rectangle {
        id: selectionRectangle

        visible: false
        color: App.Theme.selectionSoft
        border.color: App.Theme.systemBlue
        border.width: 1
        radius: 4
        opacity: 0.85
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        propagateComposedEvents: true
        scrollGestureEnabled: false

        onPressed: (mouse) => root.beginSelection(mouse)
        onPositionChanged: (mouse) => root.updatePointer(mouse)
        onReleased: (mouse) => root.endSelection(mouse)
        onCanceled: root.cancelSelection()
        onClicked: (mouse) => {
            root.handleClick(mouse)
            mouse.accepted = false
        }
        onDoubleClicked: (mouse) => {
            root.cancelSelection()
            mouse.accepted = false
        }
        onWheel: (wheel) => wheel.accepted = false
    }

    Connections {
        target: root.targetView

        function onContentYChanged() {
            root.applyMarqueeSelection()
        }
    }

    Timer {
        interval: 16
        repeat: true
        running: root.selecting && root.hasDragged

        onTriggered: {
            let step = 0
            if (root.pointerViewportPosition.y < root.edgeScrollMargin) {
                const proximity = 1 - Math.max(0, root.pointerViewportPosition.y)
                        / root.edgeScrollMargin
                step = -root.maximumEdgeScrollStep * proximity
            } else if (root.pointerViewportPosition.y > root.height - root.edgeScrollMargin) {
                const distance = Math.max(0, root.height - root.pointerViewportPosition.y)
                const proximity = 1 - distance / root.edgeScrollMargin
                step = root.maximumEdgeScrollStep * proximity
            }

            if (step === 0)
                return

            const minimumY = root.targetView.originY
            const maximumY = Math.max(
                minimumY,
                minimumY + root.targetView.contentHeight - root.targetView.height
            )
            root.targetView.contentY = Math.max(
                minimumY,
                Math.min(maximumY, root.targetView.contentY + step)
            )
        }
    }
}
