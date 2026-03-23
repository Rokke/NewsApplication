param([string]$command, [string]$arg, [string]$arg2)

function BuildWeb([bool]$publish){
    Write-Host "`nBuilding web"
    Start-Process -FilePath "flutter" -ArgumentList "build web --release --base-href "/baseurl/"
    # flutter build web --wasm --release" -Wait
    if($LASTEXITCODE -ne 0){
        Write-Host "Building WEB failed with exit code $LASTEXITCODE" -ForegroundColor Red
        return $false
    }
    if($publish){
        Write-Host "`nWEB created, copying web to mobcon"
        Start-Process -FilePath "scp" -ArgumentList "-r build\web\* talgoe@192.168.86.47:/var/www/demo/baseurl" -Wait
        if($LASTEXITCODE -ne 0){
            Write-Host "Deploying WEB failed with exit code $LASTEXITCODE" -ForegroundColor Red
            return $false
        }
        Write-Host "WEB created and published" -ForegroundColor Green
    }else{
        Write-Host "WEB created" -ForegroundColor Green
    }
    return $true
}
function BuildWindows([bool]$publish = $false){
    if($publish){
        Write-Host "`nBuilding MSI package"
        dart run msix:create --certificate-password 'add password' --install-certificate true
        if($LASTEXITCODE -ne 0){
            Write-Host "`n`nBuilding MSI failed with exit code $LASTEXITCODE" -ForegroundColor Red
            return $false
        }
        Write-Host "`n`nMSI created, copying msix and web to mobcon" -ForegroundColor Green
        scp build\windows\x64\runner\release/rss_feed_reader.msix talgoe@192.168.86.47:/var/www/demo
    }else{
        Write-Host "`nBuilding Windows executable"
        flutter build windows --release
        if($LASTEXITCODE -ne 0){
            Write-Host "Building Windows failed with exit code $LASTEXITCODE" -ForegroundColor Red
            return $false
        }else{
            Write-Host "Windows executable created" -ForegroundColor Green
        }
    }
    return $true
}
function BuildAPK{
    Write-Host "`nBuilding APK"
    Start-Process -FilePath "flutter" -ArgumentList "build apk --release" -Wait
    if($LASTEXITCODE -ne 0){
        Write-Host "`nBuilding APK failed with exit code $LASTEXITCODE" -ForegroundColor Red
        return $false
    }
    Write-Host "APK created" -ForegroundColor Green
    return $true
}

set-location rss_feed_reader

switch($command){
    "generate" {
        Write-Host "Build watcher"
        if($arg -eq "watch"){
            if($arg2 -eq "del"){
                dart run build_runner watch --delete-conflicting-outputs
            } else {
                dart run build_runner watch
            }
        } else {
            if($arg2 -eq "del"){
                dart run build_runner build --delete-conflicting-outputs
            } else {
                dart run build_runner build
            }
        }
    }
    "icons"{
            dart run flutter_launcher_icons
    }
    "build" {
        Start-Process -FilePath "flutter" -ArgumentList "pub upgrade" -Wait
        switch($arg){
            "apk" {
                BuildAPK
            }
            "bundle" {
                Write-Host "Building appbundle"
                flutter build appbundle
            }
            "win"{
                BuildWindows
            }
            "msi"{
                BuildWindows($true)
            }
            "web"{
                BuildWeb
            }
            "all"{
                Write-Host "Building all"
                if((BuildAPK) -eq $true){
                    if((BuildWeb($true)) -eq $true){
                        if((BuildWindows($true)) -eq $true){
                            Write-Host "`nAll builds completed successfully" -ForegroundColor Green
                        Invoke-Item .\pubspec.yaml
                        }
                    }
                }
            }
            default{
                Write-Host "Invalid build argument`n`nSupported build arguments: web, win, msi, apk, bundle, all"
            }
        }
    }
    default {
        Write-Host "Invalid command`n`nSupported commands: build"
    }
}

set-location ..