Connect-VIServer YOURVCENTER
$devices = Get-VMHost ONEOFYOURHOST | Get-VMHostPciDevice | where { $_.DeviceClass -eq "MassStorageController" -or $_.DeviceClass -eq "NetworkController" -or $_.DeviceClass -eq "SerialBusController"} 

$hcl = Invoke-WebRequest -Uri http://www.virten.net/repo/vmware-iohcl.json | ConvertFrom-Json
$AllInfo = @()
Foreach ($device in $devices) {

  # Ignore USB Controller
  if ($device.DeviceName -like "*USB*" -or $device.DeviceName -like "*iLO*" -or $device.DeviceName -like "*iDRAC*") {
    continue
  }

  $DeviceFound = $false
  $Info = "" | Select VMHost, Device, DeviceName, VendorName, DeviceClass, vid, did, svid, ssid, Driver, DriverVersion, FirmwareVersion, VibVersion, Supported, Reference
  $Info.VMHost = $device.VMHost
  $Info.DeviceName = $device.DeviceName
  $Info.VendorName = $device.VendorName
  $Info.DeviceClass = $device.DeviceClass
  $Info.vid = [String]::Format("{0:x}", $device.VendorId)
  $Info.did = [String]::Format("{0:x}", $device.DeviceId)
  $Info.svid = [String]::Format("{0:x}", $device.SubVendorId)
  $Info.ssid = [String]::Format("{0:x}", $device.SubDeviceId)

  if ($device.DeviceClass -eq "NetworkController"){
    # Get NIC list to identify vmnicX from PCI slot Id
    $esxcli = $device.VMHost | Get-EsxCli -V2
    $niclist = $esxcli.network.nic.list.Invoke();
    $vmnicId = $niclist | where { $_.PCIDevice -like '*'+$device.Id}
    $Info.Device = $vmnicId.Name
    
    # Get NIC driver and firmware information
    $vmnicDetail = $esxcli.network.nic.get.Invoke(@{nicname = $vmnicId.Name})
    $Info.Driver = $vmnicDetail.DriverInfo.Driver
    $Info.DriverVersion = $vmnicDetail.DriverInfo.Version
    $Info.FirmwareVersion = $vmnicDetail.DriverInfo.FirmwareVersion

    # Get driver vib package version
    Try{
      $driverVib = $esxcli.software.vib.get.Invoke(@{vibname = "net-"+$vmnicDetail.DriverInfo.Driver})
    }Catch{
      $driverVib = $esxcli.software.vib.get.Invoke(@{vibname = $vmnicDetail.DriverInfo.Driver})
    }
    $Info.VibVersion = $driverVib.Version


  } elseif ($device.DeviceClass -eq "MassStorageController" -or $device.DeviceClass -eq "SerialBusController"){
    # Identify HBA (FC or Local Storage) with PCI slot Id
    $vmhbaId = $device.VMHost |Get-VMHostHba | where { $_.PCI -like '*'+$device.Id} 
    $Info.Device = $vmhbaId.Device
    $Info.Driver = $vmhbaId.Driver

    # Get driver vib package version
    Try{
      $driverVib = $esxcli.software.vib.get.Invoke(@{vibname = "scsi-"+$vmhbaId.Driver})
    }Catch{
      $driverVib = $esxcli.software.vib.get.Invoke(@{vibname = $vmhbaId.Driver})
    }
    $Info.VibVersion = $driverVib.Version
  }

  # Search HCL entry with PCI IDs VID, DID, SVID and SSID
  Foreach ($entry in $hcl.data.ioDevices) {
    If (($Info.vid -eq $entry.vid) -and ($Info.did -eq $entry.did) -and ($Info.svid -eq $entry.svid) -and ($Info.ssid -eq $entry.ssid)) {
      $Info.Reference = $entry.url
      $DeviceFound = $true
    }
  }

  $Info.Supported = $DeviceFound
  $AllInfo += $Info
}

# Display all Infos
#$AllInfo

# Display ESXi, DeviceName and supported state
#$AllInfo |select VMHost,Device,DeviceName,Supported,Referece |ft -AutoSize

# Display device, driver and firmware information
#$AllInfo |select VMHost,Device,DeviceName,Supported,Driver,DriverVersion,FirmwareVersion,VibVersion |ft -AutoSize

# Expor to CSV
$AllInfo |Export-Csv -NoTypeInformation c:\temp\deviceList.csv