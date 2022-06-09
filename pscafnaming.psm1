function Update-CAFresourceDefinitions {



    $ResourceDefinitions = (Invoke-RestMethod 'https://github.com/aztfmod/terraform-provider-azurecaf/raw/1c4e3fb6b7cbcf23ece99dbb662755cd3b3dcda9/resourceDefinition_out_of_docs.json') + `
    (Invoke-RestMethod 'https://github.com/aztfmod/terraform-provider-azurecaf/raw/1c4e3fb6b7cbcf23ece99dbb662755cd3b3dcda9/resourceDefinition.json')

    $ResourceDefinitions | ConvertTo-Json | Set-Content $PSScriptRoot\resourceDefinitions.json -Force
}

function New-CAFResourceName {
    param(
        [parameter()]
        [string]
        $Name,

        [parameter()]
        [string[]]
        $Prefixes,

        [parameter()]
        [string[]]
        $Suffixes,

        [parameter()]
        [string]
        $Separator = '-',

        [parameter()]
        [bool]
        $CleanInput = $true,

        [parameter()]
        [bool]
        $AddResourceAbbreviation = $true,

        [parameter()]
        [switch]
        $IgnoreValidations
    )

    DynamicParam {
        # Set the dynamic parameter for Resource Types
        $ParameterName = 'ResourceType'
        
        # Create the dictionary 
        $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

        # Create the collection of attributes
        $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
        
        # Create and set the parameters' attributes
        $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
        $ParameterAttribute.Mandatory = $true
        $ParameterAttribute.Position = 1

        # Add the attributes to the attributes collection
        $AttributeCollection.Add($ParameterAttribute)

        # Generate and set the ValidateSet 
        $arrSet = Get-Content -Path $PSScriptRoot/resourceDefinitions.json | ConvertFrom-Json | Select-Object -ExpandProperty name | ForEach-Object { $_ -replace '^azurerm_' -replace '_', ' ' } | Sort-Object
        $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($arrSet)

        # Add the ValidateSet to the attributes collection
        $AttributeCollection.Add($ValidateSetAttribute)

        # Create and return the dynamic parameter
        $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, [string], $AttributeCollection)
        $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)
        return $RuntimeParameterDictionary
    }

    begin {
        # Load saved resource defintions from module folder
        $resourceDefinitions = Get-Content -Path $PSScriptRoot/resourceDefinitions.json | ConvertFrom-Json
    }

    process {
        # Select current resource definition object based on your input
        $resourceDefinition = $resourceDefinitions.where{ $_.name -eq "azurerm_$($PSBoundParameters["ResourceType"] -replace ' ','_')" }

        # Declare name part variable
        $slug = $resourceDefinition.slug
        $random = $null
        $suffixesstr = $suffixes -join ''
        $prefixesstr = $prefixes -join ''

        function shorten ([ref]$value, [ref]$length) {
            # calculate how many chars we are over the limit
            $over = ($value.value.length + $length.value) - $resourceDefinition.max_length

            if ($over -gt 0) {
                # if we are way over the limit, then shorten to the max. Realistically useless
                if ($over -gt $value.value.length) {
                    $over = $value.value.length - 1
                }
                # shorten the part based on calculation
                $value.value = $value.value.substring(0, $value.value.length - $over)
            }
            # increase the current length of the proposed resource name
            $length.value += $value.value.length
        }

        # If we are checking for validations, then shorten each part of the name in order until it fits
        if ($IgnoreValidations.IsPresent -eq $false) {
            $length = 0
            shorten ([ref]$name) ([ref]$length)
            shorten ([ref]$slug) ([ref]$length)
            shorten ([ref]$random) ([ref]$length)
            shorten ([ref]$suffixesstr) ([ref]$length)
            shorten ([ref]$prefixesstr) ([ref]$length)
        }

        # Only add the parts if they have values
        $NameParts = @()
        if (-not [string]::IsNullOrEmpty($prefixesstr)) {
            $NameParts += $prefixesstr
        }
        
        if ($AddResourceAbbreviation -and -not [string]::IsNullOrEmpty($slug)) {
            $NameParts += $slug
        }

        if (-not [string]::IsNullOrEmpty($name)) {
            $NameParts += $name
        }

        if (-not [string]::IsNullOrEmpty($suffixesstr)) {
            $NameParts += $suffixesstr
        }

        # join the parts using the separator
        $name = $NameParts -join $Separator

        # convert the name to lowercase if the resource requires it
        if ($resourceDefinition.lowercase) {
            $name = $name.ToLower()
        }


        # remove any not forbidden characters
        if ($CleanInput) {
            $name = $name -creplace [regex]::Unescape($resourceDefinition.regex.trim('"'))
        }

        # check the proposed name either match the validation regex for the resource type or bypass if the IgnoreValidation switch is enabled
        if ($IgnoreValidations.IsPresent -or $name -cmatch [regex]::Unescape($resourceDefinition.validation_regex.trim('"'))) {
            return $name
        }
        else {
            throw "sorry your resource can't meet the specifications of the resource type $($resourceDefinition.name). Value: $name Pattern: $([regex]::Unescape($resourceDefinition.validation_regex.trim('"'))))"
        }
    }
}
