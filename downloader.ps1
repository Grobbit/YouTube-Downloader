# 1. Check for yt-dlp and ffmpeg, download them if missing (No Admin needed)
if (!(Test-Path "yt-dlp.exe")) {
    Write-Host "Downloading yt-dlp..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -OutFile "yt-dlp.exe"
}

if (!(Test-Path "ffmpeg.exe")) {
    Write-Host "Downloading FFmpeg (this might take a minute)..." -ForegroundColor Cyan
    # Downloads a lite version of ffmpeg for Windows
    Invoke-WebRequest -Uri "https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v4.4.1/ffmpeg-4.4.1-win-64.zip" -OutFile "ffmpeg.zip"
    Expand-Archive -Path "ffmpeg.zip" -DestinationPath "." -Force
    Remove-Item "ffmpeg.zip"
}

# 2. Ask for the URL
$url = Read-Host -Prompt "Paste your YouTube URL here"

# 3. Run the download (Forces 1080p MP4 with sound)
Write-Host "Starting 1080p Download..." -ForegroundColor Green
.\yt-dlp.exe -f "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" --merge-output-format mp4 $url

Write-Host "Done! Check your folder." -ForegroundColor Yellow
Pause
