import os
from urllib.parse import urlparse
from typing import Any

import psycopg2
from psycopg2.extras import Json, RealDictCursor

DATABASE_URL = os.getenv("DATABASE_URL", "").strip()
if not (
    DATABASE_URL.startswith("postgresql://") or DATABASE_URL.startswith("postgres://")
):
    raise RuntimeError(
        "DATABASE_URL must be a PostgreSQL URL, for example: "
        "postgresql://user:password@localhost:5432/webscraper"
    )


def get_connection():
    try:
        return psycopg2.connect(DATABASE_URL)
    except psycopg2.OperationalError as exc:
        parsed = urlparse(DATABASE_URL)
        host = parsed.hostname or "unknown-host"
        port = parsed.port or 5432
        user = parsed.username or "unknown-user"
        db_name = (parsed.path or "/").lstrip("/") or "unknown-db"
        raise RuntimeError(
            "PostgreSQL connection failed. Check DATABASE_URL credentials and database "
            f"access (user='{user}', host='{host}', port={port}, db='{db_name}')."
        ) from exc


def init_db() -> None:
    query = """
    CREATE TABLE IF NOT EXISTS scrape_results (
        id SERIAL PRIMARY KEY,
        url TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        headings JSONB NOT NULL DEFAULT '[]'::jsonb,
        links JSONB NOT NULL DEFAULT '[]'::jsonb,
        images JSONB NOT NULL DEFAULT '[]'::jsonb,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    """

    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(query)
            cur.execute(
                "ALTER TABLE scrape_results "
                "ADD COLUMN IF NOT EXISTS images JSONB NOT NULL DEFAULT '[]'::jsonb;"
            )


def save_scrape_result(result: dict[str, Any]) -> int:
    query = """
    INSERT INTO scrape_results (url, title, description, headings, links, images)
    VALUES (%s, %s, %s, %s, %s, %s)
    RETURNING id;
    """
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                query,
                (
                    result["url"],
                    result["title"],
                    result["description"],
                    Json(result.get("headings", [])),
                    Json(result.get("links", [])),
                    Json(result.get("images", [])),
                ),
            )
            row = cur.fetchone()
            return int(row[0])


def get_recent_results(limit: int = 20) -> list[dict[str, Any]]:
    query = """
    SELECT id, url, title, description, headings, links, images, created_at
    FROM scrape_results
    ORDER BY created_at DESC
    LIMIT %s;
    """
    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query, (limit,))
            rows = cur.fetchall()
            return [dict(row) for row in rows]


def get_scrape_result_by_id(result_id: int) -> dict[str, Any] | None:
    query = """
    SELECT id, url, title, description, headings, links, images, created_at
    FROM scrape_results
    WHERE id = %s;
    """
    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query, (result_id,))
            row = cur.fetchone()
            return dict(row) if row else None
