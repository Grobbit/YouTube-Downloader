/* Drives the download form: one job at a time, poll for progress, show files. */

const form = document.getElementById("form");
const urlInput = document.getElementById("url");
const audioOnly = document.getElementById("audioOnly");
const customQuality = document.getElementById("customQuality");
const playlistBox = document.getElementById("playlist");
const submitBtn = document.getElementById("submit");
const errorBox = document.getElementById("error");

const progressBox = document.getElementById("progress");
const statusText = document.getElementById("statusText");
const percentText = document.getElementById("percentText");
const barFill = document.getElementById("barFill");
const detail = document.getElementById("detail");

const resultBox = document.getElementById("result");
const filesList = document.getElementById("files");
const zipLink = document.getElementById("zipLink");
const againBtn = document.getElementById("again");

let pollTimer = null;

/* ---------- quality handling ---------- */
function qualityValue() {
  const picked = form.querySelector('input[name="quality"]:checked');
  if (!picked) return "1080";
  if (picked.value !== "custom") return picked.value;
  const typed = customQuality.value.trim();
  return /^\d+$/.test(typed) ? typed : "";
}

form.querySelectorAll('input[name="quality"]').forEach((radio) => {
  radio.addEventListener("change", () => {
    const isCustom = radio.value === "custom" && radio.checked;
    customQuality.hidden = !isCustom;
    if (isCustom) customQuality.focus();
  });
});

audioOnly.addEventListener("change", () => {
  // Audio-only ignores quality, same as the script's -x branch.
  document
    .querySelectorAll('input[name="quality"]')
    .forEach((radio) => {
      radio.disabled = audioOnly.checked;
      radio.closest(".chip").style.opacity = audioOnly.checked ? "0.45" : "1";
    });
  customQuality.disabled = audioOnly.checked;
});

/* ---------- playlist detection (mirrors `*list=*` in the script) ---------- */
function looksLikePlaylist(value) {
  return /[?&]list=/.test(value);
}

function syncPlaylistNotice() {
  const hit = looksLikePlaylist(urlInput.value.trim());
  playlistBox.hidden = !hit;
}

urlInput.addEventListener("input", syncPlaylistNotice);
urlInput.addEventListener("paste", () => setTimeout(syncPlaylistNotice, 0));
urlInput.addEventListener("blur", syncPlaylistNotice);

/* ---------- feedback helpers ---------- */
function showError(message) {
  errorBox.textContent = message;
  errorBox.hidden = false;
}

function clearError() {
  errorBox.hidden = true;
  errorBox.textContent = "";
}

function resetView() {
  clearTimeout(pollTimer);
  progressBox.hidden = true;
  resultBox.hidden = true;
  submitBtn.disabled = false;
  submitBtn.textContent = "Download";
  barFill.style.width = "0%";
  percentText.textContent = "0%";
  detail.textContent = "";
  filesList.innerHTML = "";
  zipLink.hidden = true;
}

function setProgress(status, percent, item, itemTotal, line) {
  progressBox.hidden = false;
  const pct = Math.max(0, Math.min(100, Number(percent) || 0));
  barFill.style.width = `${pct}%`;
  percentText.textContent = `${Math.round(pct)}%`;

  if (item && itemTotal > 1) {
    statusText.textContent = `Downloading item ${item} of ${itemTotal}`;
  } else if (status === "queued") {
    statusText.textContent = "Queued…";
  } else {
    statusText.textContent = "Downloading…";
  }

  detail.textContent = line || "";
}

/* ---------- submit ---------- */
form.addEventListener("submit", async (event) => {
  event.preventDefault();
  clearError();
  resultBox.hidden = true;

  const url = urlInput.value.trim();
  if (!url) {
    showError("Paste a URL first.");
    urlInput.focus();
    return;
  }

  const quality = qualityValue();
  if (!audioOnly.checked && !quality) {
    showError("Type a max quality like 1440, or pick one of the buttons.");
    customQuality.focus();
    return;
  }

  const playlistPick = form.querySelector('input[name="playlist"]:checked');
  const payload = {
    url,
    quality: quality || "1080",
    audio_only: audioOnly.checked,
    playlist: playlistBox.hidden ? "single" : (playlistPick ? playlistPick.value : "single"),
  };

  submitBtn.disabled = true;
  submitBtn.textContent = "Starting…";
  setProgress("queued", 0, 0, 0, "Starting download…");

  try {
    const response = await fetch("/api/download", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(data.error || "Could not start that download.");
    }
    submitBtn.textContent = "Downloading…";
    poll(data.job_id);
  } catch (err) {
    resetView();
    showError(err.message);
  }
});

/* ---------- polling ---------- */
function poll(jobId) {
  const tick = async () => {
    try {
      const response = await fetch(`/api/jobs/${jobId}`);
      if (response.status === 404) {
        throw new Error("That download expired. Start it again.");
      }
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "Lost track of the download.");

      if (data.status === "error") {
        resetView();
        showError(data.error || "yt-dlp could not download that link.");
        return;
      }

      if (data.status === "done") {
        setProgress("done", 100, data.item, data.item_total, "");
        statusText.textContent = "Finishing up…";
        finish(jobId, data.files || []);
        return;
      }

      setProgress(data.status, data.percent, data.item, data.item_total, data.line);
      pollTimer = setTimeout(tick, 900);
    } catch (err) {
      resetView();
      showError(err.message);
    }
  };
  tick();
}

function finish(jobId, files) {
  clearTimeout(pollTimer);
  progressBox.hidden = true;
  submitBtn.disabled = false;
  submitBtn.textContent = "Download";
  resultBox.hidden = false;

  filesList.innerHTML = "";
  files.forEach((name, index) => {
    const li = document.createElement("li");
    const link = document.createElement("a");
    link.href = `/api/jobs/${jobId}/file/${index}`;
    link.setAttribute("download", "");

    const label = document.createElement("span");
    label.className = "name";
    label.textContent = name;

    const action = document.createElement("span");
    action.className = "get";
    action.textContent = "Save";

    link.append(label, action);
    li.append(link);
    filesList.append(li);
  });

  if (files.length > 1) {
    zipLink.href = `/api/jobs/${jobId}/zip`;
    zipLink.hidden = false;
  } else {
    zipLink.hidden = true;
  }

  resultBox.scrollIntoView({ behavior: "smooth", block: "nearest" });
}

/* ---------- "Grab another" ---------- */
againBtn.addEventListener("click", () => {
  resetView();
  clearError();
  urlInput.value = "";
  playlistBox.hidden = true;
  urlInput.focus();
});

/* First paint: make sure the notice matches anything restored in the field. */
syncPlaylistNotice();
