<#
.SYNOPSIS
    Phase 1: Simulated on-premises AD DS and legacy RDS baseline.

#>

# ---- 0. Variables ----
$Location        = "centralindia"
$ResourceGroup    = "rg-onprem-prod-centralindia-001"
$VNetName        = "vnet-onprem-prod-01"
$VNetPrefix      = "10.100.0.0/16"
$SubnetName      = "snet-dc"
$SubnetPrefix    = "10.100.1.0/24"
$DcVmName        = "vm-onprem-dc01"
$DcPrivateIp     = "10.100.1.4"
$RdsVmName       = "vm-onprem-rds01"
$RdsPrivateIp    = "10.100.1.5"
$VmSize          = "Standard_B2sv2"   # confirmed available: Bsv2 family, see quota plan
$AdminUsername   = "azlabadmin"       # do not use "admin" or "administrator", Azure rejects these
$ImagePublisher  = "MicrosoftWindowsServer"
$ImageOffer      = "WindowsServer"
$ImageSku        = "2022-datacenter-azure-edition"
$TimeZone        = "India Standard Time"   # Windows timezone ID, not IANA -- see note below

# Windows uses its own timezone ID strings, not IANA names like "Asia/Kolkata".
# "India Standard Time" is the correct Windows ID for IST (UTC+5:30) and is the
# only valid value for this region -- Windows has just one India timezone entry,
# unlike some countries with multiple zones. Confirm current spelling if this
# script is reused later: (Get-TimeZone -ListAvailable | Where Id -like "*India*")

# Credential is prompted interactively, never hardcode a password in this file
$AdminCredential = Get-Credential -UserName $AdminUsername -Message "Enter the local admin password for both VMs"

# ---- 1. Resource group ----
New-AzResourceGroup -Name $ResourceGroup -Location $Location

# ---- 2. VNet and subnet ----
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetPrefix
$vnet = New-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroup `
    -Location $Location -AddressPrefix $VNetPrefix -Subnet $subnetConfig

# ---- 3. NIC for the DC, static private IP ----
$dcNic = New-AzNetworkInterface -Name "$DcVmName-nic" -ResourceGroupName $ResourceGroup `
    -Location $Location -SubnetId $vnet.Subnets[0].Id `
    -PrivateIpAddress $DcPrivateIp

# ---- 4. Deploy the DC VM ----
$dcVmConfig = New-AzVMConfig -VMName $DcVmName -VMSize $VmSize |
    Set-AzVMOperatingSystem -Windows -ComputerName $DcVmName -Credential $AdminCredential -TimeZone $TimeZone |
    Set-AzVMSourceImage -PublisherName $ImagePublisher -Offer $ImageOffer -Skus $ImageSku -Version latest |
    Add-AzVMNetworkInterface -Id $dcNic.Id

New-AzVM -ResourceGroupName $ResourceGroup -Location $Location -VM $dcVmConfig

Write-Host "DC VM deployed. Next: RDP or Bastion into $DcVmName, run Install-ADDSForest interactively." -ForegroundColor Yellow

# ---- 5. NIC for the RDS VM, static private IP ----
$rdsNic = New-AzNetworkInterface -Name "$RdsVmName-nic" -ResourceGroupName $ResourceGroup `
    -Location $Location -SubnetId $vnet.Subnets[0].Id `
    -PrivateIpAddress $RdsPrivateIp

# ---- 6. Deploy the RDS VM ----
$rdsVmConfig = New-AzVMConfig -VMName $RdsVmName -VMSize $VmSize |
    Set-AzVMOperatingSystem -Windows -ComputerName $RdsVmName -Credential $AdminCredential -TimeZone $TimeZone |
    Set-AzVMSourceImage -PublisherName $ImagePublisher -Offer $ImageOffer -Skus $ImageSku -Version latest |
    Add-AzVMNetworkInterface -Id $rdsNic.Id

New-AzVM -ResourceGroupName $ResourceGroup -Location $Location -VM $rdsVmConfig

Write-Host "RDS VM deployed. Do not join it to the domain until AD DS promotion on the DC is complete." -ForegroundColor Yellow

# ---- 7. AFTER manual AD DS promotion — set VNet DNS to point to the DC ----
# Run this block only after Install-ADDSForest has completed and the DC has rebooted.
<#
$vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroup
$vnet.DhcpOptions.DnsServers = $DcPrivateIp
Set-AzVirtualNetwork -VirtualNetwork $vnet
#>

# ---- 8. Manual steps required inside the VMs (cannot be scripted unattended) ----
# On vm-onprem-dc01:
#   Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
#   Install-ADDSForest -DomainName "contoso.local" -InstallDns -Force  (reboots the VM)
#   New-ADOrganizationalUnit -Name "AVD_Users" -Path "DC=contoso,DC=local"
#   New-ADOrganizationalUnit -Name "AVD_Hosts" -Path "DC=contoso,DC=local"
#   New-ADUser -Name "avduser01" -SamAccountName "avduser01" -Path "OU=AVD_Users,DC=contoso,DC=local" -Enabled $true -AccountPassword (ConvertTo-SecureString "<CHANGE-ME>" -AsPlainText -Force)
#   New-ADUser -Name "avduser02" -SamAccountName "avduser02" -Path "OU=AVD_Users,DC=contoso,DC=local" -Enabled $true -AccountPassword (ConvertTo-SecureString "<CHANGE-ME>" -AsPlainText -Force)
#   New-Item -Path "C:\Shares\legacy-profiles" -ItemType Directory
#   New-SmbShare -Name "legacy-profiles" -Path "C:\Shares\legacy-profiles" -FullAccess "Everyone"  # tighten ACLs after testing
#
# On vm-onprem-rds01 (after joining the domain):
#   Add-Computer -DomainName "contoso.local" -Credential $AdminCredential -Restart
#   Install-WindowsFeature RDS-Gateway,RDS-Connection-Broker,RDS-RD-Server -IncludeManagementTools
#   New-RDSessionDeployment -ConnectionBroker "vm-onprem-rds01.contoso.local" -WebAccessServer "vm-onprem-rds01.contoso.local" -SessionHost "vm-onprem-rds01.contoso.local"

Write-Host "Phase 1 infrastructure deployed. Complete the manual AD DS and RDS steps listed at the bottom of this script." -ForegroundColor Cyan
