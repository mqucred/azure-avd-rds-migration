<#
.SYNOPSIS
    Phase 2: AVD landing zone, VNet peering, DNS.
#>

# ---- 0. Variables ----
$Location            = "centralindia"
$OnpremRg            = "rg-onprem-prod-centralindia-001"
$OnpremVNetName      = "vnet-onprem-prod-01"
$SpokeRg             = "rg-avd-prod-centralindia-001"
$SpokeVNetName       = "vnet-spoke-avd-prod-01"
$SpokeVNetPrefix     = "10.200.0.0/16"
$HostsSubnetName     = "snet-avd-hosts"
$HostsSubnetPrefix   = "10.200.1.0/24"
$StorageSubnetName   = "snet-avd-storage"
$StorageSubnetPrefix = "10.200.2.0/24"
$DcPrivateIp         = "10.100.1.4"

# ---- 1. Resource group for the spoke ----
New-AzResourceGroup -Name $SpokeRg -Location $Location

# ---- 2. Spoke VNet with both subnets ----
$hostsSubnet = New-AzVirtualNetworkSubnetConfig -Name $HostsSubnetName -AddressPrefix $HostsSubnetPrefix

$storageSubnet = New-AzVirtualNetworkSubnetConfig -Name $StorageSubnetName -AddressPrefix $StorageSubnetPrefix `
    -ServiceEndpoint "Microsoft.Storage"

$spokeVnet = New-AzVirtualNetwork -Name $SpokeVNetName -ResourceGroupName $SpokeRg `
    -Location $Location -AddressPrefix $SpokeVNetPrefix -Subnet $hostsSubnet, $storageSubnet

# ---- 3. Peering: spoke -> on-prem ----
$onpremVnet = Get-AzVirtualNetwork -Name $OnpremVNetName -ResourceGroupName $OnpremRg

Add-AzVirtualNetworkPeering -Name "spoke-to-onprem" -VirtualNetwork $spokeVnet `
    -RemoteVirtualNetworkId $onpremVnet.Id `
    -AllowForwardedTraffic -AllowGatewayTransit:$false

# ---- 4. Peering: on-prem -> spoke ----
Add-AzVirtualNetworkPeering -Name "onprem-to-spoke" -VirtualNetwork $onpremVnet `
    -RemoteVirtualNetworkId $spokeVnet.Id `
    -AllowForwardedTraffic -AllowGatewayTransit:$false

# ---- 5. Point spoke DNS at the on-prem DC ----
$spokeVnet = Get-AzVirtualNetwork -Name $SpokeVNetName -ResourceGroupName $SpokeRg
$spokeVnet.DhcpOptions.DnsServers = $DcPrivateIp
Set-AzVirtualNetwork -VirtualNetwork $spokeVnet

# ---- 6. Verify peering state on both sides ----
Get-AzVirtualNetworkPeering -VirtualNetworkName $OnpremVNetName -ResourceGroupName $OnpremRg |
    Select-Object Name, PeeringState
Get-AzVirtualNetworkPeering -VirtualNetworkName $SpokeVNetName -ResourceGroupName $SpokeRg |
    Select-Object Name, PeeringState

Write-Host "Phase 2 complete. Both peerings should show 'Connected'. Test DNS resolution from a VM in snet-avd-hosts before proceeding to Phase 3." -ForegroundColor Cyan
