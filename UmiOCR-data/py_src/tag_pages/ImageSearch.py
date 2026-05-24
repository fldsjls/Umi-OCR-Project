# ========================================
# =============== Image Search Page ======
# ========================================

from .page import Page
from ..utils.ocr_index import OcrIndex


class ImageSearch(Page):
    def search(self, keyword="", limit=200):
        return OcrIndex.search(keyword, limit)

    def stats(self):
        return OcrIndex.stats()
