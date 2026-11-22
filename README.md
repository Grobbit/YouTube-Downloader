# YouTube Downloader

A small web downloader built on [yt-dlp](https://github.com/yt-dlp/yt-dlp) and FFmpeg, deployable to
[Render](https://render.com) in one click.

This is a Python port of the original PowerShell script (`downloader.ps1`, still included for
reference). **The features are identical — nothing was added, nothing was dropped:**

| Original script | This version |
| --- | --- |
| Downloads / auto-updates `yt-dlp`, fetches FFmpeg | FFmpeg is in the Docker image; yt-dlp upgrades itself on boot |
| `Enter Max Quality` prompt | Quality picker: 720 / 1080 / 2160, or type any height |
| `Download Audio Only? (y/n)` | "Audio only (MP3)" switch → `-x --audio-format mp3` |
| `while ($true)` loop for one link after another | Every finished download returns to a ready form ("Grab another") |
| Link containing `list=` → asks **All** or **Single** | The same prompt appears inline when the pasted link contains a playlist |
| `-f "bestvideo[height<=N][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" --merge-output-format mp4` | Identical format string and merge flag |
| `--no-playlist` / `--yes-playlist` | Identical flags |
| "Done! Check your folder." | File download button (a `.zip` when there is more than one file) |

Because yt-dlp is not limited to YouTube, any site it supports works here too.

## Deploying to Render

The repo ships a `Dockerfile` and a `render.yaml` blueprint. Docker is used because Render's plain
Python runtime has no FFmpeg.

**Blueprint route (recommended)**

1. Push this repo to GitHub.
2. In Render: **New → Blueprint**, pick the repo, click **Apply**. Render reads `render.yaml`.
3. Wait for the first build, then open the service URL.

**Manual route**

1. Render → **New → Web Service** → connect the repo.
2. Language: **Docker**. Leave the Dockerfile path as `Dockerfile`.
3. Add environment variables if you want to change defaults (all optional):

   | Variable | Default | Meaning |
   | --- | --- | --- |
   | `PORT` | `8000` | Port Gunicorn binds to (Render sets this for you) |
   | `DOWNLOAD_DIR` | `/tmp/ytdl-web` | Scratch folder for in-progress and finished downloads |
   | `JOB_TTL_SECONDS` | `7200` | How long a finished download stays downloadable |
   | `YTDLP_AUTO_UPDATE` | `1` | Upgrade yt-dlp from PyPI at startup |

4. Deploy.

> **Free plan note:** the filesystem is ephemeral and the instance sleeps after inactivity. A
> download that is mid-flight when the instance sleeps is lost, and finished files disappear on
> restart. That matches the original script's "check your folder" model — grab your file promptly.

## Running locally

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
ffmpeg -version            # must be on PATH for video/audio merging
PORT=8000 .venv/bin/python app.py
```

Then open <http://localhost:8000>.

With Docker:

```bash
docker build -t youtube-downloader .
docker run -p 8000:8000 youtube-downloader
```

## Layout

```
app.py                  Flask app: job runner, yt-dlp argument building, file serving
web/templates/index.html
web/static/style.css    Light "paper" theme
web/static/app.js       Form, playlist prompt, progress polling
downloader.ps1          The original script, unchanged
Dockerfile              Python 3.11 + FFmpeg
render.yaml             Render blueprint
```

## Notes

- Downloads are held in memory per process, so the container runs a single Gunicorn worker with
  multiple threads. Scaling to more instances would need a shared job store.
- Respect the terms of service of the sites you download from and the rights of the people who made
  the content.
