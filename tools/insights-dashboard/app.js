const KEYS = {
  url: "jojo.insights.supabaseUrl",
  anon: "jojo.insights.anonKey",
  token: "jojo.insights.adminToken",
};

const $ = (id) => document.getElementById(id);

function loadConfig() {
  $("supabaseUrl").value = localStorage.getItem(KEYS.url) || "https://jacpmygzmsfiyltdsiyu.supabase.co";
  $("anonKey").value = localStorage.getItem(KEYS.anon) || "";
  $("adminToken").value = localStorage.getItem(KEYS.token) || "";
}

function saveConfig() {
  localStorage.setItem(KEYS.url, $("supabaseUrl").value.trim().replace(/\/$/, ""));
  localStorage.setItem(KEYS.anon, $("anonKey").value.trim());
  localStorage.setItem(KEYS.token, $("adminToken").value.trim());
}

async function api(path, options = {}) {
  const base = localStorage.getItem(KEYS.url);
  const anon = localStorage.getItem(KEYS.anon);
  const token = localStorage.getItem(KEYS.token);
  if (!base || !anon || !token) throw new Error("Save Supabase URL, anon key, and ADMIN_TOKEN first.");
  const res = await fetch(`${base}/functions/v1/admin-insights${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      apikey: anon,
      Authorization: `Bearer ${anon}`,
      "x-admin-token": token,
      ...(options.headers || {}),
    },
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(json.error || `HTTP ${res.status}`);
  return json;
}

function renderSources(bySource) {
  const entries = Object.entries(bySource || {}).sort((a, b) => b[1] - a[1]);
  const max = Math.max(1, ...entries.map(([, n]) => n));
  $("sources").innerHTML = entries.length
    ? entries
        .map(
          ([source, n]) => `
      <div class="bar-row">
        <span>${source.replaceAll("_", " ")}</span>
        <div class="bar-track"><div class="bar-fill" style="width:${(n / max) * 100}%"></div></div>
        <span>${n}</span>
      </div>`
        )
        .join("")
    : `<p class="hint">No acquisition answers yet.</p>`;
}

function renderFeedback(items) {
  $("feedbackList").innerHTML = items.length
    ? items
        .map((item) => {
          const enjoyed =
            item.enjoyed === true
              ? `<span class="pill yes">Yes</span>`
              : item.enjoyed === false
                ? `<span class="pill no">No</span>`
                : `<span class="pill">—</span>`;
          const cat = item.category
            ? `<span class="pill">${item.category}</span>`
            : "";
          return `
      <article class="item" data-id="${item.id}">
        <div class="item-top">
          <div>${enjoyed}${cat}<span class="pill">${item.status}</span></div>
          <span class="meta">${new Date(item.created_at).toLocaleString()}</span>
        </div>
        <p>${escapeHtml(item.message || "")}</p>
        <p class="meta">${escapeHtml(item.app_user_id || "")}</p>
        <div class="actions">
          <button type="button" data-status="reviewed">Mark reviewed</button>
          <button type="button" data-status="done">Mark done</button>
          <button type="button" data-status="new">Mark new</button>
        </div>
      </article>`;
        })
        .join("")
    : `<p class="hint">No feedback yet.</p>`;

  $("feedbackList").querySelectorAll("button[data-status]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const id = Number(btn.closest(".item").dataset.id);
      const status = btn.dataset.status;
      try {
        await api("", {
          method: "PATCH",
          body: JSON.stringify({ id, status }),
        });
        await refresh();
      } catch (e) {
        showError(e.message);
      }
    });
  });
}

function escapeHtml(s) {
  return String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function showError(msg) {
  const el = $("error");
  el.hidden = !msg;
  el.textContent = msg || "";
}

async function refresh() {
  showError("");
  try {
    const status = $("statusFilter").value;
    const qs = status ? `?status=${encodeURIComponent(status)}` : "";
    const data = await api(qs);
    $("stats").hidden = false;
    $("sourcesCard").hidden = false;
    $("feedbackCard").hidden = false;
    $("acqTotal").textContent = data.acquisition?.total ?? 0;
    $("fbTotal").textContent = data.feedback?.total ?? 0;
    $("enjoyYes").textContent = data.feedback?.enjoyed_yes ?? 0;
    $("enjoyNo").textContent = data.feedback?.enjoyed_no ?? 0;
    renderSources(data.acquisition?.by_source || {});
    renderFeedback(data.feedback?.items || []);
  } catch (e) {
    showError(e.message);
  }
}

$("saveConfig").addEventListener("click", () => {
  saveConfig();
  refresh();
});
$("refresh").addEventListener("click", refresh);
$("statusFilter").addEventListener("change", refresh);

loadConfig();
if (localStorage.getItem(KEYS.token)) refresh();
