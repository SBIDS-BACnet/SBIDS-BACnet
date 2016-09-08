#!/usr/bin/python
import MySQLdb as mdb
import requests
import libxml2
import urllib
import sys
import csv

VENDORS_FILE = "vendors.txt"
SOLR_REQUEST = "http://localhost:8983/solr/abc/select?wt=xml&indent=on&fl=id&omitHeader=true&rows=1&q="

#                 host,        user,        pass,        db
con = mdb.connect(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])

reader = csv.reader(open(VENDORS_FILE), delimiter=" ")   # File descriptor
vendors_list = [(int(row[0]),row[1].replace('_', ' ').strip())
                for row in reader]                       # Read the file
vendors_dict = dict(vendors_list)                        # Convert to dict



#*******************************************************************************
#*******************************************************************************
def solr_query(query_url):
    r = requests.get(SOLR_REQUEST + urllib.quote_plus(query_url))
    doc = libxml2.parseDoc(r.text)
    ctxt = doc.xpathNewContext()
    pics = ctxt.xpathEval('/response/result/doc')
    
    for pic in pics:
        ctxt.setContextNode(pic)
        file_name = ctxt.xpathEval('str')[0].getContent()
        return file_name

    # clean up nicely
    doc.freeDoc()
    ctxt.xpathFreeContext()



#*******************************************************************************
#*******************************************************************************
def update_db(file_name, counter):
    cur2 = con.cursor()
    cur2.execute("UPDATE device SET pics_file = %s WHERE counter = %s",
                 (file_name, counter))



#*******************************************************************************
#*******************************************************************************
# vendor_code int -> dictionary key
# returns         -> String name of the appropriate BACnet vendor
def update_vendor(vendor_code):
    cur3 = con.cursor()                                    # DB cursor
    # Fix the vendor in all records with that vendor_code
    cur3.execute("UPDATE device SET vendor = %s WHERE vendor = %s",
                 (vendors_dict[vendor_code], "\""+str(vendor_code)+"\""))



#*******************************************************************************
#*******************************************************************************
def represents_int(s):
    try: 
        int(s)
        return True
    except ValueError:
        return False



#*******************************************************************************
#*******************************************************************************
def main(argv):
    if len(sys.argv) != 5 :
        print "Host, user, password and Db required."
        sys.exit(1)

    try:
        with con:
            cur1 = con.cursor()
            cur1.execute("SELECT * FROM device")

            # First fix the vendors
            for i in range(cur1.rowcount):
                row = cur1.fetchone()
                vendor = row[7].replace('"', '').strip()
                if represents_int(vendor) : # Is vendor a str-int? Eg "105"
                    update_vendor(int(vendor))   # Update the value in the DB

            cur1.execute("SELECT * FROM device")
            # Second find PICS in solr
            for i in range(cur1.rowcount):
                row = cur1.fetchone()
                # model + object + vendor
                query = row[3] + " " + row[4] + " " + row[7]
                # strip all the quotes
                query = query.replace('"', '').strip()
                # scaping the "/" character
                query = query.replace('/', '\/')
                file_name = solr_query(query)
                update_db(file_name, row[0])
    except mdb.Error, e:
        print "Error %d: %s" % (e.args[0], e.args[1])
        sys.exit(1)
    finally:
        if con:
            con.close()
    exit(0)



#*******************************************************************************
#*******************************************************************************
if __name__ == "__main__":
    main(sys.argv)




