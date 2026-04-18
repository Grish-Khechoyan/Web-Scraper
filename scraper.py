import requests
from bs4 import BeautifulSoup
from urllib.parse import parse_qs, unquote, urljoin, urlparse


_REDIRECT_QUERY_KEYS = ("u", "url", "q", "target", "dest", "redirect", "redirect_url")


def _extract_final_url(raw_url: str) -> str:
    """Unwrap common redirect-style URLs and return a clean http(s) target when possible."""
    current = raw_url.strip()
    for _ in range(2):
        parsed = urlparse(current)
        if parsed.scheme not in {"http", "https"}:
            return current

        params = parse_qs(parsed.query)
        next_url = None
        for key in _REDIRECT_QUERY_KEYS:
            values = params.get(key)
            if values and values[0]:
                next_url = unquote(values[0]).strip()
                break

        if not next_url:
            return current

        parsed_next = urlparse(next_url)
        if parsed_next.scheme not in {"http", "https"}:
            return current
        current = next_url

    return current


def scrape_website(url: str) -> dict:
    response = requests.get(url, timeout=12, headers={"User-Agent": "Mozilla/5.0"})
    response.raise_for_status()

    soup = BeautifulSoup(response.text, "html.parser")

    title = soup.title.string.strip() if soup.title and soup.title.string else "No title"

    description_tag = soup.find("meta", attrs={"name": "description"})
    description = (
        description_tag.get("content", "").strip() if description_tag else "No description"
    )

    headings = []
    for tag in soup.find_all(["h1", "h2", "h3"]):
        text = tag.get_text(" ", strip=True)
        if text:
            headings.append(text)

    links = []
    seen_links: set[str] = set()
    for link in soup.find_all("a", href=True):
        text = link.get_text(" ", strip=True) or "(no text)"
        absolute_href = urljoin(url, link["href"].strip())
        parsed_href = urlparse(absolute_href)
        if parsed_href.scheme not in {"http", "https"}:
            continue

        cleaned_href = _extract_final_url(absolute_href)
        if cleaned_href in seen_links:
            continue
        seen_links.add(cleaned_href)
        links.append({"text": text, "href": cleaned_href})

    images: list[str] = []
    seen: set[str] = set()
    for img in soup.find_all("img", src=True):
        src = (img.get("src") or "").strip()
        if not src:
            continue

        absolute_src = urljoin(url, src)
        parsed = urlparse(absolute_src)
        if parsed.scheme not in {"http", "https"}:
            continue

        if absolute_src in seen:
            continue
        seen.add(absolute_src)
        images.append(absolute_src)

    return {
        "url": url,
        "title": title,
        "description": description,
        "headings": headings[:20],
        "links": links[:30],
        "images": images[:12],
    }
