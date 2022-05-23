$7zipPath = "$env:ProgramFiles\7-Zip\7z.exe"

if (-not (Test-Path -Path $7zipPath -PathType Leaf)) {
    throw "7 zip file '$7zipPath' not found"
}

Set-Alias 7z $7zipPath

function getToken {
  if (Test-Path -Path "token" -PathType Leaf) {
    Write-Host "token alredy exists, skipping"
    Return
  } 
  
  New-Item -Name "wrk" -ItemType "directory"
  Set-Location -Path "wrk"

  (New-Object System.Net.WebClient).DownloadFile("https://curseforge.overwolf.com/downloads/curseforge-latest-win64.exe", "wrk\cf.exe")
  7z -y x "cf.exe"
  7z -y x "`$PLUGINSDIR\app-64.7z"
  
  [regex]::Match(
    (Get-Content -Path "resources\app\dist\desktop\desktop.js") , 
    'cfCoreApiKey":"(.*?)"'
  ).captures.groups[1].value | Out-File -FilePath "..\token"
  
  Set-Location -Path ".."
  Remove-Item -Recurse "wrk"
}

function downloadPack {
  param($packZip)
  $token = Get-Content -Path "token"

  New-Item -Name "packwrk" -ItemType "directory"
  Set-Location -Path "packwrk"

  if ([System.IO.Path]::IsPathRooted("$packZip")) {
    7z x -y "$packZip"
  } else {
    7z x -y "..\$packZip"
  }

  $manifest = Get-Content -Path "manifest.json" | ConvertFrom-Json

  New-Item -Name "mods" -ItemType "directory"

  Write-Host "downloading $($manifest.files.Count) mods"

  $manifest.files | ForEach-Object {
    $project = $_.projectID
    $file = $_.fileID

    try {
      $uri = ( `
        (Invoke-WebRequest  `
        -Headers @{"x-api-key" = "$token"} `
        -Uri "https://api.curseforge.com/v1/mods/$project/files/$file").ToString() |
        ConvertFrom-Json `
      ).data.downloadUrl `
      -replace 's/\[/%5b/g;s/\]/%5d/g;',"s/'/%27/g;s/ /%20/g"
    }
    catch {
      Write-Warning "failed to get uri https://api.curseforge.com/v1/mods/$project/files/$file"
    }

    try {
      (New-Object System.Net.WebClient).DownloadFile($uri, "packwrk\mods\$(split-path -path $uri -leaf)")
    }
    catch {
      Write-Warning "failed to download $uri"
    }

  }

  $instanceName = $manifest.name -replace '[\W]', ''

  New-Item -Name $instanceName -ItemType "directory"
  New-Item -Name "$instanceName\instance.cfg"
  Set-Content "$instanceName\instance.cfg" "InstanceType=OneSix"
  New-Item -Name "$instanceName\mmc-pack.json"

  if ($manifest.minecraft.modLoaders.id -match "forge") {
    $modloader = '{
      "uid": "net.minecraftforge",
      "version": "' + ($manifest.minecraft.modLoaders.id -replace 'forge-', "") + '"
    }'
  } elseif ($manifest.minecraft.modLoaders.id -match "fabric") {
    $modloader = '{
      "uid": "net.fabricmc.fabric-loader",
      "version": "' + ($manifest.minecraft.modLoaders.id -replace 'fabric-', "") + '"
    }'
  } else {
    $modloader = '{
      "uid": "org.quiltmc.quilt-loader",
      "version": "' + ($manifest.minecraft.modLoaders.id -replace 'quilt-', "") + '"
    }'
  }

  Set-Content "$instanceName\mmc-pack.json" (`
  '{
    "components": [
        {
            "important": true,
            "uid": "net.minecraft",
            "version": "' + $manifest.minecraft.version + '"
        },
        ' + $modloader + '
    ],
    "formatVersion": 1
  }')

  New-Item -Name "$instanceName\.minecraft" -ItemType "directory"

  Move-Item -Path "mods" -Destination "$instanceName\.minecraft"
  Move-Item -Path "overrides\*" -Destination "$instanceName\.minecraft"

  7z a -tzip -r0 "$instanceName.zip" "$instanceName"

  Set-Location -Path ".."

  Move-Item -Path "packwrk\$instanceName.zip" -Destination "."
  Remove-Item -Recurse "packwrk"
}

getToken

if ($args.Length -eq 0) {
  Write-Host "specify path to pack zip"
  Exit
}
downloadPack($args[0])
