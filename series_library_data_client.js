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
