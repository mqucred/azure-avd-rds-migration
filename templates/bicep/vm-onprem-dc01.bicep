param virtualMachines_vm_onprem_dc01_name string = 'vm-onprem-dc01'
param disks_vm_onprem_dc01_OsDisk_1_f640d7d315aa4772a39bd2f727bb75fc_externalid string = '/subscriptions/sub-id/resourceGroups/RG-ONPREM-PROD-CENTRALINDIA-001/providers/Microsoft.Compute/disks/vm-onprem-dc01_OsDisk_1_f640d7d315aa4772a39bd2f727bb75fc'
param networkInterfaces_vm_onprem_dc01_nic_externalid string = '/subscriptions/sub-id/resourceGroups/RG-ONPREM-PROD-CENTRALINDIA-001/providers/Microsoft.Network/networkInterfaces/vm-onprem-dc01-nic'

resource virtualMachines_vm_onprem_dc01_name_resource 'Microsoft.Compute/virtualMachines@2026-04-01' = {
  name: virtualMachines_vm_onprem_dc01_name
  location: 'centralindia'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s_v2'
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        osType: 'Windows'
        name: '${virtualMachines_vm_onprem_dc01_name}_OsDisk_1_f640d7d315aa4772a39bd2f727bb75fc'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          id: disks_vm_onprem_dc01_OsDisk_1_f640d7d315aa4772a39bd2f727bb75fc_externalid
        }
        deleteOption: 'Detach'
      }
      dataDisks: []
      diskControllerType: 'SCSI'
    }
    osProfile: {
      computerName: virtualMachines_vm_onprem_dc01_name
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
          id: networkInterfaces_vm_onprem_dc01_nic_externalid
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: 'https://subergonpvmo093008420.blob.core.windows.net/'
      }
    }
  }
}

resource virtualMachines_vm_onprem_dc01_name_BGInfo 'Microsoft.Compute/virtualMachines/extensions@2026-04-01' = {
  parent: virtualMachines_vm_onprem_dc01_name_resource
  name: 'BGInfo'
  location: 'centralindia'
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Compute'
    type: 'BGInfo'
    typeHandlerVersion: '2.2'
  }
}
