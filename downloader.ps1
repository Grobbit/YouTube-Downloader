Set-Location -Path $PSScriptRoot

$ytDlpPath = Join-Path $PSScriptRoot 'yt-dlp.exe'
$ffmpegPath = Join-Path $PSScriptRoot 'ffmpeg.exe'

function Initialize-Dependencies {
    if (Test-Path -LiteralPath $ytDlpPath) {
        Write-Host 'Checking for yt-dlp updates...' -ForegroundColor Gray
        & $ytDlpPath -U
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "yt-dlp update check exited with code $LASTEXITCODE. Continuing with the installed version."
        }
    }
    else {
        Write-Host 'yt-dlp not found. Downloading...' -ForegroundColor Cyan
        Invoke-WebRequest `
            -Uri 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe' `
            -OutFile $ytDlpPath
    }

    if (-not (Test-Path -LiteralPath $ffmpegPath)) {
        $archivePath = Join-Path $PSScriptRoot 'ffmpeg.zip'
        Write-Host 'FFmpeg not found. Downloading dependencies...' -ForegroundColor Cyan

        try {
            Invoke-WebRequest `
                -Uri 'https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v4.4.1/ffmpeg-4.4.1-win-64.zip' `
                -OutFile $archivePath
            Expand-Archive -LiteralPath $archivePath -DestinationPath $PSScriptRoot -Force
        }
        finally {
            if (Test-Path -LiteralPath $archivePath) {
                Remove-Item -LiteralPath $archivePath -Force
            }
        }
    }
}

function Read-DownloadPreferences {
    do {
        $resolutionInput = Read-Host -Prompt 'Enter Max Quality (e.g., 720, 1080, 2160)'
        $resolution = 0
        $validResolution = [int]::TryParse($resolutionInput, [ref]$resolution) -and $resolution -gt 0
        if (-not $validResolution) {
            Write-Host 'Please enter a positive number for the maximum resolution.' -ForegroundColor Yellow
        }
    } until ($validResolution)

    $audioOnly = (Read-Host -Prompt 'Download Audio Only? (y/n)') -ieq 'y'
    return @{
        Resolution = $resolution
        AudioOnly  = $audioOnly
    }
}

function Get-DownloadArguments {
    param(
        [hashtable] $Preferences,
        [string] $Url,
        [bool] $DownloadPlaylist
    )

    $arguments = @()
    if ($DownloadPlaylist) {
        $arguments += '--yes-playlist'
    }
    else {
        $arguments += '--no-playlist'
    }

    if ($Preferences.AudioOnly) {
        $arguments += @('-x', '--audio-format', 'mp3')
    }
    else {
        $format = "bestvideo[height<=$($Preferences.Resolution)][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"
        $arguments += @('-f', $format, '--merge-output-format', 'mp4')
    }

    $arguments += $Url
    return ,$arguments
}

try {
    Initialize-Dependencies
}
catch {
    Write-Error "Could not prepare yt-dlp or FFmpeg: $_"
    exit 1
}

$preferences = Read-DownloadPreferences

while ($true) {
    Clear-Host
    Write-Host '--- Downloader Ready ---' -ForegroundColor Cyan
    $url = (Read-Host -Prompt "Paste your URL here (or type 'change' or 'exit')").Trim()

    if ($url -ieq 'exit') {
        break
    }
    if ($url -ieq 'change') {
        $preferences = Read-DownloadPreferences
        continue
    }
    if ([string]::IsNullOrWhiteSpace($url)) {
        continue
    }

    $downloadPlaylist = $false
    if ($url -match '(?:[?&])list=') {
        $choice = Read-Host -Prompt 'Playlist detected! Download (A)ll videos or (S)ingle video? [A/S]'
        $downloadPlaylist = $choice -ieq 'a'
        if ($downloadPlaylist) {
            Write-Host 'Mode: Full Playlist' -ForegroundColor Magenta
        }
        else {
            Write-Host 'Mode: Single Video' -ForegroundColor Cyan
        }
    }

    Write-Host "Starting Download (Max Res: $($preferences.Resolution) | Audio Only: $($preferences.AudioOnly))..." -ForegroundColor Green
    $downloadArguments = Get-DownloadArguments `
        -Preferences $preferences `
        -Url $url `
        -DownloadPlaylist $downloadPlaylist
    & $ytDlpPath @downloadArguments

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nDone! Check your folder." -ForegroundColor Yellow
    }
    else {
        Write-Host "`nyt-dlp exited with code $LASTEXITCODE." -ForegroundColor Red
    }

    Write-Host 'Press any key to grab another video...' -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
