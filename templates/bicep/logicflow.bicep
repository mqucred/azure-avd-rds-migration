param workflows_la_avd_soc_001_name string = 'la-avd-soc-001'
param connections_azuresentinel_externalid string = '/subscriptions/sub-id/resourceGroups/rg-avd-prod-centralindia-001/providers/Microsoft.Web/connections/azuresentinel'
param connections_outlook_externalid string = '/subscriptions/sub-id/resourceGroups/rg-avd-prod-centralindia-001/providers/Microsoft.Web/connections/outlook'

resource workflows_la_avd_soc_001_name_resource 'Microsoft.Logic/workflows@2019-05-01' = {
  name: workflows_la_avd_soc_001_name
  location: 'centralindia'
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        Microsoft_Sentinel_incident: {
          type: 'ApiConnectionWebhook'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel-2\'][\'connectionId\']'
              }
            }
            body: {
              callback_url: '@listCallbackUrl()'
            }
            path: '/incident-creation'
          }
        }
      }
      actions: {
        DEBUG_IncidentData: {
          runAfter: {}
          type: 'Compose'
          inputs: {
            ObjectId: '@triggerBody()?[\'object\']?[\'id\']'
            IncidentArmId: '@triggerBody()?[\'object\']?[\'properties\']?[\'incidentArmId\']'
            Object: '@triggerBody()?[\'object\']'
          }
        }
        'Entities_-_Get_Accounts': {
          runAfter: {
            DEBUG_IncidentData: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel-2\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            path: '/entities/account'
          }
        }
        'Send_an_email_(V2)': {
          runAfter: {
            'Entities_-_Get_Accounts': [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'outlook-1\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              To: 'email@example.com'
              Subject: '[SENTINEL SOAR] @{triggerBody()?[\'object\']?[\'properties\']?[\'title\']}'
              Body: '<p><strong>SENTINEL SOAR INCIDENT DETECTED</strong></p><p><strong>Playbook:</strong> ${workflows_la_avd_soc_001_name}</p><p><strong>Execution Reason:</strong> Controlled Security Drill Validation</p><hr><p><strong>Incident:</strong><br>@{triggerBody()?[\'object\']?[\'properties\']?[\'title\']}</p><p><strong>Incident ID:</strong><br>@{triggerBody()?[\'object\']?[\'id\']}</p><p><strong>Account Entity:</strong><br>@{body(\'Entities_-_Get_Accounts\')?[\'Accounts\']}</p><p><strong>SOAR Validation:</strong></p><ul><li>Sentinel Analytics Rule triggered</li><li>Sentinel incident created</li><li>Logic App incident trigger executed</li><li>Account entity extracted successfully</li><li>Outlook notification delivered successfully</li></ul><p><strong>Result:</strong> End-to-end Sentinel -&gt; Logic App -&gt; Outlook workflow validated.</p><hr><p><strong>Runtime Debug - Object ID:</strong><br>@{outputs(\'DEBUG_IncidentData\')?[\'ObjectId\']}</p><p><strong>Runtime Debug - Incident ARM ID:</strong><br>@{outputs(\'DEBUG_IncidentData\')?[\'IncidentArmId\']}</p></body>'
              Importance: 'Normal'
            }
            path: '/v2/Mail'
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        type: 'Object'
        value: {
          'azuresentinel-2': {
            id: '/subscriptions/sub-id/resourceGroups/rg-avd-prod-centralindia-001/providers/Microsoft.Web/locations/centralindia/managedApis/azuresentinel'
            connectionId: connections_azuresentinel_externalid
            connectionName: 'azuresentinel'
            connectionProperties: {}
          }
          'outlook-1': {
            id: '/subscriptions/sub-id/resourceGroups/rg-avd-prod-centralindia-001/providers/Microsoft.Web/locations/centralindia/managedApis/outlook'
            connectionId: connections_outlook_externalid
            connectionName: 'outlook'
            connectionProperties: {}
          }
        }
      }
    }
    endpointsConfiguration: {
      workflow: {
        outgoingIpAddresses: [
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
        ]
        accessEndpointIpAddresses: [
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
        ]
      }
      connector: {
        outgoingIpAddresses: [
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
          {
            address: 'ipaddress'
          }
        ]
      }
    }
  }
}

resource workflows_la_avd_soc_001_name_default 'Microsoft.Logic/workflows/accessKeys@2015-02-01-preview' = {
  parent: workflows_la_avd_soc_001_name_resource
  name: 'default'
  properties: {}
}
