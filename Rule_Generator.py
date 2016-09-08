#!/usr/bin/python
import string
from DB_Reader import DB_Reader
from Rule_Extractor import Rule_Extractor
import Constants as CONST
import sys

class Rule_Generator:
    def __init__(self, _host, _user, _pass, _dbname):
        self.host = _host
        self.user = _user
        self.pwd = _pass
        self.dbname = _dbname
        self.db_reader = DB_Reader(CONST.HOST, _user, _pass, _dbname)
        self.objects_rules = open('objects-rules.txt', 'w')
        self.properties_rules = open('properties-rules.txt', 'w')


    def __del__(self):
        self.objects_rules.close()
        self.properties_rules.close()


    def generate_object_rules(self):
        pics_files_array = self.db_reader.get_distinct_pics()
        
        for pics_file in pics_files_array:
            rule_extractor = Rule_Extractor(pics_file.replace('.pdf', '.xml'),
                                            self.host, self.user, self.pwd,
                                            self.dbname)
            ids_per_pics = self.db_reader.get_devids_by_pics(pics_file)
            adds_per_pics = self.db_reader.get_devadds_by_pics(pics_file)
            formated_adds_per_pics = [self.format_bac_address(i) for i in adds_per_pics]
            identified_objects = rule_extractor.get_objects() # Set of BACnet objects
            
            for devid in ids_per_pics + formated_adds_per_pics:
                rule_string = "[\""+str(devid)+ "\"] = "
                rule_string += "set("

                for bacnet_obj in identified_objects:
                    rule_string += "\"" + bacnet_obj.replace(' ', '-').replace('_', '-') + "\","

                rule_string += ")"
                rule_string = rule_string.replace(",)", ")") + ","

                self.objects_rules.write(rule_string+'\n')



    def generate_property_rules(self):
        pics_files_array = self.db_reader.get_distinct_pics()
        
        for pics_file in pics_files_array:
            rule_extractor = Rule_Extractor(pics_file.replace('.pdf', '.xml'),
                                            self.host, self.user, self.pwd,
                                            self.dbname)
            ids_per_pics = self.db_reader.get_devids_by_pics(pics_file)
            adds_per_pics = self.db_reader.get_devadds_by_pics(pics_file)
            formated_adds_per_pics = [self.format_bac_address(i) for i in adds_per_pics]

            # Set of BACnet objects identified by the Property_Reader class
            identified_objects = rule_extractor.property_reader.obj_matrix.keys()

            for devid in ids_per_pics + formated_adds_per_pics:
                rule_string = "[\""+str(devid)+ "\"] = set("
                
                for bacnet_obj in identified_objects:
                    identified_properties = rule_extractor.get_properties_for_object(bacnet_obj)

                    # This line adds the mandatory properties to the object even if they are not
                    # in the PICS.
                    object_spaces = bacnet_obj.replace('-', ' ').replace('_', ' ')
                    if object_spaces in CONST.MANDATORY:
                        identified_properties = set(identified_properties).union(CONST.MANDATORY[object_spaces])

                    for bacnet_prop in identified_properties:
                        rule_string += "[$object_name=\"" + bacnet_obj.replace(' ', '-').replace('_', '-') + "\", "
                        rule_string += "$property_name=\"" + bacnet_prop.replace(' ', '-').replace('_', '-') + "\"],"

                rule_string += ")"
                rule_string = rule_string.replace("],)", "])") + ","

                self.properties_rules.write(rule_string+'\n')



# The output of this function is how addresses are encoded in:
#   event bacnet_npdu_parameters(c: connection, src: string, dst: string)
# Input: '69:42:00:00:00:00'
# Output: 'iB\\x00\\x00\\x00\\x00'
    def format_bac_address(self, bac_address):
        hex_parts = bac_address.split(':')         # ['69' '42' '00' '00' '00' '00']
        char_parts = [chr(int(i, base=16)) for i in hex_parts] # ['i' 'B' '\x00' '\x00' '\x00' '\x00']
        printables = [i in CONST.PRINTABLE for i in char_parts] # [T T F F F F]

        output = ""
        for i in range(len(hex_parts)):
            if printables[i]:
                output += char_parts[i] if char_parts[i] != '"' else '\\"'
            else:
                output += '\\\\x'+hex_parts[i]
        return output



#*******************************************************************************
#*******************************************************************************

def main(argv):
    if len(sys.argv) != 5 :
        print "Host, user, password and db required."
        sys.exit(1)

    rg = Rule_Generator(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
    rg.generate_object_rules()
    rg.generate_property_rules()
    exit(0)

if __name__ == "__main__":
    main(sys.argv)

