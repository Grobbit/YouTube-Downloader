# Render needs FFmpeg on the box, which a plain Python service can't guarantee,
# so this runs as a Docker service. yt-dlp itself comes from requirements.txt.
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8000 \
    DOWNLOAD_DIR=/tmp/ytdl-web

# FFmpeg + a current yt-dlp binary, exactly the two things the script fetched.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY web ./web

RUN useradd --create-home --uid 10001 appuser \
 && mkdir -p /tmp/ytdl-web \
 && chown -R appuser:appuser /tmp/ytdl-web /app
USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
  CMD python -c "import urllib.request,os;urllib.request.urlopen(f'http://127.0.0.1:{os.environ.get(\"PORT\",\"8000\")}/healthz',timeout=4)"

# One worker, many threads: job state lives in memory, so a second worker
# process would not see jobs started by the first.
CMD ["sh", "-c", "gunicorn app:app --bind 0.0.0.0:${PORT:-8000} --timeout 600 --workers 1 --threads 16"]
