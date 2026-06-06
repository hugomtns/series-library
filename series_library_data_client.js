export async function loadCatalogData() {
  const response = await fetch("series_library_data.json", { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`Catalog request failed: ${response.status}`);
  }
  return response.json();
}

export async function loadSeriesDetails() {
  const response = await fetch("series_library_details.json", { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`Series detail request failed: ${response.status}`);
  }
  return response.json();
}

export async function loadSeriesState() {
  try {
    const response = await fetch("/api/series-state", { cache: "no-store" });
    if (!response.ok) return {};
    const payload = await response.json();
    return payload.series || {};
  } catch (error) {
    console.error(error);
    return {};
  }
}

export async function saveSeriesState(id, state) {
  const response = await fetch(`/api/series-state/${encodeURIComponent(id)}`, {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(state),
  });
  if (!response.ok) {
    const payload = await response.json().catch(() => ({}));
    throw new Error(payload.error || `Series state request failed: ${response.status}`);
  }
  const payload = await response.json();
  return payload.series;
}
