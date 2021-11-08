#!/bin/bash

# This script uses the api to gather all serial numbers of a computer search and then gathers application usage data for that Mac.
# each entry contains User data so, multiple lines will exist for each serial. one for each application.
# exported report is stored in a coma sperated spreadsheet.
# Please see end of script for terms

# ##################################################################
# Environment Specific Variables 
# ##################################################################

# API Info 
api_user=""
api_pass=""
jamf_url="" #include port number if on prem

# A Jamf Pro Advanced Search that contains the clients for which you want a report
group_id=""

#select a start date YYYY-MM-DD 
start_date=""
#todays date
end_date=$(date +"%Y-%m-%d")

# App name or vendor in question, leave blank to collect all apps
app_name=""

csv_export="/tmp/app_usage_export.csv"
# ##################################################################
# End parameter definition. Code below...
# ##################################################################

# ##################################################################
# Main...
# ##################################################################
  
#######################################
# Create an XSLT file at /tmp/stylesheet.xslt
#######################################
 
cat << EOF > /tmp/stylesheet.xslt
<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text"/>
<xsl:template match="/">
    <xsl:for-each select="advanced_computer_search/computers/computer">
        <xsl:value-of select="Serial_Number"/>
        <xsl:text> </xsl:text>
    </xsl:for-each>
</xsl:template>
</xsl:stylesheet>
EOF

#######################################

#build the api path to the smartgroup
api_path="JSSResource/advancedcomputersearches/id/${group_id}"
  
#grab the serialnumbers from the adv search
echo "Getting a list of devices in Jamf Pro search ID ${group_id}"
URL="${jamf_url}/${api_path}"

responseXML=$( curl	--user "${api_user}:${api_pass}" --silent --show-error --write-out "\n%{http_code}" --header "Accept: text/xml" "${URL}" )

HTTP_Status=$( echo "$responseXML" | tail -1)
responseXML=$( echo "$responseXML" | sed \$d )
echo "HTTP_Status : $HTTP_Status"

/bin/echo -n "HTTP Status Code: $HTTP_Status : "
if [[ $HTTP_Status = "200" ]]; then
  echo '[OK]'
elif [[ $HTTP_Status = "400" ]]; then
  echo "[error] Invalid API request"
  exit 1
else
  echo "[error] API could not return the group information. "
  echo "$responseXML"
  exit 1
fi

# extract 
serialnumbers=(`echo "$responseXML" | xsltproc /tmp/stylesheet.xslt -`)
 
#display all the members of the array if needed
# echo "Serial number list : ${serialnumbers[@]}"

if [ -e $csv_export ]; then
  rm -f $csv_export
fi
#touch the temp export file
touch $csv_export
 
#write the header values of each column
echo "Device Name,Serial Number,App Name,Minutes in Forground" > $csv_export
 
# ##################################################################

#loop through once for each serial number in the array, pull the app usage via API, parse, and output to the .csv

for serial in  "${serialnumbers[@]}"; do
  echo "Requesting details for device serial number : ${serial}"     
  #build the api path for machine specific info using the serial.
  api_device_path="JSSResource/computers/serialnumber/$serial"
  #going to make a bunch of variables based on the the same chunk of data from the above api call.
  data=`curl ${security} --user "${api_user}:${api_pass}" --silent --show-error --header "Accept: text/xml" "$jamf_url/$api_device_path/subset/general"`
  devicename=$(echo $data | awk -F '<name>|</name>' '{print $2}')
  echo "Device Name: \"${devicename}\""
  
  #build the api path for Application usage History using the passed serial and the passed date ranges.
  api_path="JSSResource/computerapplicationusage/serialnumber/$serial/${start_date}_${end_date}"
  # here we actually do the api call and then pass it off to the style sheet to
  # extract the data, then we'll append it to the report output file...
  echo "Requesting application usage logs for ${serial}..."
  xmlResponse=$( curl ${security} --user "${api_user}:${api_pass}" --silent --show-error --header "Accept: text/xml" "$jamf_url/$api_path" )
  # echo "API Response: $xmlResponse"

	#######################################
	# Create an XSLT output template file at /tmp/stylesheet.xslt
	# This XSL spits out device info, using bash replace string operator "//" to remove any commas. because they will break the CSV.
	#######################################
cat << EOF > /tmp/stylesheet.xslt
<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:output method="text"/>
	<xsl:template match="/">
		<xsl:for-each select="computer_application_usage/usage/apps/app">
			<xsl:text>$devicename</xsl:text>
			<xsl:text>,</xsl:text>
			<xsl:text>$serial</xsl:text>
			<xsl:text>,</xsl:text>
			<xsl:value-of select="name"/>
			<xsl:text>,</xsl:text>
			<xsl:value-of select="foreground"/>
      <xsl:text>&#xa;</xsl:text>
		</xsl:for-each>
	</xsl:template>
</xsl:stylesheet>
EOF
######
  usageData=$( echo "$xmlResponse" | xsltproc /tmp/stylesheet.xslt - )
  if [[ "$usageData" == *"$app_name"* ]]; then
    while IFS= read -r line; do 
        if [[ "$line" == *"$app_name"* ]]; then
          echo "$line" >> $csv_export
        fi
    done <<< "$usageData"
  fi

done

# ##################################################################
exit 0