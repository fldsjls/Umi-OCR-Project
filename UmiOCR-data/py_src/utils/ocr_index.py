# Local OCR text index for image search.

import json
import os
import re
import sqlite3
import time

from umi_log import logger


class OcrIndexClass:
    def __init__(self):
        self.db_path = os.path.abspath("ocr_index.sqlite")

    def _connect(self):
        conn = sqlite3.connect(self.db_path, timeout=10)
        conn.row_factory = sqlite3.Row
        self._ensure_schema(conn)
        return conn

    def _ensure_schema(self, conn):
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS ocr_images (
                path TEXT PRIMARY KEY,
                file_name TEXT NOT NULL,
                dir TEXT NOT NULL,
                text TEXT NOT NULL,
                result_json TEXT NOT NULL,
                score REAL NOT NULL DEFAULT 0,
                image_mtime REAL NOT NULL DEFAULT 0,
                indexed_at REAL NOT NULL
            )
            """
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_ocr_images_indexed_at "
            "ON ocr_images(indexed_at)"
        )
        conn.commit()

    def _get_data_text(self, data):
        if not isinstance(data, list):
            return ""
        text = ""
        last_index = len(data) - 1
        for index, block in enumerate(data):
            if not isinstance(block, dict):
                continue
            text += str(block.get("text", ""))
            if index < last_index:
                text += str(block.get("end", ""))
        return text

    def index_result(self, res):
        path = res.get("path", "")
        if not path:
            return False
        path = os.path.abspath(path)

        code = res.get("code")
        if code == 101:
            self.delete(path)
            return False
        if code != 100:
            return False

        text = self._get_data_text(res.get("data")).strip()
        if not text:
            self.delete(path)
            return False

        file_name = res.get("fileName") or os.path.basename(path)
        dir_path = res.get("dir") or os.path.dirname(path)
        score = float(res.get("score") or 0)
        image_mtime = os.path.getmtime(path) if os.path.exists(path) else 0
        indexed_at = time.time()

        res_copy = dict(res)
        res_copy["path"] = path
        res_copy["fileName"] = file_name
        res_copy["dir"] = dir_path
        result_json = json.dumps(res_copy, ensure_ascii=False, default=str)

        try:
            with self._connect() as conn:
                conn.execute(
                    """
                    INSERT INTO ocr_images (
                        path, file_name, dir, text, result_json,
                        score, image_mtime, indexed_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(path) DO UPDATE SET
                        file_name = excluded.file_name,
                        dir = excluded.dir,
                        text = excluded.text,
                        result_json = excluded.result_json,
                        score = excluded.score,
                        image_mtime = excluded.image_mtime,
                        indexed_at = excluded.indexed_at
                    """,
                    (
                        path,
                        file_name,
                        dir_path,
                        text,
                        result_json,
                        score,
                        image_mtime,
                        indexed_at,
                    ),
                )
            return True
        except Exception:
            logger.error("Failed to write OCR search index.", exc_info=True)
            return False

    def delete(self, path):
        try:
            with self._connect() as conn:
                conn.execute(
                    "DELETE FROM ocr_images WHERE path = ?", (os.path.abspath(path),)
                )
        except Exception:
            logger.error("Failed to delete OCR search index item.", exc_info=True)

    def delete_many(self, paths):
        if hasattr(paths, "toVariant"):
            paths = paths.toVariant()
        if not isinstance(paths, (list, tuple)):
            paths = [paths]
        normalized = [os.path.abspath(path) for path in paths if path]
        if not normalized:
            return {"ok": False, "deleted": 0, "message": "[Error] no record path."}
        try:
            with self._connect() as conn:
                before = conn.total_changes
                conn.executemany(
                    "DELETE FROM ocr_images WHERE path = ?",
                    [(path,) for path in normalized],
                )
                deleted = conn.total_changes - before
            return {"ok": True, "deleted": deleted}
        except Exception:
            logger.error("Failed to delete OCR search index items.", exc_info=True)
            return {"ok": False, "deleted": 0, "message": "[Error] failed to delete index records."}

    def search(self, keyword="", limit=200):
        keyword = (keyword or "").strip()
        limit = max(1, min(int(limit or 200), 1000))
        terms = [x for x in re.split(r"\s+", keyword) if x]

        sql = "SELECT * FROM ocr_images"
        params = []
        if terms:
            clauses = []
            for term in terms:
                pattern = f"%{self._escape_like(term)}%"
                clauses.append(
                    "(text LIKE ? ESCAPE '\\' OR file_name LIKE ? ESCAPE '\\' "
                    "OR path LIKE ? ESCAPE '\\')"
                )
                params.extend([pattern, pattern, pattern])
            sql += " WHERE " + " AND ".join(clauses)
        sql += " ORDER BY indexed_at DESC LIMIT ?"
        params.append(limit)

        try:
            with self._connect() as conn:
                rows = conn.execute(sql, params).fetchall()
        except Exception:
            logger.error("Failed to search OCR index.", exc_info=True)
            return []

        return [self._row_to_dict(row, terms) for row in rows]

    def stats(self):
        try:
            with self._connect() as conn:
                row = conn.execute("SELECT COUNT(*) AS count FROM ocr_images").fetchone()
            return {"count": int(row["count"]), "dbPath": self.db_path}
        except Exception:
            logger.error("Failed to read OCR index stats.", exc_info=True)
            return {"count": 0, "dbPath": self.db_path}

    def _row_to_dict(self, row, terms):
        text = row["text"]
        indexed_at = float(row["indexed_at"] or 0)
        return {
            "path": row["path"],
            "name": row["file_name"],
            "dir": row["dir"],
            "text": text,
            "snippet": self._make_snippet(text, terms),
            "score": float(row["score"] or 0),
            "indexedAt": time.strftime(
                "%Y-%m-%d %H:%M:%S", time.localtime(indexed_at)
            ),
            "source": row["result_json"],
            "exists": os.path.exists(row["path"]),
        }

    def _make_snippet(self, text, terms, radius=36):
        compact = re.sub(r"\s+", " ", text).strip()
        if not compact:
            return ""
        lower = compact.lower()
        start = 0
        for term in terms:
            index = lower.find(term.lower())
            if index >= 0:
                start = max(0, index - radius)
                break
        end = min(len(compact), start + radius * 2 + 20)
        snippet = compact[start:end]
        if start > 0:
            snippet = "..." + snippet
        if end < len(compact):
            snippet += "..."
        return snippet

    def _escape_like(self, text):
        return text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


OcrIndex = OcrIndexClass()
