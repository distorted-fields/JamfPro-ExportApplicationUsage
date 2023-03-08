#!/bin/zsh
#
#
#
#           Created by A.Hodgson                     
#            Date: 2023-03-07
#            Purpose: This script uses the api to gather all serial numbers or those from an adv computer search and then gathers application usage data.
#			
#			****IMPORTANT*****
#				This script requires jq to be installed for data parsing, download here - https://stedolan.github.io/jq/download/ or install with homebrew "brew install jq"
#
############################################################
# User Variables 
#############################################################
api_user=""
api_pass=""
jamf_url="" # include port number if on prem but with no trailing slash
group_id="" # A Jamf Pro Advanced Search that contains the clients for which you want a report, leave blank to report on all computers
start_date="" # select a start date YYYY-MM-DD 
app_name="" # App name or vendor in question, leave blank to collect all apps
#############################################################
end_date=$(date +"%Y-%m-%d") # todays date
csv_export="/tmp/app_usage_export.csv" 
headers="Date,Device Name,Serial Number,App Name,Minutes in Forground" #if you change the order, also change line 123
#######################################
# build the api path to the advanced search, or all computers
if [ -z "$group_id" ]; then
	api_path="JSSResource/computers/subset/basic"
else
	api_path="JSSResource/advancedcomputersearches/id/${group_id}"
fi
#############################################################
# create a fresh export file
if [ -e $csv_export ]; then
	rm -f $csv_export
fi
#touch the temp export file
touch $csv_export
#write the header values of each column
echo "$headers" > $csv_export
#############################################################
# Functions
#############################################################
function apiResponse(){
    HTTP_Status=$1
    if [ $HTTP_Status -eq 200 ] || [ $HTTP_Status -eq 201 ]; then echo "Success."
    elif [ $HTTP_Status -eq 400 ]; then echo "400 Failure - Bad request. Verify the syntax of the request specifically the XML body."
    elif [ $HTTP_Status -eq 401 ]; then echo "401 Failure - Authentication failed. Verify the credentials being used for the request."
    elif [ $HTTP_Status -eq 403 ]; then echo "403 Failure - Invalid permissions. Verify the account being used has the proper permissions for the object/resource you are trying to access."
    elif [ $HTTP_Status -eq 404 ]; then echo "404 Failure - Object/resource not found. Verify the URL path is correct."
    elif [ $HTTP_Status -eq 409 ]; then echo "409 Failure - Conflict, check XML data"
    elif [ $HTTP_Status -eq 500 ]; then echo "500 Failure - Internal server error. Retry the request or contact Jamf support if the error is persistent."
    fi
    echo ""
    echo ""
}

function generateAuthToken(){
	echo ""
	echo "Generating authorization token..."
	# generate an auth token
	auth_response=$(curl --write-out "%{http_code}" -sku "$api_user":"$api_pass" "${jamf_url}/api/v1/auth/token" --header 'Accept: application/json' -X POST)
	responseStatus=${auth_response: -3}
	auth_response=$(echo  ${auth_response/%???/})

	if [ $responseStatus -eq 200 ]; then
		# parse authToken for token, omit expiration
		token=$(echo "$auth_response" | plutil -extract token raw -)
		echo "Success."
		echo ""
		echo ""
	else
		echo "Authentication failed. Verify the credentials being used for the request."
		exit 1
	fi
}
#############################################################
# MAIN
#############################################################
generateAuthToken

echo "Getting a list of devices in Jamf Pro..."
api_response=$(curl --write-out "%{http_code}" -sk -H "Authorization: Bearer $token" -H "Accept: application/json" "${jamf_url}/${api_path}" -X GET)
responseStatus=${api_response: -3}
# test that we got a successful api response or output error
if [ $responseStatus -eq 200 ] || [ $responseStatus -eq 201 ]; then 
	# trim the api response code off the response
	api_response=$( echo ${api_response/%???/})
	# get all target serial numbers
	if [ -z "$group_id" ]; then
		serialnumbers=$(echo "$api_response" | jq -r '.computers[].serial_number')
	else
		serialnumbers=$(echo "$api_response" | jq -r '.advanced_computer_search.computers[].Serial_Number')
	fi

	# loop through once for each serial number in the array, pull the app usage via API, parse, and output to the .csv
	while IFS= read -r serial; do
	
		if [ -z "$group_id" ]; then
			devicename=$(echo $api_response | jq '.computers[] | select(.serial_number == "'$serial'") | .name')
		else
			devicename=$(echo $api_response | jq '.advanced_computer_search.computers[] | select(.Serial_Number == "'$serial'") | .name')
		fi

		echo "Device Info: ${devicename} - ${serial}"
		echo "Requesting application usage logs for ${serial}..."  
		# Get the app usage for current device in the date range
		app_usage_response=$(curl --write-out "%{http_code}" -sk -H "Authorization: Bearer $token" -H "Accept: application/json" "$jamf_url/JSSResource/computerapplicationusage/serialnumber/$serial/${start_date}_${end_date}" -X GET)
		responseStatus=${app_usage_response: -3}
		# check for successful api response
		if [ $responseStatus -eq 200 ] || [ $responseStatus -eq 201 ]; then 
			app_usage_response=$( echo ${app_usage_response/%???/})
			dates=$(echo $app_usage_response | jq -r '.computer_application_usage[].date')
			# parse the date outputs and gather the apps and time in foregroun
			while IFS= read -r date; do
				
				app_usage=$(echo $app_usage_response | jq -r '.computer_application_usage[] | select(.date == "'"$date"'") | .apps[] | {name, foreground} | join(",")')
				# append only target app data
				while IFS= read -r current_app; do
					if [[ "$current_app" == *"$app_name"* ]]; then
						app=$(echo "$current_app" | cut -d "," -f1)
						foreground=$(echo "$current_app" | cut -d ',' -f2)
						echo "$date,$devicename,$serial,$app,$foreground" >> $csv_export
					fi
				done <<< "$app_usage"
			done <<< "$dates"
		else
			apiResponse "$responseStatus"
		fi
		echo "" # empty line for readability in terminal
	done <<< "$serialnumbers"
else
	apiResponse "$responseStatus"
fi
#############################################################
exit 0
