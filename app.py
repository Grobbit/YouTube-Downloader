"""YouTube-Downloader, web edition.

A straight port of downloader.ps1. Same features, same yt-dlp arguments,
same quality / audio-only / playlist behaviour -- just driven from a browser
instead of a PowerShell prompt so it can live on Render.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import uuid
import zipfile

from flask import Flask, jsonify, render_template, request, send_file

app = Flask(
    __name__,
    template_folder=os.path.join("web", "templates"),
    static_folder=os.path.join("web", "static"),
)

# Where each job gets its own folder of finished files.
WORK_ROOT = os.environ.get("DOWNLOAD_DIR") or os.path.join(tempfile.gettempdir(), "ytdl-web")
os.makedirs(WORK_ROOT, exist_ok=True)

# How long a finished job stays around so it can still be downloaded.
JOB_TTL_SECONDS = int(os.environ.get("JOB_TTL_SECONDS", "7200"))

JOBS: dict[str, dict] = {}
JOBS_LOCK = threading.Lock()


# --------------------------------------------------------------------------
# Tool upkeep -- the script's "check for yt-dlp updates" step, run once at boot.
# FFmpeg comes from the container image (see Dockerfile).
# --------------------------------------------------------------------------
def _auto_update_ytdlp() -> None:
    if os.environ.get("YTDLP_AUTO_UPDATE", "1") != "1":
        return
    try:
        subprocess.run(
            [sys.executable, "-m", "pip", "install", "--upgrade", "--quiet", "yt-dlp"],
            check=False,
            timeout=180,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        print("[boot] yt-dlp update check finished", flush=True)
    except Exception as exc:  # pragma: no cover - best effort only
        print(f"[boot] yt-dlp update skipped: {exc}", flush=True)


threading.Thread(target=_auto_update_ytdlp, daemon=True).start()


def _tool_version() -> str:
    try:
        out = subprocess.run(
            [sys.executable, "-m", "yt_dlp", "--version"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        return out.stdout.strip() or "unknown"
    except Exception:
        return "unknown"


# --------------------------------------------------------------------------
# Job helpers
# --------------------------------------------------------------------------
def _build_command(url: str, quality: str, audio_only: bool, playlist: bool, folder: str) -> list[str]:
    """Mirror the PowerShell argument strings exactly."""
    cmd = [
        sys.executable,
        "-m",
        "yt_dlp",
        "--newline",
        "--no-color",
        "--yes-playlist" if playlist else "--no-playlist",
    ]

    if audio_only:
        cmd += ["-x", "--audio-format", "mp3"]
    else:
        # -f "" as in the original script, with the same fallback chain.
        fmt = (
            f"bestvideo[height<={quality}][ext=mp4]+bestaudio[ext=m4a]"
            "/best[ext=mp4]/best"
        )
        cmd += ["-f", fmt, "--merge-output-format", "mp4"]

    cmd += ["-o", os.path.join(folder, "%(title)s [%(id)s].%(ext)s"), url]
    return cmd


PERCENT_RE = re.compile(r"\[download\]\s+(\d+(?:\.\d+)?)%")
ITEM_RE = re.compile(r"\[download\]\s+Downloading item (\d+) of (\d+)")


def _run_job(job_id: str, cmd: list[str], folder: str) -> None:
    job = JOBS[job_id]
    job["status"] = "running"

    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            cwd=folder,
        )
        assert process.stdout is not None
        for raw in process.stdout:
            line = raw.rstrip()
            if not line:
                continue

            job["line"] = line
            job["log"].append(line)
            del job["log"][:-40]

            item = ITEM_RE.search(line)
            if item:
                job["item"], job["item_total"] = int(item.group(1)), int(item.group(2))

            match = PERCENT_RE.search(line)
            if match:
                job["percent"] = float(match.group(1))

        code = process.wait()
        files = sorted(
            os.path.join(folder, name)
            for name in os.listdir(folder)
            if os.path.isfile(os.path.join(folder, name))
        )
        job["files"] = files

        if code == 0 and files:
            job["status"] = "done"
            job["percent"] = 100.0
        elif code == 0:
            job["status"] = "error"
            job["error"] = "yt-dlp finished but produced no file."
        else:
            job["status"] = "error"
            tail = "\n".join(job["log"][-6:])
            job["error"] = tail or f"yt-dlp exited with code {code}."
    except Exception as exc:  # pragma: no cover
        job["status"] = "error"
        job["error"] = str(exc)
    finally:
        job["finished_at"] = time.time()


def _cleanup_loop() -> None:
    while True:
        time.sleep(300)
        cutoff = time.time() - JOB_TTL_SECONDS
        with JOBS_LOCK:
            expired = [jid for jid, j in JOBS.items() if j.get("finished_at", 0) and j["finished_at"] < cutoff]
            for jid in expired:
                job = JOBS.pop(jid)
                shutil.rmtree(job["folder"], ignore_errors=True)


threading.Thread(target=_cleanup_loop, daemon=True).start()


# --------------------------------------------------------------------------
# Routes
# --------------------------------------------------------------------------
@app.get("/")
def index():
    return render_template("index.html", ytdlp_version=_tool_version())


@app.post("/api/download")
def start_download():
    payload = request.get_json(silent=True) or {}
    url = (payload.get("url") or "").strip()
    quality = str(payload.get("quality") or "1080").strip()
    audio_only = bool(payload.get("audio_only"))
    playlist_mode = payload.get("playlist") or "single"

    if not url:
        return jsonify(error="Paste a URL first."), 400
    if not url.lower().startswith(("http://", "https://")):
        return jsonify(error="That does not look like a URL."), 400
    if not audio_only:
        if not quality.isdigit() or not (144 <= int(quality) <= 4320):
            return jsonify(error="Quality should be a number like 720, 1080 or 2160."), 400

    job_id = uuid.uuid4().hex
    folder = os.path.join(WORK_ROOT, job_id)
    os.makedirs(folder, exist_ok=True)

    # Original script: a link containing "list=" is a playlist; the user then
    # chooses all or just the one video.
    command = _build_command(
        url=url,
        quality=quality,
        audio_only=audio_only,
        playlist=playlist_mode == "all",
        folder=folder,
    )

    with JOBS_LOCK:
        JOBS[job_id] = {
            "status": "queued",
            "percent": 0.0,
            "item": 0,
            "item_total": 0,
            "line": "Starting download...",
            "log": [],
            "files": [],
            "folder": folder,
            "error": None,
            "finished_at": 0,
            "url": url,
        }

    threading.Thread(target=_run_job, args=(job_id, command, folder), daemon=True).start()
    return jsonify(job_id=job_id)


@app.get("/api/jobs/<job_id>")
def job_status(job_id: str):
    job = JOBS.get(job_id)
    if not job:
        return jsonify(error="Job not found or expired."), 404
    return jsonify(
        status=job["status"],
        percent=round(job["percent"], 1),
        item=job["item"],
        item_total=job["item_total"],
        line=job["line"],
        files=[os.path.basename(f) for f in job["files"]],
        error=job["error"],
    )


@app.get("/api/jobs/<job_id>/file/<int:index>")
def job_file(job_id: str, index: int):
    job = JOBS.get(job_id)
    if not job or not job["files"]:
        return jsonify(error="File not ready."), 404
    if index < 0 or index >= len(job["files"]):
        return jsonify(error="No such file."), 404
    path = job["files"][index]
    if not os.path.isfile(path):
        return jsonify(error="File no longer on disk."), 404
    return send_file(path, as_attachment=True, download_name=os.path.basename(path))


@app.get("/api/jobs/<job_id>/zip")
def job_zip(job_id: str):
    job = JOBS.get(job_id)
    if not job or not job["files"]:
        return jsonify(error="File not ready."), 404

    archive_path = os.path.join(job["folder"], f"download-{job_id[:8]}.zip")
    if not os.path.isfile(archive_path):
        with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_STORED) as archive:
            for path in job["files"]:
                if os.path.isfile(path):
                    archive.write(path, arcname=os.path.basename(path))
    return send_file(
        archive_path,
        as_attachment=True,
        download_name="downloads.zip",
        mimetype="application/zip",
    )


@app.get("/healthz")
def healthz():
    return jsonify(ok=True)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8000")), debug=False)
