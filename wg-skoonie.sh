#!/bin/bash

##--------------------------------------------------------------------------------------------------
##--------------------------------------------------------------------------------------------------
# 
# This script reads the most recent 
# 

##--------------------------------------------------------------------------------------------------
# ::Global Variables

declare 
declare serverPublicKey
declare networkAddress
declare subnetMaskCidrNotation
declare -a deviceIpAddresses
declare -a devicePublicKeys
declare -a deviceNames
declare -a deviceDescriptions

declare -a deviceIpAddressesSorted

# end of ::Global Variables
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::addDeviceToSkoonieFilesAndGenerateClientConfigruationFile
# 
# Adds a device to the skoonie configuration files
#

addDeviceToSkoonieIniFileAndGenerateClientConfigruationFile() {

	local -n pNetworkValues=$1
	
	# $1	Client device index.
	# $2	Client private key.
	# $3	Client public key.
	# $4	Client IP address.
	# $5	Server public key.
	# $6	Allowed IP addresses from server and peers.
	# $7	Server enpoint. IP address or domain with port (e.g. wg.pushin.com:3666)
	# $8	CIDR for client and server IP addresses.
	# $9	Folder to save to.
	# $10	WireGuard Interface Name.
	deviceClientConfigFilePath=$(generateClientConfigFile "$nextDeviceIndex" "${pNetworkValues["KEY_NEW_DEVICE_PRIVATE_KEY"]}" ""${pNetworkValues["KEY_NEW_DEVICE_PUBLIC_KEY"]}"" "${pNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}" "${pNetworkValues["KEY_SERVER_PUBLIC_KEY"]}" "${pNetworkValues["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]}" "${pNetworkValues["KEY_SERVER_ENDPOINT"]}" "${pNetworkValues["KEY_SUBNET_MASK_CIDR_NOTATION"]}" "/home/hunter/Documents" "${pNetworkValues["KEY_INTERFACE_NAME"]}")
	
	addNewDeviceToSkoonieIniFile "$interfaceSkoonieIniFilePath" "${networkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}" "$publicKey" "$newDeviceName" "$newDeviceDescription"
	
	pNetworkValues["KEY_NEW_DEVICE_CLIENT_CONFIG_FILE_ABS_PATH"]=$(realpath "${deviceClientConfigFilePath}")
	
}
# end of ::addDeviceToSkoonieConfigurationFilesAndGenerateClientConfigruationFile
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::addDeviceToWireGuard
# 
# Attempts to add the new device found in pNetworkDetails to WireGuard.
#
# Parameters:
#
# $1	Reference to associative array key-value pair for network values. Will be modified.
#
# Return:
# 
# Returns 0 upon success; 1 upon failure.
#

addDeviceToWireGuard() {

	local -n pNetworkValues=$1

	# Add device to WireGuard
	addDeviceToWireGuardCmd='wg set '"${pNetworkValues["KEY_INTERFACE_NAME"]}"' peer '"${pNetworkValues["KEY_NEW_DEVICE_PUBLIC_KEY"]}"' allowed-ips "'"${pNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}"'"  2>&1'
	
	
	addDeviceWireGuardOutput=$(eval "${addDeviceToWireGuardCmd}")
	
	listDevicesWireGuard=$(sudo wg)

	echo "$listDevicesWireGuard" | grep -q "${pNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}"
	addToWireGuardWasSuccessful=$?
	
	if [[ ${addToWireGuardWasSuccessful} != "0" ]] ; then
		errorMessage="Failed to add device to WireGuard."
		errorMessage+="\n\r\n\r	Command used:"
		errorMessage+="\n\r\n\r		${addDeviceToWireGuardCmd}"
		errorMessage+="\n\r\n\r	Output message from WireGuard after command: "
		errorMessage+="\n\r\n\r		${addDeviceWireGuardOutput}"
		logErrorMessage	"${errorMessage}"
		return 1
	fi
	
	return 0
	
}
# end of ::addDeviceToWireGuard
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::addNewDeviceToSkoonieIniFile
# 
# Adds a new device to the skoonie ini file for the WireGuard interface.
#
# Parameters:
# $1	File path to skoonie ini file for the WireGuard interface.
# $2	IP address of new device.
# $3	New device public key.
# $4	Name of new device.
# $5	Description of new device.

addNewDeviceToSkoonieIniFile() {

	local pSkoonieIniFilePath=$1
	local pNewIpAddress=$2
	local pNewDevicePublicKey=$3
	local pNewDeviceName=$4
	local pNewDeviceDescription=$5

	cat << EOF >> $pSkoonieIniFilePath

[Device]
IP Address=${pNewIpAddress}
Public Key=${pNewDevicePublicKey}
Name=${pNewDeviceName}
Description=${pNewDeviceDescription}
EOF

}
# end of ::addNewDeviceToSkoonieIniFile
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::addNewDevice
# 
# zzzzzzzzzzzzz

addNewDevice() {

	local pInterfaceName=$1
	local pNewDeviceName=$2
	local pNewDeviceDescription=$3
	
	local interfaceSkoonieIniFilePath="${pInterfaceName}.skoonieini"
	local interfaceSkoonieIniFileAbsolutePath=$(realpath "${interfaceSkoonieIniFilePath}")
	
	local statusGood=0
	
	checkInterfaceValidity "${pInterfaceName}" "${interfaceSkoonieIniFilePath}"
	statusGood=$?
	
	# Return with error if status not good
	if [[ "${statusGood}" -ne 0 ]] ; then
		return 1
	fi
	
	local -A networkValues
	
	# Read existing devices on this interface from file
	readExistingDevicesIniFile "$interfaceSkoonieIniFilePath" networkValues

	# Determine the most recent IP addrress used
	local mostRecentIpAddress="${deviceIpAddressesSorted[-1]}"
	echo "mostRecentIpAddress=${mostRecentIpAddress}"

	initializeNetworkValues "${pInterfaceName}" "${networkValues["KEY_SUBNET_MASK_CIDR_NOTATION"]}" "${networkValues["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]}" "${mostRecentIpAddress}" "${pNewDeviceName}"  "${pNewDeviceDescription}" networkValues
	
	# Check if IP address is allowed
	if [[ "${networkValues["KEY_NEW_DEVICE_IP_ADDRESS_IS_IN_SUBNET"]}" != "1" ]]
	then
		logErrorMessage	"${networkValues["KEY_NEW_DEVICE_IP_ADDRESS_IS_IN_SUBNET_MSG"]}"
		return 1
	fi
	
	# Generate private and public keys for the new device
	networkValues["KEY_NEW_DEVICE_PRIVATE_KEY"]=$(wg genkey)
    networkValues["KEY_NEW_DEVICE_PUBLIC_KEY"]=$(echo "${networkValues["KEY_NEW_DEVICE_PRIVATE_KEY"]}" | wg pubkey)
	
	addDeviceToWireGuard networkValues
	statusGood=$?
	
	# Return with error if status not good
	if [[ "${statusGood}" -ne 0 ]] ; then
		return 1
	fi
	
	addDeviceToSkoonieConfigurationFiles networkValues
	
	local yellowFontColor="\033[33m"
	local resetColors="\033[0m"
	
	logDeviceAddedSuccessfullyMessage networkValues
	
}
# end of ::addNewDevice
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::checkInterfaceValidity
# 
# Determines if pInterfaceName is a valid interface in both WireGuard and the Skoonie WireGuard 
# wrapper. Errors will be logged if it is not valid.
#
# Parameters:
#
# $1	Interface name to check for.
# $2	File path to interface skoonieini configuration file.
#
# Return:
#
# true if interface is valid in both WireGuard and Skoonie WireGuard wrapper; false otherwise.
#

checkInterfaceValidity() {

	local pInterfaceName=$1
	local pInterfaceSkoonieIniFilePath=$2
	
	local interfaceSkoonieIniFileAbsolutePath=$(realpath "${pInterfaceSkoonieIniFilePath}")
	
	statusGood=0

	wg show "${pInterfaceName}" &> /dev/null
	local interfaceExistsInWireGuard=$?

	[ -e "${pInterfaceSkoonieIniFilePath}" ]
	local interfaceSkoonieIniFileExists=$?

	if [[ $interfaceExistsInWireGuard -ne 0 && $interfaceSkoonieIniFileExists -ne 0 ]]; then
		local errorMsg=""
		errorMsg+="Interface '${pInterfaceName}' cannot be found in WireGuard and the wg-skoonie skoonieini configuration file cannot be found."
		errorMsg+="\n\r"
		errorMsg+="\n\r	File path  used for skoonieini configruation file:"
		errorMsg+="\n\r"
		errorMsg+="\n\r		${interfaceSkoonieIniFileAbsolutePath}"
		logErrorMessage "${errorMsg}"
		statusGood=1
	elif [[ $interfaceExistsInWireGuard -ne 0 ]]; then
		logErrorMessage "Interface '${pInterfaceName}' cannot be found in WireGuard."
		statusGood=1
	elif [[ $interfaceSkoonieIniFileExists -ne 0 ]]; then
		local errorMsg=""
		errorMsg+="The wg-skoonie skoonieini configuration file cannot be found for interface '${pInterfaceName}'."
		errorMsg+="\n\r"
		errorMsg+="\n\r	File path expected for skoonieini configruation file:"
		errorMsg+="\n\r"
		errorMsg+="\n\r		${interfaceSkoonieIniFileAbsolutePath}"
		logErrorMessage "${errorMsg}"
		statusGood=1
	fi
	
	return "${statusGood}"
	
}
# end of ::checkInterfaceValidity
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::convertIpAddressDottedDecimalToInteger
# 
# Converts the passed in IP address represented by the conventional dottted-decimal format to an
# integer.
#
# For example, 255.255.255.0 is converted to 4294967040.
#
# Parameters:
#
# $1	IP address represented by the conventional dottted-decimal format.
#
# Return:
#
# Returns the IP address represented as an integer.
#

convertIpAddressDottedDecimalToInteger() {

    local ipAddressAsDottedDecimal="$1"
	
	local octets

	IFS='.' read -r -a octets <<< "$ipAddressAsDottedDecimal"

	resultsInteger=$(( (${octets[0]} << 24) | (${octets[1]} << 16) | (${octets[2]} << 8) | (${octets[3]}) ))

	echo $resultsInteger
   
}
# end of ::convertIpAddressDottedDecimalToInteger
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::convertIpAddressIntegerToPadded32BitBinaryString
# 
# Converts the passed in IP address represented by an integer to binary format in a string. The 
# binary expression is padded with 0s to be a full 32 bits.
#
# For example:
# 	4294967040 	converted to	11111111111111111111111100000000
# 	184549120	converted to	00001010111111111111111100000000
#
# Parameters:
#
# $1	IP address represented as an integer.
#
# Return:
#
# Returns the IP address represented as a 32-bit binary value in a string.
#

convertIpAddressIntegerToPadded32BitBinaryString() {

    local ipAddressAsInteger="$1"

	# Desired width of the binary number with padding
	local width=32

	# Create string with thirty-two 0s
	local zerosPadding=$(printf '%0*d' $width)

	binary=$(echo "obase=2; $ipAddressAsInteger" | bc)
	
	binaryWithPadding=$(echo "${zerosPadding:0:$width-${#binary}}$binary")
	
	echo $binaryWithPadding
   
}
# end of ::convertIpAddressIntegerToPaddedBinaryString
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::convertIpAddressIntegerToDottedDecimalString
# 
# Converts the passed in IP address represented by an integer to the conventional dottted-decimal
# string.
#
# For example, 4294967040 is converted to 255.255.255.0.
#
# Parameters:
#
# $1	IP address represented as an integer.
#
# Return:
#
# Returns the IP address represented as the conventional dottted-decimal format in a string.
#

convertIpAddressIntegerToDottedDecimalString() {

    local ipAddressAsInteger="$1"

	local -a stringArray

	for (( i=0; i<=3; i++ )); do

		local bitshift=$(( ${i} * 8 ))

		local octet=$(( (ipAddressAsInteger >> ${bitshift}) & 0xFF ))
		
		stringArray+=("${octet}")
		
	done
   
	resultsString="${stringArray[3]}.${stringArray[2]}.${stringArray[1]}.${stringArray[0]}"

	echo $resultsString
   
}
# end of ::convertIpAddressIntegerToDottedDecimalString
##--------------------------------------------------------------------------------------------------

#---------------------------------------------------------------------------------------------------
# ::convertSubnetMaskCidrToSubnetMaskDottedDecimal
# 
# Converts the passed in subnet mask in CIDR notation to the equivalent subnet mask in 
# dotted-decimal notation.
#
# For example:
#	IP Address & CIDR	CIDR	Subnet Mask		IP Addresses Ranges
#	10.255.255.0/24		24		255.255.255.0	10.255.255.0 to 10.255.255.255
#	10.255.255.0/22		24		255.255.252.0	10.255.252.0 to 10.255.255.255
#
#	Note that IP addresses 10.255.255.0 (lowest) and 10.255.255.255 (highest) values are typically
#	reserved for special functions.
#
# Parameters:
#
# $1	Subnet mask in CIDR notation to convert to the equivalent subnet mask in dotted-decimal 
#		notation.
#
# Return:
#
# Returns the dotted-decimal subnet mask derived from the passed in CIDR dotted-decimal.
#

convertCidrToSubnetMask() {

    local cidr="$1"

    # Calculate the number of network bits
    local network_bits=$(( 32 - cidr ))

    # Create a bitmask with the leftmost n bits set to 1
    local bitmask=$(( (1 << network_bits) - 1 ))

    # Convert the bitmask to dotted-decimal notation
    local octet1=$(( bitmask >> 24 & 255 ))
    local octet2=$(( bitmask >> 16 & 255 ))
    local octet3=$(( bitmask >> 8 & 255 ))
    local octet4=$(( bitmask & 255 ))

    # Print the subnet mask
    echo "$(( 255 - octet1 )).$(( 255 - octet2 )).$(( 255 - octet3 )).$(( 255 - octet4 ))"
	
}
# end of ::convertCidrToSubnetMask
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::determineIpAddressForNewDevice
# 
# Determines the next consecutive IP address after the most recent IP address.
#
# For example, if the most recent IP address is 10.8.8.1, the next IP address is 10.8.8.2.
#
# The next IP address is saved in integer value format, binary value with padding format, and 
# dotted-decimal format in the passed in array.
#
# Whether or not the next IP address is a valid IP address within the subnet is also saved in the
# passed in array.
#
# Parameters:
#
# $1	Reference to associative array key-value pair for network values. Will be modified.
#
# Return:
#
# All initialized values are stored in the passed networkValues array as key-value pairs. 
#
# Key-value pairs stored:
#
# KEY_NEW_DEVICE_IP_ADDRESS_INTEGER								next consecutive IP address integer format
# KEY_NEW_DEVICE_IP_ADDRESS_BINARY_WITH_PADDING					next consecutive IP address binary with padding format
# KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL						next consecutive IP address dotted-decimal format
#
# KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_INTEGER				base address of next consecutive IP address integer format
# KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_BINARY_WITH_PADDING	base address of next consecutive IP address binary with padding format
# KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_DOTTED_DECIMAL			base address of next consecutive IP address dotted-decimal format
#
# KEY_NEW_DEVICE_IP_ADDRESS_IS_IN_SUBNET						0 if NOT in subnet or if equal to network address or broadcast address.
#																1 if in subnet.
#
# KEY_NEW_DEVICE_IP_ADDRESS_IS_IN_SUBNET_MSG					Descriptive message about whether or not the next IP address is in the subnet.
#

determineIpAddressForNewDevice() {

	local -n ppNetworkValues=$1

	ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_INTEGER"]="$(( ${ppNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_INTEGER"]}+1 ))"
	ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_INTEGER"]}")"
	ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_INTEGER"]}")"
	
	ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_INTEGER"]="$(( ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_INTEGER"] & ppNetworkValues["KEY_SUBNET_MASK_INTEGER"] ))"
	ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_INTEGER"]}")"
	ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_INTEGER"]}")"
	
	local isInSubnet
	local msg
	
	if [[ "${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_INTEGER"]}" -eq "${ppNetworkValues["KEY_NETWORK_ADDRESS_INTEGER"]}" ]]
	then
		
		isInSubnet="0"
		msg="Next IP address ${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]} is INVALID because it is equal to the network address."

	elif [[ "${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_INTEGER"]}" -eq "${pppNetworkValues["KEY_BROADCAST_ADDRESS_INTEGER"]}" ]]
	then

		isInSubnet="0"
		msg="Next IP address ${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]} is INVALID because it is equal to the broadcast address."

	elif [[ "${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_INTEGER"]}" -eq "${ppNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_INTEGER"]}" ]]
	then

		isInSubnet="1"
		msg="Next IP address ${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]} is VALID because it is within the subnet and not equal to the network address or the broadcast address."
			
	else
	
		isInSubnet="0"
		msg="Next IP address ${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]} is INVALID because it is not within the subnet."
		
	fi
	
	ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_IS_IN_SUBNET"]="${isInSubnet}"
	ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_IS_IN_SUBNET_MSG"]="${msg}"
	
}
# end of ::determineIpAddressForNewDevice
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateClientConfigFile
# 
# Generates the client configuration file using the passed in parameters.
#
# Upon return, the client configuration file will be saved to:
# 	[Folder]/[WireGuard Interface Name]/device[Device index]/[WireGuard Interface Name].conf
# 
# For example:
#	/etc/wireguard/pickwick/device0/pickwick.conf
#
# Parameters:
#
# $1	Client device index.
# $2	Client private key.
# $3	Client public key.
# $4	Client IP address.
# $5	Server public key.
# $6	Allowed IP addresses from server and peers.
# $7	Server enpoint. IP address or domain with port (e.g. wg.pushin.com:3666)
# $8	Subnet mask in CIDR notation for client and server IP addresses.
# $9	Folder to save to.
# $10	WireGuard Interface Name.
#
# Return:
#
# The file path to the client configuration file.
#


generateClientConfigFile() {

    local clientDeviceIndex=$1
	local clientPrivateKey=$2
	local clientPublicKey=$3
	local clientIpAddress=$4
	
	local serverPublicKey=$5
	local allowedIps=$6
	local serverEndpoint=$7
	
	local subnetMaskCidrNotation=$8
	
	local folder=$9
	local wireguardInterfaceName=${10}
	
	local folderPath="$folder/$wireguardInterfaceName/device$clientDeviceIndex"
	local filePath="$folderPath/$wireguardInterfaceName.conf"
	
	mkdir -p "$folderPath"
	
	cat > "$filePath" <<EOF
[Interface]
PrivateKey = $clientPrivateKey
Address = $clientIpAddress/$subnetMaskCidrNotation

[Peer]
PublicKey = $serverPublicKey
Endpoint = $serverEndpoint
AllowedIPs = $allowedIps/$subnetMaskCidrNotation
EOF

	echo "$filePath"

}
# end of ::generateClientConfigFile
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::initializeNetworkValues
# 
# Initializes network values based on passed in parameters. All initialized values are stored in
# the passed networkValues array as key-value pairs.
#
# Parameters:
#
# $1	Interface name.
# $2	Subnet mask in CIDR notation format.
# $3	Network address in dotted-decimal format.
# $4	Most recently saved IP address in dotted-decimal format.
# $5	Name of new device to be added.
# $6	Description of new device to be added.
# $7	Reference to associative array key-value pair for network values. Will be modified.
#
# Return:
#
# All initialized values are stored in the passed networkValues array as key-value pairs. 
#

initializeNetworkValues() {

	local pInterfaceName=$1
	local pSubnetMaskAsCidrNotation=$2
	local pNetworkAddressAsDottedDecimalString=$3
    local pMostRecentIpAddressAsDottedDecimalString=$4
	local pNewDeviceName=$5
	local pNewDeviceDescription=$6
	local -n pNetworkValues=$7
	
	#//DEBUG HSS//
	echo "pInterfaceName=${pInterfaceName}"
	echo "pSubnetMaskAsCidrNotation=${pSubnetMaskAsCidrNotation}"
	echo "pNetworkAddressAsDottedDecimalString=${pNetworkAddressAsDottedDecimalString}"
	echo "pMostRecentIpAddressAsDottedDecimalString=${pMostRecentIpAddressAsDottedDecimalString}"
	echo "pNewDeviceName=${pNewDeviceName}"
	echo "pNewDeviceDescription=${pNewDeviceDescription}"
	#//DEBUG HSS//
	
	# Get subnet mask from CIDR read in from ini file
	local subnetMaskAsDottedDecimalNotation=$(convertCidrToSubnetMask "$subnetMaskCidrNotation")
	
	pNetworkValues["KEY_INTERFACE_NAME"]="${pInterfaceName}"

	pNetworkValues["KEY_SUBNET_MASK_INTEGER"]="$(convertIpAddressDottedDecimalToInteger "${subnetMaskAsDottedDecimalNotation}")"
	pNetworkValues["KEY_SUBNET_MASK_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${pNetworkValues["KEY_SUBNET_MASK_INTEGER"]}")"
	pNetworkValues["KEY_SUBNET_MASK_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${pNetworkValues["KEY_SUBNET_MASK_INTEGER"]}")"
	
	pNetworkValues["KEY_INVERTED_SUBNET_MASK_INTEGER"]="$(( ~(${pNetworkValues["KEY_SUBNET_MASK_INTEGER"]}) & 0xFFFFFFFF ))"
	pNetworkValues["KEY_INVERTED_SUBNET_MASK_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${pNetworkValues["KEY_INVERTED_SUBNET_MASK_INTEGER"]}")"
	pNetworkValues["KEY_INVERTED_SUBNET_MASK_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${pNetworkValues["KEY_INVERTED_SUBNET_MASK_INTEGER"]}")"
	
	pNetworkValues["KEY_NETWORK_ADDRESS_INTEGER"]="$(convertIpAddressDottedDecimalToInteger "${pNetworkAddressAsDottedDecimalString}")"
	pNetworkValues["KEY_NETWORK_ADDRESS_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${pNetworkValues["KEY_NETWORK_ADDRESS_INTEGER"]}")"
	pNetworkValues["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${pNetworkValues["KEY_NETWORK_ADDRESS_INTEGER"]}")"
	
	pNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_INTEGER"]="$(( pNetworkValues["KEY_NETWORK_ADDRESS_INTEGER"] & pNetworkValues["KEY_SUBNET_MASK_INTEGER"] ))"
	pNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${pNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_INTEGER"]}")"
	pNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${pNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_INTEGER"]}")"
	
	pNetworkValues["KEY_BROADCAST_ADDRESS_INTEGER"]="$(( ${pNetworkValues["KEY_NETWORK_ADDRESS_INTEGER"]} | ${pNetworkValues["KEY_INVERTED_SUBNET_MASK_INTEGER"]} ))"
	pNetworkValues["KEY_BROADCAST_ADDRESS_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${pNetworkValues["KEY_BROADCAST_ADDRESS_INTEGER"]}")"
	pNetworkValues["KEY_BROADCAST_ADDRESS_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${pNetworkValues["KEY_BROADCAST_ADDRESS_INTEGER"]}")"
	
	pNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_INTEGER"]="$(convertIpAddressDottedDecimalToInteger "${pMostRecentIpAddressAsDottedDecimalString}")"
	pNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${pNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_INTEGER"]}")"
	pNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${pNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_INTEGER"]}")"
	
	pNetworkValues["KEY_NEW_DEVICE_NAME"]="${pNewDeviceName}"
	pNetworkValues["KEY_NEW_DEVICE_DESC"]="${pNewDeviceDescription}"
	
	determineIpAddressForNewDevice pNetworkValues
	
	outputNetworkValuesToConsole pNetworkValues
	
}
# end of ::initializeNetworkValues
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::logErrorMessage
# 
# Log error message telling user that device was not added.
#

logErrorMessage() {

	local errorMessage=$1
	
	local redBackground="\033[41m"
	local resetColors="\033[0m"

	local output=""
	
	output+="${redBackground}"
	output+="\n\r"
	output+="	!! ERROR !! start"
	output+="${resetColors}"
	output+="\n\r"
	output+="\n\r	Device was not added. Please see below for more details."
	output+="\n\r"
	output+="\n\r	${errorMessage}"
	output+="\n\r"
	output+="${redBackground}"
	output+="\n\r"
	output+="	!! ERROR !! end"
	output+="${resetColors}"
	output+="\n\r"
	output+="\n\r"
	
	printf "${output}"
}
# end of ::logErrorMessage
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::logDeviceAddedSuccessfullyMessage
# 
# Logs success message telling user that device was successfully added.
#
# Parameters:
#
# $1	Reference to network values containing information that can be used in the message.
#

logDeviceAddedSuccessfullyMessage() {

	local -n pNetworkValues=$1
	
	local greenBackground="\033[30;42m"
	local resetColors="\033[0m"

	local msg=""
	
	msg+="${greenBackground}"
	msg+="\n\r"
	msg+="	!! SUCCESS !! start"
	msg+="${resetColors}"
	msg+="\n\r"
	msg+="\n\r	Device was successfully added to WireGuard interface '${pNetworkValues["KEY_INTERFACE_NAME"]}'."
	msg+="\n\r"
	msg+="\n\r"
	msg+="	Device IP Address	${networkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}"
	msg+="\r\n"
	msg+="	Device Public Key	${pNetworkValues["KEY_NEW_DEVICE_PUBLIC_KEY"]}"
	msg+="\r\n"
	msg+="	Device Name		${pNetworkValues["KEY_NEW_DEVICE_NAME"]}"
	msg+="\r\n"
	msg+="	Device Description	${pNetworkValues["KEY_NEW_DEVICE_DESC"]}"
	msg+="\r\n"
	msg+="\r\n"
	msg+="	The tunnel configuration file for the newly added device has been saved to the following location:"
	msg+="\r\n"
	msg+="\r\n"
	msg+="		${yellowFontColor}${pNetworkValues["KEY_NEW_DEVICE_CLIENT_CONFIG_FILE_ABS_PATH"]}${resetColors}"
	msg+="\r\n"
	msg+="\r\n"
	msg+="	The configuration file can be imported into a client's WireGuard service to add a tunnel to the interface."
	msg+="\r\n"
	msg+="\r\n	Since it contains the client's private key, it is not recommended to keep the file on this machine"
	msg+="\r\n	after it has been added the client; storing the private key for a WireGuard peer in multiple"
	msg+="\r\n	locations can be a security risk."
	msg+="\r\n"
	msg+="\n\r"
	msg+="${greenBackground}"
	msg+="\n\r"
	msg+="	!! SUCCESS !! end"
	msg+="${resetColors}"
	msg+="\n\r"
	msg+="\n\r"
	
	printf "${msg}"
	
}
# end of ::logDeviceAddedSuccessfullyMessage
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::outputNetworkValuesToConsole
# 
# Outputs the network values to the console in a user-friendly format.
#
# Parameters:
#
# $1	Reference to associative array key-value pair for network values.
#
# Return:
#
# Network values are output to the console in a user-friendly format. 
#

outputNetworkValuesToConsole() {

	local -n ppNetworkValues=$1

	subnetMaskInteger="${ppNetworkValues["KEY_SUBNET_MASK_INTEGER"]}"
	subnetMaskBinaryWithPadding="${ppNetworkValues["KEY_SUBNET_MASK_BINARY_WITH_PADDING"]}"
	subnetMaskDottedDecimal="${ppNetworkValues["KEY_SUBNET_MASK_DOTTED_DECIMAL"]}"

	invertedSubnetMaskInteger="${ppNetworkValues["KEY_INVERTED_SUBNET_MASK_INTEGER"]}"
	invertedSubnetMaskBinaryWithPadding="${ppNetworkValues["KEY_INVERTED_SUBNET_MASK_BINARY_WITH_PADDING"]}"
	invertedSubnetMaskDottedDecimal="${ppNetworkValues["KEY_INVERTED_SUBNET_MASK_DOTTED_DECIMAL"]}"

	networkAddressInteger="${ppNetworkValues["KEY_NETWORK_ADDRESS_INTEGER"]}"
	networkAddressBinaryWithPadding="${ppNetworkValues["KEY_NETWORK_ADDRESS_BINARY_WITH_PADDING"]}"
	networkAddressDottedDecimal="${ppNetworkValues["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]}"

	networkAddressBaseAddressInteger="${ppNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_INTEGER"]}"
	networkAddressBaseAddressBinaryWithPadding="${ppNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_BINARY_WITH_PADDING"]}"
	networkAddressBaseAddressDottedDecimal="${ppNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_DOTTED_DECIMAL"]}"

	broadcastAddressInteger="${ppNetworkValues["KEY_BROADCAST_ADDRESS_INTEGER"]}"
	broadcastAddressBinaryWithPadding="${ppNetworkValues["KEY_BROADCAST_ADDRESS_BINARY_WITH_PADDING"]}"
	broadcastAddressDottedDecimal="${ppNetworkValues["KEY_BROADCAST_ADDRESS_DOTTED_DECIMAL"]}"

	ipAddressInteger="${ppNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_INTEGER"]}"
	ipAddressBinaryWithPadding="${ppNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_BINARY_WITH_PADDING"]}"
	ipAddressDottedDecimal="${ppNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_DOTTED_DECIMAL"]}"

	nextIpAddressInteger="${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_INTEGER"]}"
	nextIpAddressBinaryWithPadding="${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_BINARY_WITH_PADDING"]}"
	nextIpAddressDottedDecimal="${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}"

	nextIpAddressBaseAddressInteger="${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_DOTTED_DECIMAL"]}"
	nextIpAddressBaseAddressBinaryWithPadding="${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_BINARY_WITH_PADDING"]}"
	nextIpAddressBaseAddressDottedDecimal="${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_DOTTED_DECIMAL"]}"
	

	echo ""
	echo ""
	echo ""
	
	echo "Network Values According to Skoonie Configuration Files:"
	
	echo ""

	echo "${subnetMaskDottedDecimal}	${subnetMaskBinaryWithPadding}	Subnet Mask"

	echo "		||||||||||||||||||||||||||||||||"

	echo "${invertedSubnetMaskDottedDecimal}	${invertedSubnetMaskBinaryWithPadding}	Subnet Mask Inverted"

	echo "		||||||||||||||||||||||||||||||||"

	echo "${networkAddressDottedDecimal}	${networkAddressBinaryWithPadding}	Network Address"

	echo "		||||||||||||||||||||||||||||||||"

	echo "${networkAddressBaseAddressDottedDecimal}	${networkAddressBaseAddressBinaryWithPadding}	Network Address Base Address"

	echo "		||||||||||||||||||||||||||||||||"

	echo "${broadcastAddressDottedDecimal}	${broadcastAddressBinaryWithPadding}	Broadcast Address"

	echo "		||||||||||||||||||||||||||||||||"

	echo "${ipAddressDottedDecimal}	${ipAddressBinaryWithPadding}	Previous IP Address"

	echo "		||||||||||||||||||||||||||||||||"

	echo "${nextIpAddressDottedDecimal}	${nextIpAddressBinaryWithPadding}	Next IP Address"

	echo "		||||||||||||||||||||||||||||||||"

	echo "${nextIpAddressBaseAddressDottedDecimal}	${nextIpAddressBaseAddressBinaryWithPadding}	Next IP Address Base Address"

	echo ""
	echo ""
	echo ""
	
}
# end of ::outputNetworkValuesToConsole
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::readExistingDevicesIniFile
# 
# Reads in the previously assigned IP addresses from the [network interface name]-assignedIPs.ini
# file.
#
# Parameter 1: 	File path to ini file containing previously assigned IP addresses.
#zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
#
# On Return:	All keys read from the ini file will be stored in global array $ipAddressesKeys.
#				All values read from the ini file will be stored in global array $ipAddressesKeys.
#

readExistingDevicesIniFile() {
	
	local pFilePath=$1
	local -n pNetworkValues=$2

	# Read in all key-value pairs in the file
	if [ -f "${pFilePath}" ]; then
		while IFS='=' read -r key value; do
		
			if [[ ! "$key" =~ ^[[:space:]]*$ && ! "$key" =~ ^# && ! "$key" =~ ^\[ ]]; then
			
				case "$key" in
				
					"Server Public Key")
						pNetworkValues["KEY_SERVER_PUBLIC_KEY"]="${value}"
						;;
					
					"Server Endpoint")
						pNetworkValues["KEY_SERVER_ENDPOINT"]="${value}"
						;;
				
					"Network Address")
						pNetworkValues["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]="${value}"
						;;
				
					"Subnet Mask CIDR Notation")
						pNetworkValues["KEY_SUBNET_MASK_CIDR_NOTATION"]="${value}"
						;;
				
					"IP Address")
						deviceIpAddresses+=("$value")
						;;
						
					"Public Key")
						devicePublicKeys+=("$value")
						;;
						
					"Name")
						deviceNames+=("$value")
						;;
						
					"Description")
						deviceDescriptions+=("$value")
						;;
				
				esac

			fi
			
		done < "$pFilePath"
	fi
	
	# Sort the IP addresses in ascending order
    deviceIpAddressesSorted=($(printf "%s\n" "${deviceIpAddresses[@]}" | sort -V))
	
}
# end of ::readExistingDevicesIniFile
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::handleUserCommand
# 
# Converts the passed in IP address in dotted-decimal notation (like 192.168.1.1) into its decimal 
# equivalent.
#
# Parameters:
#
# $1	IP address string in dotted-decimal notation (like 192.168.1.1).
#
# Return:
#
# Returns the 32-bit integer form of the IP address.
#

case "$1" in
			
	"-add-device")
		addNewDevice $2 $3 $4
		;;

esac

# end of ::handleUserCommand
##--------------------------------------------------------------------------------------------------