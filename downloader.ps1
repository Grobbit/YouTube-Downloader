# 1. Setup Phase: Check for tools once at the start
if (Test-Path "yt-dlp.exe") { .\yt-dlp.exe -U }
    Write-Host "Downloading yt-dlp..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -OutFile "yt-dlp.exe"
}

if (!(Test-Path "ffmpeg.exe")) {
    Write-Host "Downloading FFmpeg..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v4.4.1/ffmpeg-4.4.1-win-64.zip" -OutFile "ffmpeg.zip"
    Expand-Archive -Path "ffmpeg.zip" -DestinationPath "." -Force
    Remove-Item "ffmpeg.zip"
}

# 2. The Loop Phase: This keeps the window open for new links
while ($true) {
    Clear-Host
    Write-Host "--- Downloader Ready ---" -ForegroundColor Cyan
    $url = Read-Host -Prompt "Paste your URL here (or type 'exit' to close)"

    # Exit condition
    if ($url -eq "exit") { break }

    if (![string]::IsNullOrWhiteSpace($url)) {
        
        # 3. Playlist Check
        $playlistFlag = "--no-playlist" 
        if ($url -like "*list=*") {
            $choice = Read-Host -Prompt "Playlist detected! Download (A)ll videos or (S)ingle video? [A/S]"
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

        Write-Host "`nDone! Check your folder." -ForegroundColor Yellow
        Write-Host "Press any key to grab another video..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}
