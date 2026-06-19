<#
.SYNOPSIS
    Module 4 - App delivery: Juice Shop backend + Application Gateway WAFv2 + Front Door Premium.

.DESCRIPTION
    Constitution Principle VI (stage 4). Publishes a (deliberately vulnerable) demo
    backend application behind layered L7 protection:
      Internet -> Front Door Premium (+ WAF) -> App Gateway WAFv2 (+ OWASP WAF) -> backend
    This demonstrates defense-in-depth web protection. All WAF policies default to
    Prevention mode (Principle VII).

    BACKEND: By default ($DeployWebApp = $false) the backend is an Azure Container
    Instance (ACI) running OWASP Juice Shop, because sponsored/MCAP subscriptions cap
    App Service VM quota at 0. The App Gateway points at $WebAppBackendFqdn over HTTP:3000.
    The optional App Service path (New-AzWebApp) is kept behind the toggle for subs that
    do have App Service quota.

    COST NOTE: Front Door Premium (~$330/mo base) and App Gateway WAFv2 (~$0.36/hr +
    capacity units) are cost-bearing. Toggle in config.ps1 if you only need part of the chain.

.NOTES
    Prerequisite: 03-compute.ps1 and, for the default ACI backend, the Juice Shop
    container created by `create-aci.ps1` (imports the image into a private Azure
    Container Registry, then runs ACI from ACR - reliable, unlike pulling docker.io
    directly).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
$rg = $Lab.ResourceGroup
$loc = $Lab.Location

# --- Optional backend on App Service (Linux container) ------------------------
# Default backend is ACI (see $WebAppBackendFqdn); this App Service path only runs
# when $DeployWebApp = $true (subscriptions that have App Service VM quota).
$webAppHostName = $null
if ($Lab.DeployWebApp) {
    Write-LabStep "Creating App Service plan + container backend ($($Lab.WebAppContainerImage))"
    $plan = Get-AzAppServicePlan -Name $Lab.AppServicePlan -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if (-not $plan) {
        $plan = New-AzAppServicePlan -Name $Lab.AppServicePlan -ResourceGroupName $rg -Location $loc `
            -Tier 'Standard' -NumberofWorkers 1 -WorkerSize 'Small' -Linux
    }
    $app = Get-AzWebApp -Name $Lab.WebApp -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if (-not $app) {
        $app = New-AzWebApp -Name $Lab.WebApp -ResourceGroupName $rg -Location $loc `
            -AppServicePlan $Lab.AppServicePlan `
            -ContainerImageName $Lab.WebAppContainerImage
    }
    $webAppHostName = $app.DefaultHostName
    Write-Host "App Service backend: https://$webAppHostName" -ForegroundColor DarkGray
}

# --- Application Gateway WAFv2 -----------------------------------------------
$appGwPublicIp = $null
if ($Lab.DeployAppGateway) {
    # NSG on the App Gateway subnet. App Gateway v2 REQUIRES inbound GatewayManager
    # ports 65200-65535 for its control plane, and we open TCP 80 for the public HTTP
    # listener. Default NSG rules still cover VNet + AzureLoadBalancer inbound; DenyAll
    # blocks the rest. Without these two rules the gateway shows unhealthy / returns 000.
    Write-LabStep "Creating NSG '$($Lab.AppGwNsg)' for the App Gateway subnet"
    $agwNsg = Get-AzNetworkSecurityGroup -Name $Lab.AppGwNsg -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if (-not $agwNsg) {
        $ruleGwMgr = New-AzNetworkSecurityRuleConfig -Name 'Allow-AppGwV2-Infrastructure' -Access Allow -Protocol Tcp `
            -Direction Inbound -Priority 100 -SourceAddressPrefix 'GatewayManager' -SourcePortRange * `
            -DestinationAddressPrefix * -DestinationPortRange 65200-65535
        $ruleHttp = New-AzNetworkSecurityRuleConfig -Name 'Allow-HTTP-Inbound' -Access Allow -Protocol Tcp `
            -Direction Inbound -Priority 110 -SourceAddressPrefix 'Internet' -SourcePortRange * `
            -DestinationAddressPrefix * -DestinationPortRange 80
        $agwNsg = New-AzNetworkSecurityGroup -Name $Lab.AppGwNsg -ResourceGroupName $rg -Location $loc `
            -SecurityRule $ruleGwMgr, $ruleHttp
    }
    $hubForNsg = Get-AzVirtualNetwork -Name $Lab.HubVnet -ResourceGroupName $rg
    Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $hubForNsg -Name $Lab.AppGwSubnet `
        -AddressPrefix $Lab.AppGwPrefix -NetworkSecurityGroup $agwNsg | Out-Null
    $hubForNsg | Set-AzVirtualNetwork | Out-Null

    Write-LabStep "Creating Application Gateway WAFv2 '$($Lab.AppGwName)' (this can take ~15 min)"
    $existingGw = Get-AzApplicationGateway -Name $Lab.AppGwName -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if (-not $existingGw) {
        $hub = Get-AzVirtualNetwork -Name $Lab.HubVnet -ResourceGroupName $rg
        $gwSubnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $hub -Name $Lab.AppGwSubnet
        $gwPip = Get-AzPublicIpAddress -Name $Lab.AppGwPip -ResourceGroupName $rg

        # WAF policy (OWASP managed rules, Prevention mode)
        $wafPolicy = Get-AzApplicationGatewayFirewallPolicy -Name $Lab.AppGwWafPolicy -ResourceGroupName $rg -ErrorAction SilentlyContinue
        if (-not $wafPolicy) {
            $managedRuleSet = New-AzApplicationGatewayFirewallPolicyManagedRuleSet -RuleSetType 'OWASP' -RuleSetVersion '3.2'
            $managedRules = New-AzApplicationGatewayFirewallPolicyManagedRule -ManagedRuleSet $managedRuleSet
            $policySetting = New-AzApplicationGatewayFirewallPolicySetting -Mode 'Prevention' -State 'Enabled'
            $wafPolicy = New-AzApplicationGatewayFirewallPolicy -Name $Lab.AppGwWafPolicy -ResourceGroupName $rg `
                -Location $loc -ManagedRule $managedRules -PolicySetting $policySetting
        }

        $gipCfg   = New-AzApplicationGatewayIPConfiguration -Name 'agw-ipconfig' -Subnet $gwSubnet
        $feIp     = New-AzApplicationGatewayFrontendIPConfig -Name 'agw-feip' -PublicIPAddress $gwPip
        $fePort   = New-AzApplicationGatewayFrontendPort -Name 'agw-fe-port' -Port 80

        # Backend = ACI Juice Shop (HTTP:3000) when set, else the optional App Service host, else a placeholder.
        $backendFqdn  = if ($Lab.WebAppBackendFqdn) { $Lab.WebAppBackendFqdn } elseif ($webAppHostName) { $webAppHostName } else { 'www.bing.com' }
        $backendPort  = if ($Lab.WebAppBackendPort) { [int]$Lab.WebAppBackendPort } else { 443 }
        $backendProto = if ($Lab.WebAppBackendProtocol) { $Lab.WebAppBackendProtocol } else { 'Https' }
        $pool     = New-AzApplicationGatewayBackendAddressPool -Name 'agw-backend' -BackendFqdns $backendFqdn
        $probe    = New-AzApplicationGatewayProbeConfig -Name 'agw-probe' -Protocol $backendProto -Path '/' `
                        -Interval 30 -Timeout 30 -UnhealthyThreshold 3 -PickHostNameFromBackendHttpSettings
        $httpSet  = New-AzApplicationGatewayBackendHttpSetting -Name 'agw-httpsetting' -Port $backendPort -Protocol $backendProto `
                        -CookieBasedAffinity Disabled -PickHostNameFromBackendAddress -RequestTimeout 30 -Probe $probe
        $listener = New-AzApplicationGatewayHttpListener -Name 'agw-listener' -FrontendIPConfiguration $feIp `
                        -FrontendPort $fePort -Protocol Http
        $rule     = New-AzApplicationGatewayRequestRoutingRule -Name 'agw-rule' -RuleType Basic -Priority 100 `
                        -HttpListener $listener -BackendAddressPool $pool -BackendHttpSettings $httpSet
        $sku      = New-AzApplicationGatewaySku -Name 'WAF_v2' -Tier 'WAF_v2' -Capacity 2

        New-AzApplicationGateway -Name $Lab.AppGwName -ResourceGroupName $rg -Location $loc `
            -BackendAddressPools $pool -BackendHttpSettingsCollection $httpSet -Probes $probe `
            -FrontendIpConfigurations $feIp -GatewayIpConfigurations $gipCfg -FrontendPorts $fePort `
            -HttpListeners $listener -RequestRoutingRules $rule -Sku $sku `
            -FirewallPolicy $wafPolicy | Out-Null
    }
    $appGwPip = Get-AzPublicIpAddress -Name $Lab.AppGwPip -ResourceGroupName $rg
    $appGwPublicIp = $appGwPip.IpAddress
    Write-Host "App Gateway public IP: $appGwPublicIp" -ForegroundColor DarkGray
}

# --- Front Door Premium (+ WAF) ----------------------------------------------
if ($Lab.DeployFrontDoor) {
    Write-LabStep "Creating Front Door Premium profile '$($Lab.FrontDoorProfile)'"
    $fdProfile = Get-AzFrontDoorCdnProfile -Name $Lab.FrontDoorProfile -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if (-not $fdProfile) {
        $fdProfile = New-AzFrontDoorCdnProfile -Name $Lab.FrontDoorProfile -ResourceGroupName $rg `
            -SkuName 'Premium_AzureFrontDoor' -Location 'Global'
    }

    $endpoint = Get-AzFrontDoorCdnEndpoint -EndpointName $Lab.FrontDoorEndpoint -ProfileName $Lab.FrontDoorProfile -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if (-not $endpoint) {
        $endpoint = New-AzFrontDoorCdnEndpoint -EndpointName $Lab.FrontDoorEndpoint `
            -ProfileName $Lab.FrontDoorProfile -ResourceGroupName $rg -Location 'Global'
    }

    $originGroup = Get-AzFrontDoorCdnOriginGroup -OriginGroupName $Lab.FrontDoorOriginGroup -ProfileName $Lab.FrontDoorProfile -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if (-not $originGroup) {
        $probe = New-AzFrontDoorCdnOriginGroupHealthProbeSettingObject -ProbeIntervalInSecond 60 -ProbePath '/' -ProbeProtocol 'Http' -ProbeRequestType 'GET'
        $lb = New-AzFrontDoorCdnOriginGroupLoadBalancingSettingObject -SampleSize 4 -SuccessfulSamplesRequired 3 -AdditionalLatencyInMillisecond 50
        $originGroup = New-AzFrontDoorCdnOriginGroup -OriginGroupName $Lab.FrontDoorOriginGroup `
            -ProfileName $Lab.FrontDoorProfile -ResourceGroupName $rg `
            -HealthProbeSetting $probe -LoadBalancingSetting $lb
    }

    # Origin = App Gateway public IP (fallback to backend hostname)
    $originHost = if ($appGwPublicIp) { $appGwPublicIp } elseif ($webAppHostName) { $webAppHostName } else { 'www.bing.com' }
    $origin = Get-AzFrontDoorCdnOrigin -OriginName $Lab.FrontDoorOrigin -OriginGroupName $Lab.FrontDoorOriginGroup -ProfileName $Lab.FrontDoorProfile -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if (-not $origin) {
        New-AzFrontDoorCdnOrigin -OriginName $Lab.FrontDoorOrigin -OriginGroupName $Lab.FrontDoorOriginGroup `
            -ProfileName $Lab.FrontDoorProfile -ResourceGroupName $rg `
            -HostName $originHost -HttpPort 80 -HttpsPort 443 -OriginHostHeader $originHost `
            -Priority 1 -Weight 1000 -EnabledState 'Enabled' | Out-Null
    }

    $route = Get-AzFrontDoorCdnRoute -RouteName $Lab.FrontDoorRoute -EndpointName $Lab.FrontDoorEndpoint -ProfileName $Lab.FrontDoorProfile -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if (-not $route) {
        $og = Get-AzFrontDoorCdnOriginGroup -OriginGroupName $Lab.FrontDoorOriginGroup -ProfileName $Lab.FrontDoorProfile -ResourceGroupName $rg
        New-AzFrontDoorCdnRoute -RouteName $Lab.FrontDoorRoute -EndpointName $Lab.FrontDoorEndpoint `
            -ProfileName $Lab.FrontDoorProfile -ResourceGroupName $rg `
            -OriginGroupId $og.Id -LinkToDefaultDomain 'Enabled' -ForwardingProtocol 'HttpOnly' `
            -SupportedProtocol 'Http', 'Https' -PatternsToMatch '/*' -HttpsRedirect 'Enabled' | Out-Null
    }

    # Front Door WAF policy (Premium - managed rules, Prevention)
    # NOTE: Az.FrontDoor 2.2.0 injects a rule-set 'action' that DRS 2.1 rejects
    # ("This rule set action value is not supported"). The Azure CLI handles DRS 2.1
    # anomaly-scoring correctly, so we drive this step via 'az' and bind the policy
    # to the endpoint with a security policy association.
    Write-LabStep "Creating Front Door WAF policy '$($Lab.FrontDoorWaf)' (via Azure CLI)"
    $fdWafId = az network front-door waf-policy show --name $Lab.FrontDoorWaf --resource-group $rg --query id -o tsv 2>$null
    if (-not $fdWafId) {
        az network front-door waf-policy create --name $Lab.FrontDoorWaf --resource-group $rg `
            --sku 'Premium_AzureFrontDoor' --disabled false --mode 'Prevention' | Out-Null
        az network front-door waf-policy managed-rules add --policy-name $Lab.FrontDoorWaf --resource-group $rg `
            --type 'Microsoft_DefaultRuleSet' --version '2.1' --action 'Block' | Out-Null
        $fdWafId = az network front-door waf-policy show --name $Lab.FrontDoorWaf --resource-group $rg --query id -o tsv
    }

    # Associate the WAF policy with the Front Door endpoint (all paths)
    $secPolName = "$($Lab.FrontDoorProfile)-secpol"
    $existingSecPol = az afd security-policy show --resource-group $rg --profile-name $Lab.FrontDoorProfile --security-policy-name $secPolName --query id -o tsv 2>$null
    if (-not $existingSecPol) {
        $endpointId = az afd endpoint show --resource-group $rg --profile-name $Lab.FrontDoorProfile --endpoint-name $Lab.FrontDoorEndpoint --query id -o tsv
        az afd security-policy create --resource-group $rg --profile-name $Lab.FrontDoorProfile `
            --security-policy-name $secPolName --domains $endpointId --waf-policy $fdWafId | Out-Null
    }

    $endpoint = Get-AzFrontDoorCdnEndpoint -EndpointName $Lab.FrontDoorEndpoint -ProfileName $Lab.FrontDoorProfile -ResourceGroupName $rg
    Write-Host "Front Door endpoint: https://$($endpoint.HostName)" -ForegroundColor DarkGray
}

# --- Checkpoint --------------------------------------------------------------
Write-LabCheckpoint "App delivery ready. Defense-in-depth chain (Front Door WAF -> App Gateway WAF -> backend) deployed. Proceed to 05-monitoring.ps1"
