#!/usr/bin/python
import MySQLdb as mdb
import Constants as CONST
import sys

class DB_Reader:
    # Constructor
    def __init__(self, _host, _user, _pwd, _db):
        self.con = mdb.connect(_host, _user, _pwd, _db)

    # Destructor
    def __del__(self):
        if self.con:
            self.con.close()


    def flatten(self, *args):
        output_list = []
        for l in args:
            if not isinstance(l, (list, tuple)): l = [l]
            for item in l:
                if isinstance(item, (list,tuple)):
                    output_list.extend(self.flatten(item))
                else:
                    output_list.append(item)
        return output_list


    # Retrieve present objects from DB
    def get_objects(self, pics_file, object_status):
        pics_file = '%/' + pics_file + '.pdf'
        try:
            with self.con:
                cur1 = self.con.cursor()
                if object_status == CONST.PRESENT_OBJ:
                    query = ">"
                elif object_status == CONST.ABSENT_OBJ:
                    query = "<"
                cur1.execute("SELECT object_name FROM objects_pics " +
                             "WHERE is_present " + query +
                             " 0 AND pics_file like %s", (pics_file))
                return self.flatten(cur1.fetchall())
        except mdb.Error, e:
            print "Error %d: %s" % (e.args[0], e.args[1])
            sys.exit(1)


    #
    def get_properties_for_object(self, pics_file, obj, prop_status):
        pics_file = '%/' + pics_file + '.pdf'
        try:
            with self.con:
                cur1 = self.con.cursor()
                if prop_status == CONST.PRESENT_PROP:
                    symbol = ">"
                elif prop_status == CONST.ABSENT_PROP:
                    symbol = "<"
                cur1.execute("SELECT property_name FROM properties_pics " +
                             "WHERE is_present " + symbol + " 0 AND " +
                             "object_name = %s AND pics_file like %s" ,
                             (obj, pics_file))
                return self.flatten(cur1.fetchall())
        except mdb.Error, e:
            print "Error %d: %s" % (e.args[0], e.args[1])
            sys.exit(1)



    #
    def get_distinct_pics(self):
        try:
            with self.con:
                cur1 = self.con.cursor()
                cur1.execute("SELECT DISTINCT pics_file FROM device WHERE " +
                             "pics_file is not null")
                return self.flatten(cur1.fetchall())
        except mdb.Error, e:
            print "Error %d: %s" % (e.args[0], e.args[1])
            sys.exit(1)



    #
    def get_devids_by_pics(self, pics_file):
        try:
            with self.con:
                cur1 = self.con.cursor()
                cur1.execute("SELECT DISTINCT device_id FROM device WHERE " +
                             "pics_file = %s AND device_id is not null",
                             (pics_file))
                return self.flatten(cur1.fetchall())
        except mdb.Error, e:
            print "Error %d: %s" % (e.args[0], e.args[1])
            sys.exit(1)



    # Get device addresses
    def get_devadds_by_pics(self, pics_file):
        try:
            with self.con:
                cur1 = self.con.cursor()
                cur1.execute("SELECT DISTINCT bacnet_adr FROM device WHERE " +
                             "pics_file = %s AND bacnet_adr is not null",
                             (pics_file))
                return self.flatten(cur1.fetchall())
        except mdb.Error, e:
            print "Error %d: %s" % (e.args[0], e.args[1])
            sys.exit(1)

