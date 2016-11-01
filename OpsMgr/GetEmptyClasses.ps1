

## Get all management packs starting with Contoso.
$MPs = Get-SCOMManagementPack -name Contoso*

## For each MP, For each Class, count classinstances.
$Overview = @()
Foreach($MP in $MPs){
    $Classes = $mp.GetClasses()

    foreach($Class in $Classes){
        $ClassInstance = $null
        $ClassInstance = Get-SCClassInstance -Class $class

        ## If you want you can change the number of class instances to sort on.
        if($ClassInstance.Count -le 0){
            $Overview += $Class
        }
    }
}

$Overview | Format-Table Name,Displayname,Managementpack