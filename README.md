# Jamf-Export-Application-Usage
Export Application usage based on an Advanced Search


There's a couple spots in the main area of the script that you can update based on your particular needs.

*Line 94* - 
Contains the header information for .csv file

*Line 105* - 
Contains all information within the <general> tags of the API response, you can pull more device information from here if desired. 

*Lines 121-138* - 
Contains the parsing of the API XML response, if you add additional headers, make sure you also include the corresponding items
