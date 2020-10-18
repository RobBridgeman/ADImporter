#Credit for original script to Helge Klein https://helgeklein.com.
#Adapted to allow higher numbers of users with the same information set.

# Summary of changes.
# Reduced Male and Female names into one list for ease of expansion
# Changed Displayname code to create each combination of names possible
# Changed sAMAccountname generation to add unique account ID with orgShortName as suffix.


# Known issues
# Usercount (For me anyway) seems to be inaccurate when import completes. May be related to errorcheck compensation when usercount is reduced. Consistently seem to get many more users that intended.


Set-StrictMode -Version 2
$DebugPreference = "SilentlyContinue" # SilentlyContinue | Continue
Import-Module ActiveDirectory

# Set the working directory to the script's directory
Push-Location (Split-Path ($MyInvocation.MyCommand.Path))

#
# Global variables
#
# User properties
$ou = "OU=YourOUHere,DC=AC,DC=Local"         # Which OU to create the user in
$initialPassword = "Password1"               # Initial password set for the user
$orgShortName = "AC"                         # This is used to build a user's sAMAccountName
$dnsDomain = "AC.local"                      # Domain is used for e-mail address and UPN
$company = "AC co"                           # Used for the user object's company attribute
$departments = (                             # Departments and associated job titles to assign to the users
                  @{"Name" = "Finance & Accounting"; Positions = ("Manager", "Accountant", "Data Entry")},
                  @{"Name" = "Human Resources"; Positions = ("Manager", "Administrator", "Officer", "Coordinator")},
                  @{"Name" = "Sales"; Positions = ("Manager", "Representative", "Consultant")},
                  @{"Name" = "Marketing"; Positions = ("Manager", "Coordinator", "Assistant", "Specialist")},
                  @{"Name" = "Engineering"; Positions = ("Manager", "Engineer", "Scientist")},
                  @{"Name" = "Consulting"; Positions = ("Manager", "Consultant")},
                  @{"Name" = "IT"; Positions = ("Manager", "Engineer", "Technician")},
                  @{"Name" = "Planning"; Positions = ("Manager", "Engineer")},
                  @{"Name" = "Contracts"; Positions = ("Manager", "Coordinator", "Clerk")},
                  @{"Name" = "Purchasing"; Positions = ("Manager", "Coordinator", "Clerk", "Purchaser")}
[System.Collections.ArrayList]$phoneCountryCodes = @{"NL" = "+31"; "GB" = "+44"; "DE" = "+49"}         # Country codes for the countries used in the address file

# Other parameters
$userCount = 5000                           # How many users to create
$locationCount = 2                          # How many different offices locations to use counting from 0, where 0 is 1

# Files used
$firstNameFile = "Firstnames.txt"            # Format: FirstName
$lastNameFile = "Lastnames.txt"              # Format: LastName
$addressFile = "Addresses.txt"               # Format: City,Street,State,PostalCode,Country
$postalAreaFile = "PostalAreaCode.txt"       # Format: PostalCode,PhoneAreaCode

# Check locationCount before importing Files else it chokes when it's set too high
if ($locationCount -ge $phoneCountryCodes.Count) {Write-Error ("ERROR: selected locationCount is higher than configured phoneCountryCodes2. You may want to configure $($phoneCountryCodes.Count-1) as max locationCount");continue}

#
# Read input files
#
$firstNames = Import-CSV $firstNameFile -Encoding utf7 # This will remove some "illegal" characters from the names as those characters are not displayed properly (in WS2012R2)
$lastNames = Import-CSV $lastNameFile -Encoding utf7 # This will remove some "illegal" characters from the names as those characters are not displayed properly (in WS2012R2)
$addresses = Import-CSV $addressFile -Encoding utf7 # This will remove some "illegal" characters from the names as those characters are not displayed properly (in WS2012R2)
$postalAreaCodesTemp = Import-CSV $postalAreaFile

# Convert the postal & phone area code object list into a hash
$postalAreaCodes = @{}
foreach ($row in $postalAreaCodesTemp)
{
   $postalAreaCodes[$row.PostalCode] = $row.PhoneAreaCode
}
$postalAreaCodesTemp = $null

#
# Preparation
#
$securePassword = ConvertTo-SecureString -AsPlainText $initialPassword -Force

# Select the configured number of locations from the address list
$locations = @()
$addressIndexesUsed = @()
for ($i = 0; $i -le $locationCount; $i++)
{
   # Determine a random address
   $addressIndex = -1
   do
   {
      $addressIndex = Get-Random -Minimum 0 -Maximum $addresses.Count
   } while ($addressIndexesUsed -contains $addressIndex)

   # Store the address in a location variable
   $street = $addresses[$addressIndex].Street
   $city = $addresses[$addressIndex].City
   $state = $addresses[$addressIndex].State
   $postalCode = $addresses[$addressIndex].PostalCode
   $country = $addresses[$addressIndex].Country
   $locations += @{"Street" = $street; "City" = $city; "State" = $state; "PostalCode" = $postalCode; "Country" = $country}

   # Do not use this address again
   $addressIndexesUsed += $addressIndex
}

# Create the OUs
foreach($dep in $departments) 
{
   New-ADOrganizationalUnit -Name $dep.Name -Path $ou
   "Created ou #" + ($i+1) + ", " + $dep.Name
}

# Create the Groups
foreach($dep in $departments)
{
   $path = "OU=" + $dep.Name + "," + $ou
   foreach($pos in $dep.Positions)
   {
      $groupname = $dep.Name + "_" + $pos
      $description = $pos + " of Department " + $dep.Name
      New-ADGroup -Path $path -Name $groupname -GroupScope Global -Description $description
      "Created group " + $groupname
   }
}

#
# Create the users
#

#
# Randomly determine this user's properties
#

# Create (and overwrite) new array lists [0]
$CSV_Fname = New-Object System.Collections.ArrayList
$CSV_Lname = New-Object System.Collections.ArrayList

#Populate entire $firstNames and $lastNames into the array
$CSV_Fname.Add($firstNames)
$CSV_Lname.Add($lastNames)
   
# Sex & name
$i = 0
if ($i -lt $userCount) 
{
   foreach ($firstname in $firstNames)
   {
       foreach ($lastname in $lastnames)
       {
          $Fname = ($CSV_Fname | Get-Random).FirstName
          $Lname = ($CSV_Lname | Get-Random).LastName

          #Capitalise first letter of each name
          $displayName = (Get-Culture).TextInfo.ToTitleCase($Fname + " " + $Lname)

          # Address
          $locationIndex = Get-Random -Minimum 0 -Maximum $locations.Count
          $street = $locations[$locationIndex].Street
          $city = $locations[$locationIndex].City
          $state = $locations[$locationIndex].State
          $postalCode = $locations[$locationIndex].PostalCode
          $country = $locations[$locationIndex].Country
          $matchcc = $phoneCountryCodes.GetEnumerator() | Where-Object {$_.Name -eq $country} # match the phone country code to the selected country above

          # Department & title
          $departmentIndex = Get-Random -Minimum 0 -Maximum $departments.Count
          $department = $departments[$departmentIndex].Name
          $title = $departments[$departmentIndex].Positions[$(Get-Random -Minimum 0 -Maximum $departments[$departmentIndex].Positions.Count)]

          # Phone number
          if ($matchcc.Name -notcontains $country)
          {
             Write-Debug ("ERROR1: No country code found for $country")
             continue
          }
          if (-not $postalAreaCodes.ContainsKey($postalCode))
          {
             Write-Debug ("ERROR2: No country code found for $country")
             continue
          }
          $officePhone = $matchcc.Value + " " + $postalAreaCodes[$postalCode].Substring(1) + " " + (Get-Random -Minimum 100000 -Maximum 1000000)
   
          # Build the sAMAccountName: $orgShortName + employee number
          $employeeNumber = Get-Random -Minimum 100000 -Maximum 1000000
          $sAMAccountName = $orgShortName + $employeeNumber
          $userExists = $false
          Try   { $userExists = Get-ADUser -LDAPFilter "(sAMAccountName=$sAMAccountName)" }
          Catch { }
          if ($userExists)
          {
             $i=$i-1
             if ($i -lt 0)
             {$i=0}
             continue
          }

          #
          # Create the user account
          #
          $path = "OU=" + $department + "," + $ou
          New-ADUser -SamAccountName $sAMAccountName -Name $displayName -Path $path -AccountPassword $securePassword -Enabled $true -GivenName $Fname -Surname $Lname -DisplayName $displayName -EmailAddress "$Fname.$Lname@$dnsDomain" -StreetAddress $street -City $city -PostalCode $postalCode -State $state -Country $country -UserPrincipalName "$sAMAccountName@$dnsDomain" -Company $company -Department $department -EmployeeNumber $employeeNumber -Title $title -OfficePhone $officePhone
          #
          # Assign user account to group
          #
          $groupname = $department + "_" + $title
          Add-ADGroupMember -Identity $groupname -Members $sAMAccountName

          "Created user #" + ($i+1) + ", $displayName, $sAMAccountName, $title, $department, $officePhone, $country, $street, $city"
          $i = $i+1
          $employeeNumber = $employeeNumber+1

          if ($i -ge $userCount) 
          {
             "Script Complete. Exiting"
             exit
          }
       }
   }
}
