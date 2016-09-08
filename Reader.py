import xml.etree.ElementTree as ET
import Constants as CONST

class Reader:
    def __init__(self, xml_file):
        self.root = ET.parse(xml_file).getroot()
        self.max_num_cols = self.get_num_cols()

# How many columns are actually used in the spreadsheet
    def get_num_cols(self):
        val = 0
        for col in self.root.iter(CONST.Col_tag):
            if CONST.Index_attrib in col.attrib:
                col_index = int(col.attrib[CONST.Index_attrib])
                if val < col_index:
                    val = col_index
        return val


    
    def process_row(self, row):
        storage_list =  [''] * self.max_num_cols
        for cell in row.iter(CONST.Cell_tag):
            cell_str = ''
            for elem in cell.iter():
                if elem.text:
                    clean_txt = elem.text.lower().strip()
                                                      # If line is empty or
                    if ((cell_str == '') or           #    ends in '-'
                        (len(cell_str.strip()) > 0 and cell_str.strip()[-1] == u'-')):
                        cell_str += clean_txt.strip() # the word continues below
                    else:                             # Else
                        cell_str += ' ' + clean_txt   # it is a different word
            if CONST.Index_attrib in cell.attrib:
                storage_list[int(cell.attrib[CONST.Index_attrib])-1] = cell_str
        # Apply Levenshtein's distance        
        fixed_list = self.fix_typos_prop(storage_list)
        return fixed_list



# Input: a dictionary of sets
# Output: a set -> the union of all input sets
    def merge_dos(self, dos):
        output = set()
        for k in dos:
            output = output.union(dos[k])
        return output



# Levenshtein's distance between two strings
# https://en.wikibooks.org/wiki/Algorithm_Implementation/Strings/Levenshtein_distance
    def levenshtein(self, s1, s2):
        if len(s1) < len(s2):
            return self.levenshtein(s2, s1)

        if len(s2) == 0:
            return len(s1)

        previous_row = range(len(s2) + 1)
        for i, c1 in enumerate(s1):
            current_row = [i + 1]
            for j, c2 in enumerate(s2):
                 # j+1 instead of j since previous_row and current_row are one
                 # character longer than s2
                insertions = previous_row[j + 1] + 1
                deletions = current_row[j] + 1
                substitutions = previous_row[j] + (c1 != c2)
                current_row.append(min(insertions, deletions, substitutions))
            previous_row = current_row
        return previous_row[-1]



# In case of typos in the PICS, fix them with the most likely value (i.e. min
# levenshtein's distance).
    def fix_typos_prop(self, cell_list):
        fixed_list = cell_list
        for i in range(len(cell_list)):
            distances = dict()

            for bacnet_prop in CONST.PROPERTIES:
                d = self.levenshtein(cell_list[i], bacnet_prop)
                distances[d] = bacnet_prop

            for bacnet_prop in CONST.PROPERTIES2:
                d = self.levenshtein(cell_list[i], bacnet_prop)
                distances[d] = bacnet_prop

            for bacnet_prop in CONST.PROPERTIES3:
                d = self.levenshtein(cell_list[i], bacnet_prop)
                distances[d] = bacnet_prop
     
            if (len(distances) > 0 and min(distances) <= CONST.MAX_DISTANCE):
                fixed_list[i] = distances[min(distances)]
        return fixed_list


# The same but for BACnet objects
    def fix_typos_obj(self, cell_list):
        fixed_list = cell_list
        for i in range(len(cell_list)):
            cell_txt = cell_list[i].replace('object', '').strip()
            distances = dict()
            for bacnet_obj in CONST.OBJECTS:
                d = self.levenshtein(cell_txt, bacnet_obj)
                distances[d] = bacnet_obj

            if (len(distances) > 0 and min(distances) <= CONST.MAX_DISTANCE):
                fixed_list[i] = distances[min(distances)]
        return fixed_list

