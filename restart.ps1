#!/opt/microsoft/powershell/7/pwsh

Write-Host "Waiting for Docker..."
while ($true) {
    $result = docker info 2>&1
    if ($LASTEXITCODE -eq 0) { break }
    Write-Host "Docker not ready, retrying in 5s..."
    Start-Sleep -Seconds 5
}

set-location /home/jonathan/snowSeTools

# prod.sh wraps docker compose with --env-file prod.env -f docker-compose.prod.yml
./prod.sh down
./prod.sh up -d --remove-orphans
