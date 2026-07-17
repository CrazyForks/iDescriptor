import QtQuick

Item {
    id: root

    required property var targetView
    required property int itemCount
    required property real selectableItemWidth
    required property real selectableItemHeight
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

    function contentSelectionRect() {
        const currentContentPosition = Qt.point(
            pointerViewportPosition.x + targetView.contentX,
            pointerViewportPosition.y + targetView.contentY
        )

        return {
            x: Math.min(anchorContentPosition.x, currentContentPosition.x),
            y: Math.min(anchorContentPosition.y, currentContentPosition.y),
            width: Math.abs(currentContentPosition.x - anchorContentPosition.x),
            height: Math.abs(currentContentPosition.y - anchorContentPosition.y)
        }
    }

    function updateSelectionRectangle(rect) {
        selectionRect.x = rect.x - targetView.contentX
        selectionRect.y = rect.y - targetView.contentY
        selectionRect.width = rect.width
        selectionRect.height = rect.height
    }

    function gridLayoutOffset(columns) {
        // GridView does not instantiate every off-screen delegate. Use any available
        // delegate to preserve the view's actual content origin for inferred rows.
        for (let i = 0; i < itemCount; ++i) {
            const item = targetView.itemAtIndex(i)
            if (!item)
                continue

            return Qt.point(
                item.x - (i % columns) * targetView.cellWidth,
                item.y - Math.floor(i / columns) * targetView.cellHeight
            )
        }
        return Qt.point(0, 0)
    }

    function applySelection() {
        if (!selecting || !hasDragged)
            return

        const rect = contentSelectionRect()
        updateSelectionRectangle(rect)

        const columns = Math.max(1, Math.floor(targetView.width / targetView.cellWidth))
        const layoutOffset = gridLayoutOffset(columns)
        let changed = false

        for (let i = 0; i < itemCount; ++i) {
            const visibleItem = targetView.itemAtIndex(i)
            const itemX = visibleItem
                        ? visibleItem.x
                        : layoutOffset.x + (i % columns) * targetView.cellWidth
            const itemY = visibleItem
                        ? visibleItem.y
                        : layoutOffset.y + Math.floor(i / columns) * targetView.cellHeight
            const itemWidth = visibleItem ? visibleItem.width : selectableItemWidth
            const itemHeight = visibleItem ? visibleItem.height : selectableItemHeight

            const intersects =
                itemX < rect.x + rect.width &&
                itemX + itemWidth > rect.x &&
                itemY < rect.y + rect.height &&
                itemY + itemHeight > rect.y
            const shouldSelect = (additiveSelection && selectionSnapshot[i]) || intersects

            if (isItemSelected(i) !== shouldSelect) {
                setItemSelected(i, shouldSelect)
                changed = true
            }
        }

        if (changed)
            selectionUpdated()
    }

    function beginSelection(mouse) {
        selectionSnapshot = []
        for (let i = 0; i < itemCount; ++i)
            selectionSnapshot.push(isItemSelected(i))

        pressViewportPosition = Qt.point(mouse.x, mouse.y)
        pointerViewportPosition = pressViewportPosition
        anchorContentPosition = Qt.point(
            mouse.x + targetView.contentX,
            mouse.y + targetView.contentY
        )
        additiveSelection = hasAdditiveModifier(mouse.modifiers)
        hasDragged = false
        selecting = true

        selectionRect.x = mouse.x
        selectionRect.y = mouse.y
        selectionRect.width = 0
        selectionRect.height = 0
        selectionRect.visible = false
    }

    function updatePointer(mouse) {
        pointerViewportPosition = Qt.point(mouse.x, mouse.y)
        if (!hasDragged) {
            hasDragged = Math.abs(mouse.x - pressViewportPosition.x) >= 1
                      || Math.abs(mouse.y - pressViewportPosition.y) >= 1
            if (hasDragged)
                selectionAnchorIndex = -1
            selectionRect.visible = hasDragged
        }
        applySelection()
    }

    function endSelection(mouse) {
        if (!selecting)
            return

        updatePointer(mouse)
        selecting = false
        selectionRect.visible = false
        selectionSnapshot = []
    }

    function cancelSelection() {
        selecting = false
        hasDragged = false
        selectionRect.visible = false
        selectionSnapshot = []
    }

    function hasAdditiveModifier(modifiers) {
        return Boolean(modifiers & (Qt.ControlModifier | Qt.MetaModifier))
    }

    function setSelectionForClick(index, modifiers) {
        const additive = hasAdditiveModifier(modifiers)
        const rangeSelection = Boolean(modifiers & Qt.ShiftModifier)
        const hasValidAnchor = selectionAnchorIndex >= 0 && selectionAnchorIndex < itemCount
        let rangeStart = index
        let rangeEnd = index

        if (rangeSelection && hasValidAnchor) {
            rangeStart = Math.min(selectionAnchorIndex, index)
            rangeEnd = Math.max(selectionAnchorIndex, index)
        }

        let changed = false
        for (let i = 0; i < itemCount; ++i) {
            let shouldSelect
            if (rangeSelection) {
                const inRange = i >= rangeStart && i <= rangeEnd
                shouldSelect = additive ? isItemSelected(i) || inRange : inRange
            } else if (additive) {
                shouldSelect = i === index ? !isItemSelected(i) : isItemSelected(i)
            } else {
                shouldSelect = i === index
            }

            if (isItemSelected(i) !== shouldSelect) {
                setItemSelected(i, shouldSelect)
                changed = true
            }
        }

        if (!rangeSelection || !hasValidAnchor)
            selectionAnchorIndex = index

        if (changed)
            selectionUpdated()
    }

    function clearSelection() {
        let changed = false
        for (let i = 0; i < itemCount; ++i) {
            if (!isItemSelected(i))
                continue
            setItemSelected(i, false)
            changed = true
        }

        selectionAnchorIndex = -1
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

        if (index >= 0 && index < itemCount) {
            setSelectionForClick(index, mouse.modifiers)
        } else if (!hasAdditiveModifier(mouse.modifiers) && !(mouse.modifiers & Qt.ShiftModifier)) {
            clearSelection()
        }
    }

    Rectangle {
        id: selectionRect
        color: "transparent"
        border.color: "blue"
        border.width: 1
        visible: false
        opacity: 0.3

        Rectangle {
            anchors.fill: parent
            color: "blue"
            opacity: 0.2
        }
    }

    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        scrollGestureEnabled: false

        onPressed: (mouse) => root.beginSelection(mouse)
        onPositionChanged: (mouse) => root.updatePointer(mouse)
        onReleased: (mouse) => root.endSelection(mouse)
        onCanceled: root.cancelSelection()

        // Apply standard desktop selection, then preserve delegate click handling.
        onClicked: (mouse) => {
            root.handleClick(mouse)
            mouse.accepted = false
        }
        onDoubleClicked: (mouse) => mouse.accepted = false

        // scrollGestureEnabled passes trackpad gestures through. Explicitly reject
        // physical wheel events as well so the GridView can scroll underneath.
        onWheel: (wheel) => wheel.accepted = false
    }

    Connections {
        target: root.targetView

        function onContentYChanged() {
            root.applySelection()
        }
    }

    Timer {
        interval: 16
        repeat: true
        running: root.selecting && root.hasDragged

        onTriggered: {
            let step = 0
            if (root.pointerViewportPosition.y < root.edgeScrollMargin) {
                const proximity = 1 - Math.max(0, root.pointerViewportPosition.y) / root.edgeScrollMargin
                step = -root.maximumEdgeScrollStep * proximity
            } else if (root.pointerViewportPosition.y > root.height - root.edgeScrollMargin) {
                const distanceFromBottom = Math.max(0, root.height - root.pointerViewportPosition.y)
                const proximity = 1 - distanceFromBottom / root.edgeScrollMargin
                step = root.maximumEdgeScrollStep * proximity
            }

            if (step === 0)
                return

            const minimumY = root.targetView.originY
            const maximumY = Math.max(
                minimumY,
                minimumY + root.targetView.contentHeight - root.targetView.height
            )
            const nextY = Math.max(minimumY, Math.min(maximumY, root.targetView.contentY + step))

            if (nextY !== root.targetView.contentY)
                root.targetView.contentY = nextY
        }
    }
}
