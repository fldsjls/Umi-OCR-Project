# ==========================================================
# =============== Python向Qml传输 Pixmap 图像 ===============
# ==========================================================

import os
import struct
import ctypes
from ctypes import wintypes
from uuid import uuid4  # 唯一ID
from urllib.parse import unquote
from PySide2.QtCore import Qt, QByteArray, QBuffer, QUrl, QMimeData, QFile
from PySide2.QtGui import QPixmap, QImage, QPainter, QClipboard
from PySide2.QtQml import QJSValue
from PySide2.QtQuick import QQuickImageProvider

from umi_log import logger
from . import ImageQt
from ..platform import Platform

Clipboard = QClipboard()  # 剪贴板


# Pixmap型图片提供器
class PixmapProviderClass(QQuickImageProvider):
    def __init__(self):
        super().__init__(QQuickImageProvider.Pixmap)
        self.pixmapDict = {}  # 缓存所有pixmap的字典
        self.compDict = {}  # 缓存所有组件的字典
        # 空图占位符
        self._noneImg = None

    # 向qml返回图片，imgID不存在时返回警告图
    def requestPixmap(self, path, size=None, resSize=None):
        if "/" in path:
            compID, imgID = path.split("/", 1)
            self._delCompCache(compID, imgID)  # 先清缓存
            if imgID in self.pixmapDict:
                self.compDict[compID] = imgID  # 记录缓存
                return self.pixmapDict[imgID]
        else:  # 清空一个组件的缓存
            self._delCompCache(path)
        return self._getNoneImg()  # 返回占位符

    # 添加一个Pixmap图片到提供器，返回imgID
    def addPixmap(self, pixmap):
        imgID = str(uuid4())
        self.pixmapDict[imgID] = pixmap
        return imgID

    # 向py返回图片，相当于requestPixmap，但imgID不存在时返回None
    def getPixmap(self, imgID):
        return self.pixmapDict.get(imgID, None)

    # 向py返回PIL对象
    def getPilImage(self, imgID):
        im = self.getPixmap(imgID)
        if not im:
            return None
        try:
            return ImageQt.fromqimage(im)
        except Exception:
            logger.error("QPixmap 转 PIL 失败。", exc_info=True, stack_info=True)
            return None

    # py将PIL对象写回pixmapDict。主要是记录预处理的图像
    # imgID可以已存在，也可以新添加
    def setPilImage(self, img, imgID=""):
        try:
            pixmap = ImageQt.toqpixmap(img)
        except Exception as e:
            logger.error("PIL 转 QPixmap 失败。", exc_info=True, stack_info=True)
            return f"[Error] PIL 转 QPixmap 失败：{e}"
        if not imgID:
            imgID = str(uuid4())
        self.pixmapDict[imgID] = pixmap
        return imgID

    # 从pixmapDict缓存中删除一个或一批图片
    # 一般无需手动调用此函数！缓存会自动管理、清除。
    def delPixmap(self, imgIDs):
        if isinstance(imgIDs, str):
            imgIDs = [imgIDs]
        for i in imgIDs:
            if i in self.pixmapDict:
                del self.pixmapDict[i]
        logger.debug(f"删除图片缓存，剩余：{len(self.pixmapDict)}")

    # 将 QPixmap 或 QImage 转换为字节
    @staticmethod
    def toBytes(image):
        if isinstance(image, QPixmap):
            image = image.toImage()
        elif not isinstance(image, QImage):
            raise ValueError(
                f"[Error] Only QImage or QPixmap can toBytes(), no {str(type(image))}."
            )
        byteArray = QByteArray()  # 创建一个字节数组
        buffer = QBuffer(byteArray)  # 创建一个缓冲区
        buffer.open(QBuffer.WriteOnly)
        image.save(buffer, "PNG")  # 将 QImage 保存为字节数组
        buffer.close()
        bytesData = byteArray.data()  # 获取字节数组的内容
        return bytesData

    # 清空一个组件的缓存。imgID可选该组件下一次更新的图片ID。
    def _delCompCache(self, compID, imgID=""):
        if compID in self.compDict:
            last = self.compDict[compID]
            if imgID and imgID == last:
                logger.warning(f"图片组件异常清理： {compID} {imgID}")
                return  # 如果下一次更新的ID等于当前ID，则为异常，不进行清理
            if last in self.pixmapDict:
                del self.pixmapDict[last]
            del self.compDict[compID]

    # 返回空图占位符
    def _getNoneImg(self):
        if self._noneImg:
            return self._noneImg
        pixmap = QPixmap(1, 100)
        pixmap.fill(Qt.blue)
        painter = QPainter(pixmap)  # 绘制警告条纹
        painter.setPen(Qt.red)
        painter.drawLine(0, 0, 0, 5)
        painter.drawLine(0, 95, 0, 100)
        self._noneImg = pixmap
        return self._noneImg


# 图片提供器 单例
PixmapProvider = PixmapProviderClass()


# 读入一张图片，返回该图片
# type: pixmap / qimage / error
def _imread(path):
    path = unquote(path)  # 做一次URL解码
    if path.startswith("image://pixmapprovider/"):
        path = path[23:]
        if "/" in path:
            compID, imgID = path.split("/", 1)
            if imgID in PixmapProvider.pixmapDict:
                return {"type": "pixmap", "data": PixmapProvider.pixmapDict[imgID]}
        else:
            return {"type": "error", "data": f"[Warning] ID not in pixmapDict: {path}"}
    elif path.startswith("file:///"):
        path = path[8:]
        if os.path.exists(path):
            try:
                image = QImage(path)
                return {"type": "qimage", "data": image, "path": path}
            except Exception as e:
                return {
                    "type": "error",
                    "data": f"[Error] QImage cannot read path: {path}",
                }
        else:
            return {"type": "error", "data": f"[Warning] Path {path} not exists."}
    elif path in PixmapProvider.pixmapDict:
        return {"type": "pixmap", "data": PixmapProvider.pixmapDict[path]}
    elif os.path.exists(path):
        try:
            image = QImage(path)
            return {"type": "qimage", "data": image, "path": path}
        except Exception as e:
            return {"type": "error", "data": f"[Error] QImage cannot read path: {path}"}
    return {"type": "error", "data": f"[Warning] Unknow: {path}"}


# 复制一张图片到剪贴板
def copyImage(path):
    im = _imread(path)
    typ, data = im["type"], im["data"]
    if typ == "error":
        return data
    try:
        if typ == "pixmap":
            Clipboard.setPixmap(data)
        elif typ == "qimage":
            Clipboard.setImage(data)
        return "[Success]"
    except Exception as e:
        return f"[Error] can't copy: {e}\n{path}"


def _toLocalPaths(paths):
    if isinstance(paths, QJSValue):
        paths = paths.toVariant()
    if isinstance(paths, str):
        paths = [paths]
    elif not isinstance(paths, (list, tuple)):
        try:
            paths = list(paths)
        except TypeError:
            paths = [paths]
    paths = [p.toVariant() if isinstance(p, QJSValue) else p for p in paths if p]
    local_paths = []
    for p in paths:
        if isinstance(p, QUrl) and p.isLocalFile():
            path = p.toLocalFile()
        else:
            path = unquote(str(p))
        if path.startswith("file:///"):
            path = path[8:]
        if path:
            local_paths.append(os.path.abspath(path))
    return local_paths


def _copyFilesToClipboard(paths, isCut=False):
    paths = _toLocalPaths(paths)
    if len(paths) <= 0:
        return "[Error] no file path."

    urls = []
    valid_paths = []
    for path in paths:
        if os.path.exists(path):
            urls.append(QUrl.fromLocalFile(path))
            valid_paths.append(path)

    if len(urls) <= 0:
        return "[Error] no valid file path."

    try:
        mime_data = QMimeData()
        mime_data.setUrls(urls)
        mime_data.setText("\n".join(valid_paths))
        drop_effect = 2 if isCut else 1
        drop_data = QByteArray(struct.pack("<I", drop_effect))
        mime_data.setData("Preferred DropEffect", drop_data)
        mime_data.setData(
            'application/x-qt-windows-mime;value="Preferred DropEffect"',
            drop_data,
        )
        Clipboard.setMimeData(mime_data)
        return f"[Success] {len(urls)}"
    except Exception as e:
        return f"[Error] can't copy files: {e}"


def copyImages(paths):
    return _copyFilesToClipboard(paths, False)


def cutImages(paths):
    return _copyFilesToClipboard(paths, True)


def _moveToTrashWin(path):
    class SHFILEOPSTRUCTW(ctypes.Structure):
        _fields_ = [
            ("hwnd", wintypes.HWND),
            ("wFunc", wintypes.UINT),
            ("pFrom", wintypes.LPCWSTR),
            ("pTo", wintypes.LPCWSTR),
            ("fFlags", wintypes.WORD),
            ("fAnyOperationsAborted", wintypes.BOOL),
            ("hNameMappings", wintypes.LPVOID),
            ("lpszProgressTitle", wintypes.LPCWSTR),
        ]

    shell_file_operation = ctypes.windll.shell32.SHFileOperationW
    shell_file_operation.argtypes = [ctypes.POINTER(SHFILEOPSTRUCTW)]
    shell_file_operation.restype = ctypes.c_int

    op = SHFILEOPSTRUCTW()
    op.wFunc = 3  # FO_DELETE
    op.pFrom = path + "\0\0"
    op.fFlags = 0x0040 | 0x0010 | 0x0400  # FOF_ALLOWUNDO | NOCONFIRMATION | NOERRORUI
    res = ctypes.windll.shell32.SHFileOperationW(ctypes.byref(op))
    return res == 0 and not op.fAnyOperationsAborted


def _moveToTrash(path):
    if hasattr(QFile, "moveToTrash"):
        try:
            res = QFile.moveToTrash(path)
            ok = res[0] if isinstance(res, tuple) else res
            if ok:
                return True
        except Exception:
            logger.error(f"Failed to move file to trash by QFile: {path}", exc_info=True)
    if os.name == "nt":
        try:
            return _moveToTrashWin(path)
        except Exception:
            logger.error(f"Failed to move file to trash by shell: {path}", exc_info=True)
    return False


def deleteImages(paths):
    paths = _toLocalPaths(paths)
    if len(paths) <= 0:
        return {"ok": False, "deleted": [], "failed": [], "message": "[Error] no file path."}

    deleted = []
    failed = []
    for path in paths:
        if not os.path.exists(path):
            failed.append(path)
            continue
        ok = _moveToTrash(path)
        if ok:
            deleted.append(path)
        else:
            failed.append(path)

    ok = len(failed) == 0
    message = f"[Success] {len(deleted)}" if ok else (
        f"[Error] moved {len(deleted)} files to trash, failed {len(failed)}."
    )
    return {"ok": ok, "deleted": deleted, "failed": failed, "message": message}


# 用系统默认应用打开图片
def openImage(path):
    im = _imread(path)
    typ, data = im["type"], im["data"]
    if typ == "error":
        return data
    # 若原本为本地图片，则直接打开
    if "path" in im:
        path = im["path"]
    # 若为内存数据，则创建缓存文件
    else:
        path = "umi_temp_image.png"
        try:
            if typ == "pixmap":
                data = data.toImage()
            data.save(path)
            logger.debug(f"用系统默认应用打开图片时，缓存临时图片到 {path}")
        except Exception as e:
            logger.error(
                f"用系统默认应用打开图片时，无法缓存临时图片到 {path}",
                exc_info=True,
                stack_info=True,
            )
            return f"[Error] can't save to temp file: {e}\n{path}"
    # 打开文件
    try:
        Platform.startfile(path)
        return "[Success]"
    except Exception as e:
        logger.error(
            f"无法用系统默认应用打开图片 {path}",
            exc_info=True,
            stack_info=True,
        )
        return f"[Error] can't open image: {e}\n{path}"


# 保存一张图片
def saveImage(fromPath, toPath):
    if toPath.startswith("file:///"):
        toPath = toPath[8:]
    im = _imread(fromPath)
    typ, data = im["type"], im["data"]
    if typ == "error":
        return data
    try:
        if typ == "pixmap":
            data.save(toPath)
        elif typ == "qimage":
            data.save(toPath)
        return f"[Success] {toPath}"
    except Exception as e:
        return f"[Error] can't save: {e}\n{fromPath}\n{toPath}"
