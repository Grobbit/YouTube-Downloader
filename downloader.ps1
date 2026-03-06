.\yt-dlp.exe -U
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

# 3. Check if it's a playlist and ask the user
$playlistFlag = "--no-playlist" # Default to single video
if ($url -like "*list=*") {
    $choice = Read-Host -Prompt "Playlist detected! Download (A)ll videos or (S)ingle video only? [A/S]"
    if ($choice -eq "A" -or $choice -eq "a") {
        $playlistFlag = "--yes-playlist"
        Write-Host "Mode: Full Playlist" -ForegroundColor Magenta
    } else {
        Write-Host "Mode: Single Video" -ForegroundColor Cyan
    }
}

# 4. Run the download
Write-Host "Starting Download..." -ForegroundColor Green
.\yt-dlp.exe $playlistFlag -f "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" --merge-output-format mp4 $url

Write-Host "Done! Check your folder." -ForegroundColor Yellow
Pause
