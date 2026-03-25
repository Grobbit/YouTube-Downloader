Set-Location -Path $PSScriptRoot
# 1. Setup Phase: Check for tools once at the start
if (Test-Path "yt-dlp.exe") {
    Write-Host "Checking for yt-dlp updates..." -ForegroundColor Gray
    .\yt-dlp.exe -U
} else {
    Write-Host "yt-dlp not found. Downloading..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -OutFile "yt-dlp.exe"
}

if (!(Test-Path "ffmpeg.exe")) {
    Write-Host "FFmpeg not found. Downloading dependencies..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v4.4.1/ffmpeg-4.4.1-win-64.zip" -OutFile "ffmpeg.zip"
    Expand-Archive -Path "ffmpeg.zip" -DestinationPath "." -Force
    Remove-Item "ffmpeg.zip"
}

# --- Session Preferences ---
$res = Read-Host -Prompt "Enter Max Quality (e.g., 720, 1080, 2160)"
$audioMode = Read-Host -Prompt "Download Audio Only? (y/n)"
if ($audioMode -eq "y") { 
    $formatArgs = "-x --audio-format mp3" 
} else { 
    $formatArgs = "-f `"bestvideo[height<=$res][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best`" --merge-output-format mp4" 
}

# 2. The Loop Phase: This keeps the window open for new links
while ($true) {
    Clear-Host
    Write-Host "--- Downloader Ready ---" -ForegroundColor Cyan
    $url = Read-Host -Prompt "Paste your URL here (or type 'exit' to close)"

    # Exit condition
    if ($url -eq "exit") { break }
    # Reset Settings Trigger
    if ($url -eq "change") {
        $res = Read-Host -Prompt "New Max Resolution (720, 1080, 2160)"
        $audioMode = Read-Host -Prompt "Audio Only? (y/n)"
        if ($audioMode -eq "y") {
            $formatArgs = "-x --audio-format mp3"
        } else {
            $formatArgs = "-f `"bestvideo[height<=$res][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best`" --merge-output-format mp4"
        }
        continue # Skips the rest of the loop and goes back to "Paste URL"
    }

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
Write-Host "Starting Download (Res: $res | Audio: $audioMode)..." -ForegroundColor Green

# Stealth flags to bypass server-side throttling on generic sites
$stealthFlags = '--impersonate "chrome" --referer "https://www.supercartoons.net/" --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"'

# Combine everything
$allArgs = "$playlistFlag $formatArgs $stealthFlags `"$url`""

# Execute
Invoke-Expression ".\yt-dlp.exe $allArgs"
        
        # We use Start-Process to handle the complex argument string safely
        $allArgs = "$playlistFlag $formatArgs `"$url`""
        Invoke-Expression ".\yt-dlp.exe $allArgs"
        Write-Host "`nDone! Check your folder." -ForegroundColor Yellow
        Write-Host "Press any key to grab another video..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}
