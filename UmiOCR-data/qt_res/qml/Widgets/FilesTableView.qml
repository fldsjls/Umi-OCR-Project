// =============== 文件表格面板 ===============

import QtQuick 2.15
import QtQuick.Controls 2.15
import Qt.labs.qmlmodels 1.0 // 表格
import QtGraphicalEffects 1.15 // 子元素圆角
import QtQuick.Dialogs 1.3 // 文件对话框

Item {
    id: fTableRoot

    // ========================= 【定义】 =========================

    // 表头。定义每一列。
    property var headers: [
        // 第一列也作为总key（tk），不允许重复。
        {key: "path", title: "文件", },
        {key: "time", title: "耗时", },
        {key: "state", title: "状态", },
        // 可选项：
        // btn:  true 启用按钮
        // onClicked: 单击函数
        // left: true 左对齐
        // display: 显示函数，输入value，返回显示文本
    ]
    property string openBtnText: "选择文件"
    property string clearBtnText: "清空"
    property string defaultTips: "拖入或选择文件"
    property string fileDialogTitle: "请选择文件"
    property var fileDialogNameFilters: ["文件 (*.jpg *.jpe *.jpeg *.jfif *.png *.webp *.bmp *.tif *.tiff)"]
    property int spacing: size_.smallLine // 表项水平间隔
    property int minWidth0: size_.smallLine * 5 // 第0列最小宽度
    property bool isLock: false // 是否锁定UI操作
    property bool showOpenButton: true
    property bool showClearButton: true
    property bool autoElide: true
    property bool showCellToolTip: true
    property bool enableColumnResize: true
    property int minColumnWidth: size_.smallLine * 3
    property real maxAutoColumnWidthRatio: 0.45
    property bool enableSelection: false
    property string copyImageKey: "path"
    property int selectionUpdate: 0
    property int lastSelectedIndex: -1
    property int anchorIndex: -1
    property var selectedRows: ({})
    property bool dragSelecting: false
    property bool dragSelectMoved: false
    property real dragStartX: 0
    property real dragStartY: 0
    property real dragCurrentX: 0
    property real dragCurrentY: 0
    property int dragStartRow: -1
    property int dragModifiers: 0
    property var dragBaseRows: ({})


    // ========================= 【调用接口】 =========================

    // 增：添加一项。 row：字典，key在headers中，如 { "path" "time" "state" }
    // ik：可以是表格行index（int），也可以是总key（string）
    function add(row, ik=-1) {
        const key = row[headerKey]
        if(key in dataDict) {
            console.warn(`add: ${key} 已在dataDict中！`)
            return false
        }
        if(ik === -1 || ik === rowCount) {
            dataDict[key] = rowCount
            dataModel.append(row)
        }
        else {
            const i = ik2i(ik)
            if(i < 0) {
                console.warn(`add: ik ${ik} ${i} < 0 ！`)
                return false
            }
            dataDict[key] = i
            dataModel.insert(i, row)
        }
        updateWidth()
        return true
    }
    // 删：删除一项
    function del(ik) {
        const i = ik2i(ik)
        if(i < 0) {
            console.warn(`del: ik ${ik} ${i} < 0 ！`)
            return false
        }
        const key = dataModel.get(i)[headerKey]
        delete dataDict[key]
        dataModel.remove(i)
        return true
    }
    // 删：清空
    function clear() {
        dataModel.clear()
        dataDict = {}
        clearSelection()
    }
    // 改：属性字典
    function set(ik, columnDict) {
        const i = ik2i(ik)
        if(i < 0) {
            console.warn(`set: ik ${ik} ${i} < 0 ！`)
            return false
        }
        dataModel.set(i, columnDict)
        updateWidth()
        return true
    }
    // 改：单个属性
    function setProperty(ik, columnKey, value) {
        const i = ik2i(ik)
        if(i < 0) {
            console.warn(`setProperty: ik ${ik} ${i} < 0 ！`)
            return false
        }
        dataModel.setProperty(i, columnKey, value)
        updateWidth()
        return true
    }
    // 查：ik转index。返回-1表示失败。
    function ik2i(ik) {
        if (typeof ik === "number") {
            if(ik >= 0 && ik < rowCount)
                return ik
        } else if (typeof ik === "string") {
            if(ik in dataDict)
                return dataDict[ik]
        }
        return -1
    }
    // 查：获取单个行的字典
    function get(ik) {
        const i = ik2i(ik)
        if(i < 0) {
            console.warn(`get: ik ${ik} ${i} < 0 ！`)
            return {}
        }
        return dataModel.get(i)
    }
    // 查：获取key列的所有数据，返回每项为value
    function getColumnsValue(key) {
        let list = []
        for(let y = 0; y < rowCount; y++) {
            list.push( dataModel.get(y)[key] )
        }
        return list
    }
    // 查：获取多个列的数据，返回每项为字典
    function getColumnsValues(keys=[]) {
        let list = []
        if(keys.length > 0) {
            for(let y = 0; y < rowCount; y++) {
                const data = dataModel.get(y)
                const d = {}
                for(let i in keys)
                    d[keys[i]] = data[keys[i]]
                list.push(d)
            }
        }
        else {
            for(let y = 0; y < rowCount; y++)
                list.push(dataModel.get(y))
        }
        return list
    }

    // 定义信号
    signal addPaths(var paths) // 添加文件的信号
    signal click(var info) // 点击条目的信号

    Keys.onPressed: {
        if(enableSelection) {
            if((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_A) {
                selectAllRows()
                event.accepted = true
            }
            else if((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) {
                copySelectedImages()
                event.accepted = true
            }
        }
    }

    Component.onCompleted: {
        dataDict = {}
        columnCount = headers.length
        for(let i=0; i<columnCount; i++){
            headerModel.append({
                "key": headers[i].key,
                "title": headers[i].title,
                "width": 1,
                "userWidth": -1,
            })
        }
        headerKey = headers[0].key
        updateWidth(true)
    }

    // ========================= 【逻辑】 =========================

    property int columnCount: 0 // 列数量， onCompleted 中初始化
    property int rowCount: dataModel.count // 行数量
    property string headerKey: "" // 自动
    // 表头， key title width
    ListModel { id: headerModel }
    // 数据， 项为headers的key
    ListModel { id: dataModel }
    property var dataDict: {} // 指向 dataModel 的 index
    onRowCountChanged: {
        headerModel.setProperty(0, "title", headers[0].title + ` (${rowCount})`)
    }

    function toDisplayString(value) {
        if(value === undefined || value === null)
            return ""
        return String(value)
    }
    function getCellText(row, header) {
        if(!header)
            return ""
        const value = row[header.key]
        return toDisplayString(header.display ? header.display(value, row) : value)
    }
    function getCellToolTipText(row, header, displayText) {
        if(!header)
            return displayText
        if(header.toolTipDisplay)
            return toDisplayString(header.toolTipDisplay(row[header.key], row))
        if(header.toolTipKey && row[header.toolTipKey] !== undefined)
            return toDisplayString(row[header.toolTipKey])
        return toDisplayString(row[header.key] !== undefined ? row[header.key] : displayText)
    }
    function getColumnMinWidth(column) {
        const header = headers[column]
        if(header && header.minWidth !== undefined)
            return Math.max(1, header.minWidth)
        return column === 0 ? minWidth0 : minColumnWidth
    }
    function getColumnMaxAutoWidth(column) {
        const header = headers[column]
        const minWidth = getColumnMinWidth(column)
        if(header && header.maxWidth !== undefined)
            return Math.max(minWidth, header.maxWidth)
        if(tableArea.width <= 0)
            return 999999
        return Math.max(minWidth, tableArea.width * maxAutoColumnWidthRatio)
    }
    function setColumnUserWidth(column, width) {
        if(column < 0 || column >= columnCount)
            return
        const w = Math.max(getColumnMinWidth(column), width)
        headerModel.setProperty(column, "userWidth", w)
        headerModel.setProperty(column, "width", w)
    }
    function resetColumnUserWidth(column) {
        if(column < 0 || column >= columnCount)
            return
        headerModel.setProperty(column, "userWidth", -1)
        updateWidth(true)
    }
    function resizeColumnPair(column, dx, leftStartWidth, rightStartWidth) {
        if(column < 0 || column >= columnCount - 1)
            return
        const rightColumn = column + 1
        const leftMin = getColumnMinWidth(column)
        const rightMin = getColumnMinWidth(rightColumn)
        const total = leftStartWidth + rightStartWidth
        let leftWidth = leftStartWidth + dx
        let rightWidth = rightStartWidth - dx
        if(leftWidth < leftMin) {
            leftWidth = leftMin
            rightWidth = total - leftWidth
        }
        if(rightWidth < rightMin) {
            rightWidth = rightMin
            leftWidth = total - rightWidth
        }
        if(column === 0) {
            setColumnUserWidth(rightColumn, rightWidth)
            updateWidth0()
        }
        else {
            setColumnUserWidth(column, leftWidth)
            setColumnUserWidth(rightColumn, rightWidth)
        }
    }

    function bumpSelectionUpdate() {
        selectionUpdate++
        if(selectionUpdate > 100000)
            selectionUpdate = 0
    }
    function isRowSelected(row) {
        selectionUpdate
        return selectedRows[row] === true
    }
    function clearSelection() {
        selectedRows = {}
        lastSelectedIndex = -1
        anchorIndex = -1
        bumpSelectionUpdate()
    }
    function selectSingleRow(row) {
        if(row < 0 || row >= rowCount)
            return
        selectedRows = {}
        selectedRows[row] = true
        lastSelectedIndex = row
        anchorIndex = row
        bumpSelectionUpdate()
    }
    function selectAllRows() {
        selectedRows = {}
        for(let i = 0; i < rowCount; i++)
            selectedRows[i] = true
        if(rowCount > 0) {
            lastSelectedIndex = rowCount - 1
            if(anchorIndex < 0)
                anchorIndex = 0
        }
        bumpSelectionUpdate()
    }
    function copySelectionMap(source) {
        const target = {}
        for(let key in source) {
            if(source[key])
                target[key] = true
        }
        return target
    }
    function toggleRowSelection(row) {
        if(row < 0 || row >= rowCount)
            return
        const next = copySelectionMap(selectedRows)
        if(next[row])
            delete next[row]
        else
            next[row] = true
        selectedRows = next
        lastSelectedIndex = row
        anchorIndex = row
        bumpSelectionUpdate()
    }
    function selectRangeRows(fromRow, toRow, keepExisting=false) {
        if(rowCount <= 0)
            return
        const a = Math.max(0, Math.min(rowCount - 1, fromRow))
        const b = Math.max(0, Math.min(rowCount - 1, toRow))
        const left = Math.min(a, b)
        const right = Math.max(a, b)
        const next = keepExisting ? copySelectionMap(selectedRows) : {}
        for(let i = left; i <= right; i++)
            next[i] = true
        selectedRows = next
        lastSelectedIndex = toRow
        if(anchorIndex < 0)
            anchorIndex = fromRow
        bumpSelectionUpdate()
    }
    function selectedIndexes() {
        const rows = []
        for(let key in selectedRows) {
            if(selectedRows[key]) {
                const row = Number(key)
                if(row >= 0 && row < rowCount)
                    rows.push(row)
            }
        }
        rows.sort(function(a, b){ return a - b })
        return rows
    }
    function selectedImagePaths() {
        const rows = selectedIndexes()
        const paths = []
        for(let i = 0; i < rows.length; i++) {
            const row = dataModel.get(rows[i])
            if(row && row[copyImageKey])
                paths.push(row[copyImageKey])
        }
        return paths
    }
    function copySelectedImages() {
        const paths = selectedImagePaths()
        if(paths.length <= 0) {
            qmlapp.popup.simple(qsTr("文件：无选中文件"), "")
            return
        }
        let res = ""
        if(qmlapp.imageManager.copyImages)
            res = qmlapp.imageManager.copyImages(paths)
        else
            res = qmlapp.imageManager.copyImage(paths[0])
        if(res && res.startsWith("[Success]"))
            qmlapp.popup.simple(qsTr("文件：复制%1个").arg(paths.length), "")
        else
            qmlapp.popup.simple(qsTr("复制文件失败"), res)
    }
    function activateRow(row) {
        if(row < 0 || row >= rowCount)
            return
        for(let i = 0; i < headers.length; i++) {
            if(headers[i].onClicked) {
                headers[i].onClicked(row)
                return
            }
        }
    }
    function tableRowStep() {
        return Math.max(1, size_.smallLine * 1.5 + tableView.rowSpacing)
    }
    function rowAtTableY(y, clamp=true) {
        if(rowCount <= 0)
            return -1
        const row = Math.floor((tableView.contentY + y) / tableRowStep())
        if(!clamp && (row < 0 || row >= rowCount))
            return -1
        return Math.max(0, Math.min(rowCount - 1, row))
    }
    function isPointOnTableRow(y) {
        if(rowCount <= 0 || y < 0)
            return false
        const contentBottom = rowCount * tableRowStep() - tableView.contentY - tableView.rowSpacing
        return y < contentBottom
    }
    function clampTablePoint(point) {
        return {
            "x": Math.max(0, Math.min(tableView.width, point.x)),
            "y": Math.max(0, Math.min(tableView.height, point.y)),
        }
    }
    function selectDragRows(currentRow) {
        if(dragStartRow < 0 || currentRow < 0)
            return
        const keepExisting = (dragModifiers & Qt.ControlModifier) !== 0
        const next = keepExisting ? copySelectionMap(dragBaseRows) : {}
        const left = Math.min(dragStartRow, currentRow)
        const right = Math.max(dragStartRow, currentRow)
        for(let i = left; i <= right; i++)
            next[i] = true
        selectedRows = next
        lastSelectedIndex = currentRow
        anchorIndex = dragStartRow
        bumpSelectionUpdate()
    }
    function selectDragRectRows(fromY, toY) {
        if(rowCount <= 0)
            return
        const keepExisting = (dragModifiers & Qt.ControlModifier) !== 0
        const next = keepExisting ? copySelectionMap(dragBaseRows) : {}
        const step = tableRowStep()
        const rectTop = tableView.contentY + Math.min(fromY, toY)
        const rectBottom = tableView.contentY + Math.max(fromY, toY)
        const contentTop = 0
        const contentBottom = rowCount * step
        const overlapTop = Math.max(contentTop, rectTop)
        const overlapBottom = Math.min(contentBottom, rectBottom)
        if(overlapTop < overlapBottom) {
            const firstRow = Math.max(0, Math.floor(overlapTop / step))
            const lastRow = Math.min(rowCount - 1, Math.floor((overlapBottom - 0.001) / step))
            for(let i = firstRow; i <= lastRow; i++)
                next[i] = true
            lastSelectedIndex = lastRow
            anchorIndex = firstRow
        }
        selectedRows = next
        bumpSelectionUpdate()
    }
    function handleSelectionPressed(row, item, mouse) {
        if(!enableSelection || row < 0 || row >= rowCount)
            return
        forceActiveFocus()
        const modifiers = mouse.modifiers || 0
        if(mouse.button === Qt.RightButton) {
            if(!isRowSelected(row)) {
                if(modifiers & Qt.ShiftModifier) {
                    const base = anchorIndex >= 0 ? anchorIndex : (lastSelectedIndex >= 0 ? lastSelectedIndex : row)
                    selectRangeRows(base, row, (modifiers & Qt.ControlModifier) !== 0)
                }
                else if(modifiers & Qt.ControlModifier)
                    toggleRowSelection(row)
                else
                    selectSingleRow(row)
            }
            return
        }
        if(mouse.button !== Qt.LeftButton)
            return

        if(modifiers & Qt.ShiftModifier) {
            const base = anchorIndex >= 0 ? anchorIndex : (lastSelectedIndex >= 0 ? lastSelectedIndex : row)
            selectRangeRows(base, row, (modifiers & Qt.ControlModifier) !== 0)
        }
        else if(modifiers & Qt.ControlModifier)
            toggleRowSelection(row)
        else
            selectSingleRow(row)

        const point = clampTablePoint(item.mapToItem(tableView, mouse.x, mouse.y))
        dragStartX = dragCurrentX = point.x
        dragStartY = dragCurrentY = point.y
        dragStartRow = row
        dragModifiers = modifiers
        dragBaseRows = copySelectionMap(selectedRows)
        dragSelectMoved = false
        dragSelecting = false
    }
    function handleSelectionAreaPressed(item, mouse) {
        if(!enableSelection) {
            mouse.accepted = false
            return
        }
        forceActiveFocus()
        if(!isPointOnTableRow(mouse.y)) {
            if(mouse.button !== Qt.LeftButton)
                return
            const point = clampTablePoint(item.mapToItem(tableView, mouse.x, mouse.y))
            if(!(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)))
                clearSelection()
            dragStartX = dragCurrentX = point.x
            dragStartY = dragCurrentY = point.y
            dragStartRow = rowAtTableY(mouse.y)
            dragModifiers = mouse.modifiers || 0
            dragBaseRows = copySelectionMap(selectedRows)
            dragSelectMoved = false
            dragSelecting = false
            return
        }
        handleSelectionPressed(rowAtTableY(mouse.y), item, mouse)
    }
    function handleSelectionAreaMoved(item, mouse) {
        if(!enableSelection || dragStartRow < 0)
            return
        handleSelectionMoved(item, mouse)
    }
    function handleSelectionAreaClicked(mouse) {
        if(!enableSelection || !isPointOnTableRow(mouse.y))
            return
        handleSelectionClicked(rowAtTableY(mouse.y), mouse)
    }
    function handleSelectionAreaDoubleClicked(mouse) {
        if(!enableSelection || !isPointOnTableRow(mouse.y))
            return
        handleSelectionDoubleClicked(rowAtTableY(mouse.y), mouse)
    }
    function handleSelectionMoved(item, mouse) {
        if(!enableSelection || dragStartRow < 0)
            return
        const point = clampTablePoint(item.mapToItem(tableView, mouse.x, mouse.y))
        dragCurrentX = point.x
        dragCurrentY = point.y
        if(!dragSelectMoved) {
            const dx = dragCurrentX - dragStartX
            const dy = dragCurrentY - dragStartY
            dragSelectMoved = Math.sqrt(dx * dx + dy * dy) > 4
        }
        if(dragSelectMoved) {
            dragSelecting = true
            selectDragRectRows(dragStartY, dragCurrentY)
        }
    }
    function handleSelectionReleased() {
        dragSelecting = false
        dragSelectMoved = false
        dragStartRow = -1
    }
    function handleSelectionClicked(row, mouse) {
        if(!enableSelection || row < 0 || row >= rowCount)
            return
        if(mouse.button === Qt.RightButton)
            copySelectedImages()
    }
    function handleSelectionDoubleClicked(row, mouse) {
        if(!enableSelection || row < 0 || row >= rowCount)
            return
        if(mouse.button === Qt.LeftButton)
            activateRow(row)
    }

    // 宽度更新
    Timer {
        id: updateWidthTimer
        interval: 100
        repeat: false
        onTriggered: {
            updateWidth(true)
        }
    }
    // 更新全部宽度
    function updateWidth(timer=false) {
        if(!timer) { // 启动计时器，减少调用频率
            updateWidthTimer.restart()
            return
        }
        let ws = Array(columnCount).fill(1)
        // 表头
        for(let i = 1; i < columnCount; i++) {
            let maxWidth = headerRepeater.itemAt(i).maxWidth + fTableRoot.spacing*2
            if(maxWidth > ws[i]) ws[i] = maxWidth
        }
        // 表体
        for(let y in tableView.items) {
            const repeater = tableView.items[y].repeater
            for(let x = 1; x < columnCount; x++) {
                let maxWidth = repeater.itemAt(x).maxWidth + fTableRoot.spacing*2
                if(maxWidth > ws[x]) ws[x] = maxWidth
            }
        }
        // 赋值 / 计算第0列宽度
        let w0 = tableArea.width
        for(let i = 1; i < columnCount; i++) {
            const userWidth = headerModel.get(i).userWidth
            const autoWidth = Math.min(Math.max(getColumnMinWidth(i), ws[i]), getColumnMaxAutoWidth(i))
            const width = userWidth > 0 ? userWidth : autoWidth
            headerModel.setProperty(i, "width", width)
            w0 -= width
        }
        // 更新第0列宽度
        updateWidth0(w0)
    }
    // 更新第0列宽度
    function updateWidth0(w0 = -1) {
        if(headerModel.count <= 0) return
        if(w0 < 0) {
            w0 = tableArea.width
            for(let i = 1; i < columnCount; i++)
                w0 -= headerModel.get(i).width
        }
        w0 += columnCount-10 // 避让右侧滚动条空间
        if(w0 < getColumnMinWidth(0)) w0 = getColumnMinWidth(0)
        headerModel.setProperty(0, "width", w0)
    }

    // ========================= 【布局】 =========================

    // 表格区域
    Rectangle {
        id: tableArea
        anchors.fill: parent
        color: theme.bgColor

        Item {
            id: tableContainer
            anchors.fill: parent

            // 上方操控版
            Item {
                id: tableTopPanel
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: (showOpenButton || showClearButton) ? size_.line * 2 : 0

                // 左打开图片按钮
                IconTextButton {
                    id: openBtn
                    visible: showOpenButton && parent.width > openBtn.width + (showClearButton ? clearBtn.width : 0) // 容器宽度过小时隐藏
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: size_.smallSpacing * 0.5
                    icon_: "folder"
                    text_: openBtnText

                    onClicked: {
                        if(isLock) return
                        fileDialog.open()
                    }
                }

                // 右清空按钮
                IconTextButton {
                    id: clearBtn
                    visible: showClearButton
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: size_.smallSpacing * 0.5
                    icon_: "clear"
                    text_: clearBtnText

                    onClicked: {
                        if(isLock) return
                        fTableRoot.clear()
                    }
                }
            }

            // 提示
            DefaultTips {
                visibleFlag: fTableRoot.rowCount
                anchors.top: tableTopPanel.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                tips: defaultTips
            }

            // 表头
            Item {
                id: tableHeaderContainer
                visible: fTableRoot.rowCount > 0
                anchors.top: tableTopPanel.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: size_.line * 1.5
                onWidthChanged: updateWidth()

                Row {
                    anchors.fill: parent
                    spacing: -1
                    Repeater {
                        model: headerModel
                        id: headerRepeater
                        Rectangle {
                            width: model.width
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            color: theme.bgColor
                            border.width: 1
                            border.color: theme.coverColor2
                            clip: true
                            property real maxWidth: hText.implicitWidth
                            property int columnIndex: index
                            Text_ {
                                id: hText
                                anchors.fill: parent
                                anchors.leftMargin: fTableRoot.spacing * 0.5
                                anchors.rightMargin: fTableRoot.spacing * 0.5
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter // 垂直居中
                                font.pixelSize: size_.smallText
                                elide: fTableRoot.autoElide ? Text.ElideRight : Text.ElideNone
                                text: model.title
                            }
                            MouseArea {
                                id: headerHoverArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                            ToolTip_ {
                                visible: fTableRoot.showCellToolTip && headerHoverArea.containsMouse && hText.truncated
                                text: model.title
                            }
                            MouseArea {
                                visible: fTableRoot.enableColumnResize && columnIndex < columnCount - 1
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                width: Math.max(4, size_.smallSpacing)
                                hoverEnabled: true
                                cursorShape: Qt.SplitHCursor
                                property real pressX: 0
                                property real leftStartWidth: 0
                                property real rightStartWidth: 0
                                onPressed: {
                                    const point = mapToItem(tableArea, mouse.x, mouse.y)
                                    pressX = point.x
                                    leftStartWidth = headerModel.get(columnIndex).width
                                    rightStartWidth = headerModel.get(columnIndex + 1).width
                                }
                                onPositionChanged: {
                                    if(!pressed)
                                        return
                                    const point = mapToItem(tableArea, mouse.x, mouse.y)
                                    resizeColumnPair(columnIndex, point.x - pressX, leftStartWidth, rightStartWidth)
                                }
                                onDoubleClicked: {
                                    resetColumnUserWidth(columnIndex)
                                    resetColumnUserWidth(columnIndex + 1)
                                }
                            }
                        }
                    }
                }
            }
            // 表体
            TableView {
                id: tableView
                anchors.top: tableHeaderContainer.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                flickableDirection: Flickable.VerticalFlick // 只允许垂直滚动
                boundsBehavior: Flickable.StopAtBounds // 禁止flick过冲。不影响滚轮滚动的过冲
                model: dataModel
                clip: true
                property var items: tableView.children[0].children
                rowSpacing: -1
                delegate: Item {
                    Component.onCompleted: updateWidth()
                    TableView.onReused: updateWidth()
                    implicitHeight: size_.smallLine * 1.5
                    implicitWidth: 1
                    property int rowIndex: index
                    property var rowModel: model
                    property alias repeater: repeater
                    Row {
                        anchors.fill: parent
                        spacing: -1
                        Repeater {
                            id: repeater
                            model: headerModel
                            Rectangle {
                                width: model.width
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                color: enableSelection && isRowSelected(rowIndex) ? theme.coverColor2 : theme.bgColor
                                border.width: 1
                                border.color: theme.coverColor2
                                property real maxWidth: hText.implicitWidth
                                property int columnIndex: index
                                property string columnKey: model.key
                                property var header: headers[columnIndex]
                                property string displayText: getCellText(rowModel, header)
                                property string toolTipText: getCellToolTipText(rowModel, header, displayText)
                                clip: true
                                Button_ {
                                    visible: header.btn?true:false
                                    anchors.fill: parent
                                    radius: 0
                                    onClicked: {
                                        if(header.onClicked) {
                                            header.onClicked(rowIndex)
                                        }
                                    }
                                }
                                Text_ {
                                    id: hText
                                    property bool isLeft: headers[columnIndex].left?true:false
                                    anchors.fill: parent
                                    anchors.leftMargin: fTableRoot.spacing * 0.5
                                    anchors.rightMargin: fTableRoot.spacing * 0.5
                                    horizontalAlignment: isLeft ? Text.AlignLeft : Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter // 垂直居中
                                    font.pixelSize: size_.smallText
                                    elide: fTableRoot.autoElide ? Text.ElideRight : Text.ElideNone
                                    color: (columnKey != "state"|| typeof rowModel.state != "string" || rowModel.state.length == 0) ? theme.subTextColor : 
                                        (rowModel.state.startsWith("×") ? theme.noColor : (rowModel.state.startsWith("√") ? theme.yesColor : theme.subTextColor))
                                    text: parent.displayText
                                }
                                MouseArea {
                                    id: cellHoverArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: enableSelection ? (Qt.LeftButton | Qt.RightButton) : Qt.NoButton
                                    onPressed: handleSelectionPressed(rowIndex, cellHoverArea, mouse)
                                    onPositionChanged: handleSelectionMoved(cellHoverArea, mouse)
                                    onReleased: handleSelectionReleased()
                                    onClicked: handleSelectionClicked(rowIndex, mouse)
                                    onDoubleClicked: handleSelectionDoubleClicked(rowIndex, mouse)
                                }
                                ToolTip_ {
                                    visible: fTableRoot.showCellToolTip && cellHoverArea.containsMouse && hText.truncated
                                    text: toolTipText
                                }
                            }
                        }
                    }
                }
                // 滚动条
                ScrollBar.vertical: ScrollBar { id: tableScrollBar }
            }
            MouseArea {
                id: tableSelectionArea
                anchors.top: tableView.top
                anchors.left: tableView.left
                anchors.right: tableView.right
                anchors.bottom: tableView.bottom
                anchors.rightMargin: tableScrollBar.visible ? tableScrollBar.width : 0
                z: 10
                acceptedButtons: enableSelection ? (Qt.LeftButton | Qt.RightButton) : Qt.NoButton
                preventStealing: true
                onPressed: handleSelectionAreaPressed(tableSelectionArea, mouse)
                onPositionChanged: handleSelectionAreaMoved(tableSelectionArea, mouse)
                onReleased: handleSelectionReleased()
                onClicked: handleSelectionAreaClicked(mouse)
                onDoubleClicked: handleSelectionAreaDoubleClicked(mouse)
            }
            Item {
                anchors.fill: tableView
                z: 20
                visible: enableSelection && dragSelecting
                Rectangle {
                    x: Math.min(dragStartX, dragCurrentX)
                    y: Math.min(dragStartY, dragCurrentY)
                    width: Math.abs(dragCurrentX - dragStartX)
                    height: Math.abs(dragCurrentY - dragStartY)
                    color: theme.coverColor2
                    opacity: 0.45
                    border.width: 1
                    border.color: theme.coverColor4
                }
            }
        }

        // 内圆角裁切
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: tableContainer.width
                height: tableContainer.height
                radius: size_.btnRadius
            }
        }
    }

    // 文件选择对话框
    // QT-5.15.2 会报错：“Model size of -225 is less than 0”，不影响使用。
    // QT-5.15.5 修复了这个Bug，但是PySide2尚未更新到这个版本号。只能先忍忍了
    // https://bugreports.qt.io/browse/QTBUG-92444
    FileDialog_ {
        id: fileDialog
        title: fileDialogTitle
        nameFilters: fileDialogNameFilters
        folder: shortcuts.pictures
        selectMultiple: true // 多选
        onAccepted: {
            addPaths(fileDialog.fileUrls_)
        }
    }
}
