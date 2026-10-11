param virtualMachines_vm_avd_host_0_name string = 'vm-avd-host-0'
param disks_vm_avd_host_0_OsDisk_1_908ab2b73d814ba6a30bb686a8c53aea_externalid string = '/subscriptions/sub-id/resourceGroups/RG-AVD-PROD-CENTRALINDIA-001/providers/Microsoft.Compute/disks/vm-avd-host-0_OsDisk_1_908ab2b73d814ba6a30bb686a8c53aea'
param networkInterfaces_vm_avd_host_0_nic_externalid string = '/subscriptions/sub-id/resourceGroups/RG-AVD-PROD-CENTRALINDIA-001/providers/Microsoft.Network/networkInterfaces/vm-avd-host-0-nic'

resource virtualMachines_vm_avd_host_0_name_resource 'Microsoft.Compute/virtualMachines@2026-04-01' = {
  name: virtualMachines_vm_avd_host_0_name
  location: 'centralindia'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D2s_v5'
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'windows-11'
        sku: 'win11-23h2-avd'
        version: 'latest'
      }
      osDisk: {
        osType: 'Windows'
        name: '${virtualMachines_vm_avd_host_0_name}_OsDisk_1_908ab2b73d814ba6a30bb686a8c53aea'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          id: disks_vm_avd_host_0_OsDisk_1_908ab2b73d814ba6a30bb686a8c53aea_externalid
        }
        deleteOption: 'Detach'
      }
      dataDisks: []
      diskControllerType: 'SCSI'
    }
    osProfile: {
      computerName: virtualMachines_vm_avd_host_0_name
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
          assessmentMode: 'ImageDefault'
        }
        timeZone: 'India Standard Time'
      }
      secrets: []
      allowExtensionOperations: true
      requireGuestProvisionSignal: true
      adminUsername: 'azlabadmin'
    }
    securityProfile: {
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
      securityType: 'TrustedLaunch'
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterfaces_vm_avd_host_0_nic_externalid
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: 'https://subergavdvma100206190.blob.core.windows.net/'
      }
    }
  }
}

resource virtualMachines_vm_avd_host_0_name_BGInfo 'Microsoft.Compute/virtualMachines/extensions@2026-04-01' = {
  parent: virtualMachines_vm_avd_host_0_name_resource
  name: 'BGInfo'
  location: 'centralindia'
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Compute'
    type: 'BGInfo'
    typeHandlerVersion: '2.2'
  }
}
