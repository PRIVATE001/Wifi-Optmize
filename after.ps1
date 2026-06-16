# === AFTER ===
"=== AFTER ===" | Out-File "$env:USERPROFILE\Desktop\network_compare.txt" -Append
"Date: $(Get-Date)" | Add-Content "$env:USERPROFILE\Desktop\network_compare.txt"
"" | Add-Content "$env:USERPROFILE\Desktop\network_compare.txt"

"--- DNS Servers ---" | Add-Content "$env:USERPROFILE\Desktop\network_compare.txt"
Get-DnsClientServerAddress | Format-Table | Out-String | Add-Content "$env:USERPROFILE\Desktop\network_compare.txt"

"" | Add-Content "$env:USERPROFILE\Desktop\network_compare.txt"
"--- TCP Settings ---" | Add-Content "$env:USERPROFILE\Desktop\network_compare.txt"
netsh int tcp show global | Add-Content "$env:USERPROFILE\Desktop\network_compare.txt"

"" | Add-Content "$env:USERPROFILE\Desktop\network_compare.txt"
"--- Adapter Info ---" | Add-Content "$env:USERPROFILE\Desktop\network_compare.txt"
Get-NetAdapter | Select-Object Name, Status, LinkSpeed | Format-Table | Out-String | Add-Content "$env:USERPROFILE\Desktop\network_compare.txt"

Write-Host "Saved.nOw Comparive "