# Makes a game icon with FLUX (Cloudflare Workers AI), cuts out the background, and uploads it to Roblox.
#
#   .\tools\icon.ps1 -Name coin -Subject "a shiny gold coin"
#   .\tools\icon.ps1 -Name coin -Subject "a shiny gold coin" -NoUpload     # only make the PNG
#   .\tools\icon.ps1 -Name coin -UploadOnly                                # upload an existing PNG
#
# Writes ui/icons/<Name>.png and adds "<Name> = <assetId>" to ui/icons.toml.
# Needs env vars: CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_API_TOKEN (Workers AI), ROBLOX_API_KEY.
param(
    [Parameter(Mandatory)] [string]$Name,
    [string]$Subject,
    [int]$Seed = 0,
    [switch]$NoUpload,
    [switch]$UploadOnly
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
if ($Name -notmatch '^[a-z][a-zA-Z0-9]*$') { throw "Name must be camelCase letters/digits, e.g. coin or gemBlue" }
$png = "ui/icons/$Name.png"
New-Item -ItemType Directory -Force ui/icons | Out-Null

# One prompt for every icon, so they all look like one set (outline matches the Depth Stack).
$style = "flat 2D mobile game UI icon of {0}. Bold simple shapes, thick dark navy outline of even width, " +
         "soft gradient shading, small white highlight at the top, centered, fills most of the frame, " +
         "isolated on a pure plain white background. One single object only. No text, no letters, no drop shadow, " +
         "no border, no frame, no sparkles, no particles, no decorations around it, no holes, no chains."

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class IconCut {
    // Flood-fills near-white background from the edges and makes it transparent (soft edge),
    // so white parts inside the icon stay. Then trims, pads to a square and resizes.
    public static void Run(string input, string output, int size, int tol, int feather, double margin) {
        using (var src = new Bitmap(input)) {
            int w = src.Width, h = src.Height;
            var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp)) g.DrawImage(src, 0, 0, w, h);
            var rect = new Rectangle(0, 0, w, h);
            var data = bmp.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            var px = new byte[w * h * 4];
            Marshal.Copy(data.Scan0, px, 0, px.Length);

            Func<int, int> dist = i => 255 - Math.Min(px[i], Math.Min(px[i + 1], px[i + 2]));
            var bg = new bool[w * h];
            var q = new Queue<int>();
            for (int x = 0; x < w; x++) { q.Enqueue(x); q.Enqueue((h - 1) * w + x); }
            for (int y = 0; y < h; y++) { q.Enqueue(y * w); q.Enqueue(y * w + w - 1); }
            while (q.Count > 0) {
                int p = q.Dequeue();
                if (bg[p] || dist(p * 4) > tol + feather) continue;
                bg[p] = true;
                int x = p % w, y = p / w;
                if (x > 0) q.Enqueue(p - 1);
                if (x < w - 1) q.Enqueue(p + 1);
                if (y > 0) q.Enqueue(p - w);
                if (y < h - 1) q.Enqueue(p + w);
            }
            for (int p = 0; p < w * h; p++) {
                int i = p * 4;
                if (bg[p]) {
                    int d = dist(i);
                    int a = d <= tol ? 0 : Math.Min(255, (d - tol) * 255 / Math.Max(1, feather));
                    px[i + 3] = (byte)a;
                }
            }
            // Keep only the biggest connected shape: drops stray sparkles and specks.
            var label = new int[w * h];
            int bestLabel = 0, bestSize = 0, next = 1;
            var stack = new Stack<int>();
            for (int s0 = 0; s0 < w * h; s0++) {
                if (label[s0] != 0 || px[s0 * 4 + 3] <= 16) continue;
                int count = 0; label[s0] = next; stack.Push(s0);
                while (stack.Count > 0) {
                    int p = stack.Pop(); count++;
                    int x = p % w, y = p / w;
                    int[] nb = { x > 0 ? p - 1 : -1, x < w - 1 ? p + 1 : -1, y > 0 ? p - w : -1, y < h - 1 ? p + w : -1 };
                    foreach (int n in nb) {
                        if (n >= 0 && label[n] == 0 && px[n * 4 + 3] > 16) { label[n] = next; stack.Push(n); }
                    }
                }
                if (count > bestSize) { bestSize = count; bestLabel = next; }
                next++;
            }
            int minX = w, minY = h, maxX = -1, maxY = -1;
            for (int p = 0; p < w * h; p++) {
                int i = p * 4;
                if (px[i + 3] > 16 && label[p] != bestLabel) { px[i + 3] = 0; continue; }
                if (px[i + 3] > 16) {
                    int x = p % w, y = p / w;
                    if (x < minX) minX = x; if (x > maxX) maxX = x;
                    if (y < minY) minY = y; if (y > maxY) maxY = y;
                }
            }
            Marshal.Copy(px, 0, data.Scan0, px.Length);
            bmp.UnlockBits(data);
            if (maxX < 0) throw new Exception("Nothing left after removing the background");

            int bw = maxX - minX + 1, bh = maxY - minY + 1;
            int side = (int)(Math.Max(bw, bh) * (1 + 2 * margin));
            using (var outBmp = new Bitmap(size, size, PixelFormat.Format32bppArgb))
            using (var g = Graphics.FromImage(outBmp)) {
                g.Clear(Color.Transparent);
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.CompositingQuality = CompositingQuality.HighQuality;
                float scale = (float)size / side;
                float dw = bw * scale, dh = bh * scale;
                g.DrawImage(bmp, new RectangleF((size - dw) / 2f, (size - dh) / 2f, dw, dh),
                    new RectangleF(minX, minY, bw, bh), GraphicsUnit.Pixel);
                outBmp.Save(output, ImageFormat.Png);
            }
            bmp.Dispose();
        }
    }
}
'@

function Need($var) {
    if (-not [Environment]::GetEnvironmentVariable($var)) { throw "Env var $var is not set (see CLAUDE.md > UI > Icons)" }
}

if (-not $UploadOnly) {
    if (-not $Subject) { throw "-Subject is required, e.g. -Subject 'a shiny gold coin'" }
    Need CLOUDFLARE_ACCOUNT_ID; Need CLOUDFLARE_API_TOKEN
    $prompt = [string]::Format($style, $Subject)
    $body = @{ prompt = $prompt; steps = 8 }
    if ($Seed -gt 0) { $body.seed = $Seed }
    Write-Host "Generating '$Name' with FLUX..."
    $uri = "https://api.cloudflare.com/client/v4/accounts/$($env:CLOUDFLARE_ACCOUNT_ID)/ai/run/@cf/black-forest-labs/flux-1-schnell"
    $res = Invoke-RestMethod -Method Post -Uri $uri -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $($env:CLOUDFLARE_API_TOKEN)" } -Body ($body | ConvertTo-Json)
    $raw = Join-Path (Resolve-Path ui/icons) "$Name.raw.jpg"
    [IO.File]::WriteAllBytes($raw, [Convert]::FromBase64String($res.result.image))
    [IconCut]::Run($raw, (Join-Path (Resolve-Path ui/icons) "$Name.png"), 256, 18, 40, 0.06)
    Remove-Item $raw
    Write-Host "Wrote $png"
}

if ($NoUpload) { exit 0 }
if (-not (Test-Path $png)) { throw "$png does not exist" }
Need ROBLOX_API_KEY

Add-Type -AssemblyName System.Net.Http
$key = $env:ROBLOX_API_KEY
$who = Invoke-RestMethod -Method Post -Uri "https://apis.roblox.com/api-keys/v1/introspect" `
    -ContentType "application/json" -Body (@{ apiKey = $key } | ConvertTo-Json)
$request = @{
    assetType = "Decal"
    displayName = "icon_$Name"
    description = "UI icon"
    creationContext = @{ creator = @{ userId = [string]$who.authorizedUserId } }
} | ConvertTo-Json -Depth 5

$client = New-Object System.Net.Http.HttpClient
$client.DefaultRequestHeaders.Add("x-api-key", $key)
$form = New-Object System.Net.Http.MultipartFormDataContent
$form.Add((New-Object System.Net.Http.StringContent($request)), "request")
$file = New-Object System.Net.Http.ByteArrayContent(, [IO.File]::ReadAllBytes((Resolve-Path $png)))
$file.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("image/png")
$form.Add($file, "fileContent", "$Name.png")
Write-Host "Uploading to Roblox..."
$resp = $client.PostAsync("https://apis.roblox.com/assets/v1/assets", $form).Result
$text = $resp.Content.ReadAsStringAsync().Result
if (-not $resp.IsSuccessStatusCode) { throw "Upload failed ($([int]$resp.StatusCode)): $text" }
$op = $text | ConvertFrom-Json

$assetId = $null
for ($i = 0; $i -lt 30 -and -not $assetId; $i++) {
    Start-Sleep -Seconds 2
    $r = $client.GetAsync("https://apis.roblox.com/assets/v1/$($op.path)").Result.Content.ReadAsStringAsync().Result | ConvertFrom-Json
    if ($r.done) { $assetId = $r.response.assetId }
}
if (-not $assetId) { throw "Upload did not finish in time; operation: $($op.path)" }

# Update the manifest (replace an existing line for this name).
$manifest = "ui/icons.toml"
$lines = @(Get-Content $manifest | Where-Object { $_ -notmatch "^$Name\s*=" })
$lines += "$Name = $assetId"
[IO.File]::WriteAllLines((Resolve-Path $manifest), $lines, (New-Object Text.UTF8Encoding $false))
Write-Host "Uploaded: $Name = $assetId (Roblox moderation can take a few minutes before it shows)"
