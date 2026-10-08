$ErrorActionPreference = "Stop"
$key = [Environment]::GetEnvironmentVariable("APIMART_KEY","User")
if(-not $key){ Write-Output "SIN_CLAVE: pide la key al usuario"; exit 1 }
$submitUrl = "https://api.apimart.ai/v1/images/generations"
$taskUrl   = "https://api.apimart.ai/v1/tasks/"
$headers   = @{ Authorization = "Bearer $key" }
$root = $PSScriptRoot
$assets = Join-Path $root "assets"
if(-not(Test-Path $assets)){ New-Item -ItemType Directory -Path $assets | Out-Null }
$raw = Join-Path $root "_raw"
if(-not(Test-Path $raw)){ New-Item -ItemType Directory -Path $raw | Out-Null }

$style = "candid editorial photograph, natural realistic skin texture with pores and slight imperfections, real everyday Latin American people (not models), authentic natural expression, soft natural window light, 50mm lens, shallow depth of field, subtle film grain, photorealistic documentary style. Avoid plastic skin, avoid perfect symmetry, avoid CGI, no text, no watermark, no logos."

$jobs = @(
  @{ out="hero";        size="1536x1024"; w=1100; prompt="Interior of an elegant established neighborhood hair and beauty salon in warm cream, wine-burgundy and gold accents, classic styling stations with large framed mirrors and warm golden lighting, a mature experienced hairstylist attending a client in a styling chair, tidy upscale timeless boutique atmosphere, bright natural daylight." },
  @{ out="svc-estetica";size="1024x1024"; w=820; prompt="A beauty esthetician shaping and grooming the eyebrows of a Latin American woman lying on a treatment bed in a clean elegant beauty salon, facial and brow aesthetics, soft warm tones, professional and candid." },
  @{ out="team-owner";  size="1024x1024"; w=720; prompt="Professional warm headshot of a mature experienced Latin American woman hairstylist and salon owner in her late 40s, elegant, wearing black, genuine confident warm smile conveying years of experience and trust, blurred warm classic salon background." },
  @{ out="team-2";      size="1024x1024"; w=720; prompt="Professional friendly headshot of a Latin American woman stylist and manicurist in her early 30s, natural confident smile, wearing black, blurred warm elegant salon background." }
)

foreach($j in $jobs){
  $body = @{ model="gpt-image-2"; prompt=($j.prompt+" "+$style); size=$j.size; n=1 } | ConvertTo-Json
  try{
    $sub = Invoke-RestMethod -Uri $submitUrl -Method Post -Headers $headers -ContentType "application/json" -Body $body
    $j.task = $sub.data[0].task_id
    Write-Output ("SUBMIT " + $j.out + " -> " + $j.task)
  } catch {
    Write-Output ("SUBMIT_FAIL " + $j.out + " : " + $_.Exception.Message)
    $j.task = $null
  }
  Start-Sleep -Milliseconds 400
}

Add-Type -AssemblyName System.Drawing
function Save-Jpg($srcPath,$dstPath,$targetW){
  $img = [System.Drawing.Image]::FromFile($srcPath)
  $w = $img.Width; $h = $img.Height
  if($w -gt $targetW){ $nh = [int]($h * ($targetW / $w)); $nw = $targetW } else { $nw=$w; $nh=$h }
  $bmp = New-Object System.Drawing.Bitmap $nw,$nh
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.DrawImage($img,0,0,$nw,$nh)
  $enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
  $p = New-Object System.Drawing.Imaging.EncoderParameters 1
  $p.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, [long]82)
  $bmp.Save($dstPath,$enc,$p)
  $g.Dispose(); $bmp.Dispose(); $img.Dispose()
}

foreach($j in $jobs){
  if(-not $j.task){ continue }
  $done=$false
  for($n=0;$n -lt 90 -and -not $done;$n++){
    Start-Sleep -Seconds 4
    try{
      $t = Invoke-RestMethod -Uri ($taskUrl+$j.task) -Method Get -Headers $headers
      $st = $t.data.status; if(-not $st){ $st=$t.status }
      if($st -eq "completed" -or $st -eq "succeeded"){
        $res = $t.data.result; if(-not $res){ $res=$t.result }
        $u = $res.images[0].url; if($u -is [array]){ $u=$u[0] }
        $rawPath = Join-Path $raw ($j.out+".png")
        Invoke-WebRequest -Uri $u -OutFile $rawPath
        Save-Jpg $rawPath (Join-Path $assets ($j.out+".jpg")) $j.w
        Write-Output ("DONE " + $j.out)
        $done=$true
      } elseif($st -eq "failed" -or $st -eq "error"){
        Write-Output ("FAILED " + $j.out)
        $done=$true
      }
    } catch {
      Write-Output ("POLL_ERR " + $j.out + " : " + $_.Exception.Message)
    }
  }
  if(-not $done){ Write-Output ("TIMEOUT " + $j.out) }
}
Write-Output "ALL_DONE"
