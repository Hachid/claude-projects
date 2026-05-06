# sync-vault.ps1
# Sincroniza claude-projects vault com GitHub

$VaultPath = "C:\Projetos\claude-projects"
$SyncLogFile = "$VaultPath\SYNC_LOG.md"
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$CommitTime = Get-Date -Format "yyyy-MM-dd HH:mm"

Set-Location $VaultPath

Write-Host "📊 Status antes:" -ForegroundColor Cyan
git status --short

Write-Host ""
Write-Host "🔄 Sincronizando..." -ForegroundColor Yellow

git add .
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Erro ao fazer git add" -ForegroundColor Red
    exit 1
}

$CommitMsg = "docs: vault sync $CommitTime"
git commit -m $CommitMsg 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Commit: $CommitMsg" -ForegroundColor Green
} elseif ($LASTEXITCODE -eq 1) {
    Write-Host "ℹ️  Nada pra commitar (working tree clean)" -ForegroundColor Blue
} else {
    Write-Host "❌ Erro ao fazer commit" -ForegroundColor Red
    exit 1
}

Write-Host "📤 Pushing..." -ForegroundColor Cyan
$PushOutput = git push origin main 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Push para GitHub: OK" -ForegroundColor Green
    Write-Host $PushOutput
} else {
    Write-Host "⚠️  Push com aviso:" -ForegroundColor Yellow
    Write-Host $PushOutput
}

$LogEntry = "- [$Timestamp] ✅ Synced ($(git rev-parse --short HEAD))"
Add-Content -Path $SyncLogFile -Value $LogEntry

Write-Host ""
Write-Host "🎉 Sync concluído!" -ForegroundColor Green
Write-Host "📝 Log atualizado em SYNC_LOG.md"

Write-Host ""
Write-Host "📊 Status depois:" -ForegroundColor Cyan
git status --short
