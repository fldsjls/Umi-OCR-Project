// ==============================================
// =============== 图片文字搜索 ==================
// ==============================================

import QtQuick 2.15
import QtQuick.Controls 2.15

import ".."
import "../BatchOCR"
import "../../Widgets"

TabPage {
    id: tabPage

    property int indexCount: 0
    property int resultCount: 0

    Component.onCompleted: {
        // 等待子表格完成初始化，避免首次加载时 headerKey 仍为空。
        Qt.callLater(searchNow)
    }

    function refreshStats() {
        const info = tabPage.callPy("stats")
        indexCount = info ? info.count : 0
        countText.text = qsTr("已索引 %1 张，当前 %2 条").arg(indexCount).arg(resultCount)
    }

    function searchNow() {
        const rows = tabPage.callPy("search", keywordField.text, 300)
        resultsTable.clear()
        if(!rows) {
            resultCount = 0
            refreshStats()
            return
        }
        for(let i = 0; i < rows.length; i++) {
            resultsTable.add(rows[i])
        }
        resultCount = rows.length
        refreshStats()
    }

    function path2name(path) {
        const parts = String(path).replace(/\\/g, "/").split("/")
        return parts[parts.length - 1]
    }

    function openResult(index) {
        const row = resultsTable.get(index)
        let data = undefined
        if(row.source) {
            try {
                data = JSON.parse(row.source)
            } catch(e) {
                console.warn("搜索结果OCR信息解析失败", e)
            }
        }
        previewImage.show(row.path, data, row.text)
    }

    Panel {
        anchors.fill: parent

        Item {
            id: searchBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: size_.spacing
            height: size_.line * 2

            TextField_ {
                id: keywordField
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: searchBtn.left
                anchors.rightMargin: size_.smallSpacing
                placeholderText: qsTr("关键词")
                Keys.onReturnPressed: searchNow()
            }

            IconTextButton {
                id: searchBtn
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: clearBtn.left
                anchors.rightMargin: size_.smallSpacing
                icon_: "search"
                text_: qsTr("搜索")
                onClicked: searchNow()
            }

            IconTextButton {
                id: clearBtn
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                icon_: "clear"
                text_: qsTr("清空")
                onClicked: {
                    keywordField.text = ""
                    searchNow()
                }
            }
        }

        Text_ {
            id: countText
            anchors.top: searchBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: size_.spacing
            anchors.rightMargin: size_.spacing
            height: size_.line
            verticalAlignment: Text.AlignVCenter
            color: theme.subTextColor
        }

        FilesTableView {
            id: resultsTable
            anchors.top: countText.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: size_.spacing
            anchors.topMargin: size_.smallSpacing
            showOpenButton: false
            showClearButton: false
            enableSelection: true
            clearBtnText: qsTr("清空")
            defaultTips: qsTr("暂无结果")
            headers: [
                {key: "path", title: qsTr("图片"), left: true, display: path2name,
                    btn: true, onClicked: openResult},
                {key: "snippet", title: qsTr("匹配文字"), left: true, toolTipKey: "text"},
                {key: "score", title: qsTr("置信度"), display: function(v){ return Number(v).toFixed(2) }},
                {key: "indexedAt", title: qsTr("识别时间")},
            ]
        }
    }

    PreviewImage {
        id: previewImage
        anchors.fill: parent
    }
}
