import csv
import json
import ipaddress
import socket
from io import BytesIO, StringIO
from urllib.parse import urlparse

from dotenv import load_dotenv
from flask import Flask, abort, jsonify, request, send_file
from openpyxl import Workbook
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas

load_dotenv()

from db import get_recent_results, get_scrape_result_by_id, init_db, save_scrape_result
from scraper import scrape_website


app = Flask(__name__, static_folder="public", static_url_path="")


def _build_csv_bytes(result: dict) -> bytes:
    output = StringIO()
    writer = csv.writer(output)
    writer.writerow(["id", "url", "title", "description", "created_at", "headings", "links", "images"])
    writer.writerow(
        [
            result.get("id", ""),
            result.get("url", ""),
            result.get("title", ""),
            result.get("description", ""),
            result.get("created_at", ""),
            json.dumps(result.get("headings", []), ensure_ascii=False),
            json.dumps(result.get("links", []), ensure_ascii=False),
            json.dumps(result.get("images", []), ensure_ascii=False),
        ]
    )
    return output.getvalue().encode("utf-8")


def _build_xlsx_bytes(result: dict) -> bytes:
    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "Scrape Result"
    sheet.append(["Field", "Value"])
    sheet.append(["id", result.get("id", "")])
    sheet.append(["url", result.get("url", "")])
    sheet.append(["title", result.get("title", "")])
    sheet.append(["description", result.get("description", "")])
    sheet.append(["created_at", str(result.get("created_at", ""))])
    sheet.append(["headings", json.dumps(result.get("headings", []), ensure_ascii=False)])
    sheet.append(["links", json.dumps(result.get("links", []), ensure_ascii=False)])
    sheet.append(["images", json.dumps(result.get("images", []), ensure_ascii=False)])

    stream = BytesIO()
    workbook.save(stream)
    stream.seek(0)
    return stream.read()


def _build_pdf_bytes(result: dict) -> bytes:
    stream = BytesIO()
    pdf = canvas.Canvas(stream, pagesize=letter)
    width, height = letter
    x = 40
    y = height - 40

    lines = [
        f"Scrape Result ID: {result.get('id', '')}",
        f"URL: {result.get('url', '')}",
        f"Title: {result.get('title', '')}",
        f"Description: {result.get('description', '')}",
        f"Created At: {result.get('created_at', '')}",
        "",
        "Headings:",
    ]
    lines.extend([f"- {item}" for item in result.get("headings", [])] or ["- None"])
    lines.append("")
    lines.append("Links:")
    lines.extend([f"- {item.get('text', '')}: {item.get('href', '')}" for item in result.get("links", [])] or ["- None"])
    lines.append("")
    lines.append("Images:")
    lines.extend([f"- {item}" for item in result.get("images", [])] or ["- None"])

    text_obj = pdf.beginText(x, y)
    text_obj.setFont("Helvetica", 10)
    max_chars = 105
    for line in lines:
        chunks = [line[i : i + max_chars] for i in range(0, len(line), max_chars)] or [""]
        for chunk in chunks:
            if text_obj.getY() < 40:
                pdf.drawText(text_obj)
                pdf.showPage()
                text_obj = pdf.beginText(x, height - 40)
                text_obj.setFont("Helvetica", 10)
            text_obj.textLine(chunk)

    pdf.drawText(text_obj)
    pdf.save()
    stream.seek(0)
    return stream.read()


def _is_valid_url(value: str) -> bool:
    try:
        parsed = urlparse(value)
        return parsed.scheme in {"http", "https"} and bool(parsed.netloc)
    except Exception:
        return False


def _is_private_or_local_host(hostname: str) -> bool:
    host = (hostname or "").strip().lower()
    if not host:
        return True
    if host in {"localhost", "127.0.0.1", "::1"}:
        return True

    try:
        ip = ipaddress.ip_address(host)
        return (
            ip.is_private
            or ip.is_loopback
            or ip.is_link_local
            or ip.is_multicast
            or ip.is_reserved
        )
    except ValueError:
        pass

    try:
        addr_infos = socket.getaddrinfo(host, None)
    except socket.gaierror:
        return True

    for info in addr_infos:
        resolved_ip = info[4][0]
        try:
            ip = ipaddress.ip_address(resolved_ip)
        except ValueError:
            return True
        if (
            ip.is_private
            or ip.is_loopback
            or ip.is_link_local
            or ip.is_multicast
            or ip.is_reserved
        ):
            return True

    return False


@app.get("/")
def index():
    return app.send_static_file("index.html")


@app.post("/api/scrape")
def scrape():
    payload = request.get_json(silent=True) or {}
    url = (payload.get("url") or "").strip()

    if not _is_valid_url(url):
        return jsonify({"error": "Please provide a valid http(s) URL."}), 400
    host = (urlparse(url).hostname or "").strip()
    if _is_private_or_local_host(host):
        return jsonify({"error": "Private, local, or unresolved hosts are not allowed."}), 400

    try:
        result = scrape_website(url)
        saved_id = save_scrape_result(result)
        result["id"] = saved_id
        return jsonify(result)
    except Exception:
        return jsonify({"error": "Failed to scrape URL."}), 500


@app.get("/api/history")
def history():
    limit_raw = request.args.get("limit", "20")
    try:
        limit = max(1, min(100, int(limit_raw)))
    except ValueError:
        limit = 20

    try:
        items = get_recent_results(limit=limit)
        return jsonify({"items": items})
    except Exception:
        return jsonify({"error": "Failed to load history."}), 500


@app.get("/api/export/<string:file_type>/<int:result_id>")
def export_result(file_type: str, result_id: int):
    item = get_scrape_result_by_id(result_id)
    if item is None:
        return jsonify({"error": "Result not found."}), 404

    safe_id = int(item.get("id", result_id))
    filename_base = f"scrape-result-{safe_id}"

    if file_type == "csv":
        data = _build_csv_bytes(item)
        return send_file(
            BytesIO(data),
            as_attachment=True,
            download_name=f"{filename_base}.csv",
            mimetype="text/csv",
        )

    if file_type == "xlsx":
        data = _build_xlsx_bytes(item)
        return send_file(
            BytesIO(data),
            as_attachment=True,
            download_name=f"{filename_base}.xlsx",
            mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )

    if file_type == "pdf":
        data = _build_pdf_bytes(item)
        return send_file(
            BytesIO(data),
            as_attachment=True,
            download_name=f"{filename_base}.pdf",
            mimetype="application/pdf",
        )

    return jsonify({"error": "Unsupported format. Use csv, pdf, or xlsx."}), 400


@app.get("/<path:path>")
def spa_fallback(path: str):
    if path.startswith("api/"):
        abort(404)

    # Keep real 404 behavior for missing static assets.
    if "." in path:
        abort(404)

    return app.send_static_file("index.html")


if __name__ == "__main__":
    init_db()
    app.run(debug=True, host="0.0.0.0", port=5000)
