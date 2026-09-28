<powershell>
$ErrorActionPreference = "Stop"

# Install IIS
Install-WindowsFeature -Name Web-Server -IncludeManagementTools
Import-Module WebAdministration

# Static page
Remove-Item -Path "C:\inetpub\wwwroot\iisstart.*" -Force -ErrorAction SilentlyContinue
Set-Content -Path "C:\inetpub\wwwroot\index.html" -Value "i am a web server"

# Serve the default site on 8080 instead of 80
Get-WebBinding -Name "Default Web Site" -Protocol http | Remove-WebBinding
New-WebBinding -Name "Default Web Site" -Protocol http -Port 8080 -IPAddress "*"

# Open the Windows firewall for 8080
New-NetFirewallRule -DisplayName "HTTP 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow

Restart-Service W3SVC
</powershell>
