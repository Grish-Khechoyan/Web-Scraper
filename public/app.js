const form = document.getElementById("scrape-form");
const urlInput = document.getElementById("url-input");
const statusText = document.getElementById("status");
const resultSection = document.getElementById("result");

const resultUrl = document.getElementById("result-url");
const resultTitle = document.getElementById("result-title");
const resultDescription = document.getElementById("result-description");
const headingsList = document.getElementById("headings-list");
const linksList = document.getElementById("links-list");
const imagesGrid = document.getElementById("images-grid");
const downloadCsvBtn = document.getElementById("download-csv-btn");
const downloadPdfBtn = document.getElementById("download-pdf-btn");
const downloadXlsxBtn = document.getElementById("download-xlsx-btn");
const historyList = document.getElementById("history-list");
const refreshHistoryBtn = document.getElementById("refresh-history-btn");
let currentResultId = null;

function renderList(parent, items, renderItem) {
  parent.innerHTML = "";
  if (!items.length) {
    const li = document.createElement("li");
    li.textContent = "None";
    parent.appendChild(li);
    return;
  }

  items.forEach((item) => {
    const li = document.createElement("li");
    li.innerHTML = renderItem(item);
    parent.appendChild(li);
  });
}

function escapeHtml(text) {
  return String(text)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function renderImages(parent, images) {
  parent.innerHTML = "";
  if (!images.length) {
    parent.innerHTML = "<p class=\"images-empty\">None</p>";
    return;
  }

  images.forEach((src) => {
    const a = document.createElement("a");
    a.href = src;
    a.target = "_blank";
    a.rel = "noopener";
    a.className = "image-card";

    const img = document.createElement("img");
    img.src = src;
    img.alt = "Scraped image";
    img.loading = "lazy";

    a.appendChild(img);
    parent.appendChild(a);
  });
}

async function loadHistory() {
  try {
    const response = await fetch("/api/history?limit=15");
    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.error || "Failed to load history");
    }

    renderList(historyList, data.items || [], (item) => {
      const date = item.created_at ? new Date(item.created_at).toLocaleString() : "";
      return `
        <div><strong>${escapeHtml(item.title || "No title")}</strong></div>
        <div>${escapeHtml(item.url || "")}</div>
        <div class="history-date">${escapeHtml(date)}</div>
      `;
    });
  } catch (error) {
    historyList.innerHTML = `<li>${escapeHtml(error.message)}</li>`;
  }
}

function downloadCurrentResult(fileType) {
  if (!currentResultId) {
    statusText.textContent = "No result to download yet.";
    return;
  }

  window.location.href = `/api/export/${fileType}/${currentResultId}`;
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const url = urlInput.value.trim();

  statusText.textContent = "Scraping...";
  resultSection.classList.add("hidden");

  try {
    const response = await fetch("/api/scrape", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ url }),
    });

    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.error || "Unknown error");
    }

    resultUrl.textContent = data.url || "";
    resultTitle.textContent = data.title || "";
    resultDescription.textContent = data.description || "";
    currentResultId = data.id || null;

    renderList(headingsList, data.headings || [], (item) => escapeHtml(item));
    renderList(
      linksList,
      data.links || [],
      (item) =>
        `<a class="link-text" href="${escapeHtml(item.href)}" target="_blank" rel="noopener">${escapeHtml(item.text)}</a><div class="link-url">${escapeHtml(item.href)}</div>`
    );
    renderImages(imagesGrid, data.images || []);

    statusText.textContent = "Done";
    resultSection.classList.remove("hidden");
    loadHistory();
  } catch (error) {
    statusText.textContent = error.message;
  }
});

refreshHistoryBtn.addEventListener("click", loadHistory);
downloadCsvBtn.addEventListener("click", () => downloadCurrentResult("csv"));
downloadPdfBtn.addEventListener("click", () => downloadCurrentResult("pdf"));
downloadXlsxBtn.addEventListener("click", () => downloadCurrentResult("xlsx"));
loadHistory();
