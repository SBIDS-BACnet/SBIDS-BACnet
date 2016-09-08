import Constants as CONST
from Reader import Reader

class Property_Reader(Reader):
    def __init__(self, xml_file):
        Reader.__init__(self, xml_file)
        self.last_object = ''
        self.matrix = list()
        self.obj_matrix = dict()  # {obj1:[ [][][] ], obj2: [ [][][] ], ...}

        self.parse_rows(self.root)
        


    def parse_rows(self, root):
        for row in root.iter(CONST.Row_tag):
            # parsed_row is [ 'cell1',  'cell2',  'cell3',  ...]
            parsed_row = self.process_row(row)
            levenshtein_fixed = self.fix_typos_obj(parsed_row)
            
            for cell_str in levenshtein_fixed:
                self.look_for_object(cell_str)

            if self.is_relevant_row(parsed_row):
                self.matrix.append(parsed_row)
            
        # After reading the file, are there elements in memory that need to be saved
        if len(self.matrix) > 0 and self.last_object != '':
            if self.last_object not in self.obj_matrix.keys():
                self.obj_matrix[self.last_object] = self.matrix



    def look_for_object(self, txt):
        clean_txt = txt.strip()
        if clean_txt in CONST.OBJECTS:
            if (self.last_object != '' and len(self.matrix) > 0) :
                self.obj_matrix[self.last_object] = self.matrix
                # I had found something before...
                if clean_txt in self.obj_matrix.keys():
                    self.matrix = self.obj_matrix[clean_txt] # ...bring it back
                else: # else create a new entry for that BACnet object
                    self.matrix = list()
            self.last_object = clean_txt



# Input:  list of lists.                             E.g.  [[3,4], [5,6], [1,2]]
# Output: Flat set with all the elems from the lists.      {1, 2, 3, 4, 5, 6}
    def flatten(self, lol):
        output = set()
        for l in lol:
            for x in l:
                output.add(x)
        return output
    


# Input: a dictionary of sets
# Output: a set -> the union of all input sets
    def merge_dos(self, dos):
        output = set()
        for k in dos:
            output = output.union(dos[k])
        return output
            
    
    
# Table extraction considers as relevant rows only those mentioning properties
    def is_relevant_row(self, row_list):
        for separator in CONST.SEPARATORS:
            for elem in row_list:
                elems_list = elem.split(separator)
                for elem in elems_list:
                    if (elem.strip() in CONST.PROPERTIES or
                        elem.strip() in CONST.PROPERTIES2 or
                        elem.strip() in CONST.PROPERTIES3) :
                        return True
        return False



# Does this matrix/table contain multiple columns with properties?
# | P1 |    |...|
# |    | P2 |...|    Input: several rows [ [P1, ''] ['', P2] [P3, P4] ['', P5]]
# | P3 | P4 |...|
# |    | P5 |...|    Output: True if looks like the example, False otherwise
    def is_multi_column_properties(self, matrix):
        output = set() # To store the column numbers where properties where found
        for row in matrix:
            for col_num in range(len(row)):
                token = row[col_num]
                if (token.strip() in CONST.PROPERTIES or
                    token.strip() in CONST.PROPERTIES2 or
                    token.strip() in CONST.PROPERTIES3) :
                    output.add(col_num)
        if len(output) > 1:
            return True, output
        return False, output



# This function is called when all the properties are located in the same column
# Expands properties along the table
#
# Input example: matrix column 1 holds the properties
# | N | P1 | R | O |
# | Y | P2 | W | R |
# | Y | P3 | W | R |
# | Y | P4 | R | O |
#
# Output example
# [
#     {  'n': ['P1'],           'y': ['P2', 'P3', 'P4']}
#     {                                                },
#     {'R': ['P1', 'P4'],       'W': ['P2', 'P3']      },
#     {'O': ['P1', 'P4'],       'R': ['P2', 'P3']      }
# ]
    def create_property_groups(self, matrix):
        output = [dict() for i in range(len(matrix[0]))]#As many dicts as columns
        f, properties_col_num_set = self.is_multi_column_properties(matrix)
        if (f or len(properties_col_num_set) == 0):
            print "Error: matrix format is incorrect for this function"
            return output
        properties_col_num = properties_col_num_set.pop()
        
        for row in matrix:
            bacnet_property = row[properties_col_num]
            for col_num in range(len(row)):
                token = row[col_num]
                column_dict = output[col_num]
                if col_num == properties_col_num or token == '':
                    continue
                if token in column_dict.keys():
                    token_list = column_dict[token]
                    column_dict[token] = token_list + [bacnet_property]
                else:
                    column_dict[token] = [bacnet_property]
        return output



# Input example: matrix column 1 holds the properties
# | N | P1 | R | O |
# | Y | P2 | W | R |
# | Y | P3 | W | R |
# | Y | P4 | R | O |
#
# Intermediate computation (create_property_groups)
# [
#     {  'n': ['P1'],           'y': ['P2', 'P3', 'P4']}
#     {                                                },
#     {'R': ['P1', 'P4'],       'W': ['P2', 'P3']      },
#     {'O': ['P1', 'P4'],       'R': ['P2', 'P3']      }
# ]
#
# Output example
# [['P1'] ['P2', 'P3', 'P4'] ['P1', 'P4'] ['P1', 'P4'] ['P2','P3'] ['P2','P3'] [all] ]
    def get_single_column_properties(self, matrix):
        l_of_dicts = self.create_property_groups(matrix)
        output = dict()
        for index in range(len(l_of_dicts)):
            for k in l_of_dicts[index]:
                output['col'+str(index)+'-'+k] = set(l_of_dicts[index][k])
        merge_all = self.merge_dos(output)
        output['all'] = merge_all
        return output
    


# Does this matrix/table contain multiple columns with properties?
# | P1 |    |...|
# |    | P2 |...|    Input: several rows [ [P1, ''] ['', P2] [P3, P4] ['', P5]]
# | P3 | P4 |...|
# |    | P5 |...|    Output: Properties per column [ [P1, P3] [P2, P4, P5] [all] ]
    def get_multi_column_properties(self, matrix):
        t, col_set = self.is_multi_column_properties(matrix)
        output = dict()
        matrix_prime = [list(i) for i in zip(*matrix)]    # Matrix transpose
        for col_num in col_set:
            properties_set = set()
            for token in matrix_prime[col_num]:
                if (token.strip() in CONST.PROPERTIES or
                    token.strip() in CONST.PROPERTIES2 or
                    token.strip() in CONST.PROPERTIES3) :
                    properties_set.add(token.strip())
            output['col'+str(col_num)] = properties_set
        merge_all = self.merge_dos(output)
        output['all'] = merge_all
        return output



# Does this matrix/table contain single cells with multiple properties?
# | O1 | P1, P2 | P5, P6 |   Input: a row [[O1], [...], [P1..P4], [...], [] ]
# |    | P3, P4 |        |   Output: True if looks like the example, False other
    def is_multi_property_cell(self, matrix):
        for row in matrix:
            for col in row:
                for separator in CONST.SEPARATORS:
                    counter = 0                           # +2 in the same cell?
                    elems_list = col.split(separator)
                    for elem in elems_list:
                        if (elem.strip() in CONST.PROPERTIES or
                            elem.strip() in CONST.PROPERTIES2 or
                            elem.strip() in CONST.PROPERTIES3) :
                            counter += 1
                    if counter > 1:
                        return True
        return False



# In case there are multiple properties per cell return a list with those groups
# | O1 | P1, P2 | P5, P6 |   Input: a row [[O1], [...], [P1..P4], [...], [] ]
# |    | P3, P4 |        |   Output: [ [P1, P2, P3, P4] [P5, P6] [all] ]
    def group_properties(self, matrix):
        #output = list()
        output = dict()
        for row in matrix:
            col_num = 0
            for col in row:
                cell_set = set()
                for separator in CONST.SEPARATORS:
                    elems_list = col.split(separator)
                    for elem in elems_list:
                        if (elem.strip() in CONST.PROPERTIES or
                            elem.strip() in CONST.PROPERTIES2 or
                            elem.strip() in CONST.PROPERTIES3) :
                            cell_set.add(elem.strip())
                if len(cell_set):
                    output['col'+str(col_num)] = cell_set
                col_num += 1
        merge_all = self.merge_dos(output)
        output['all'] = merge_all
        return output



# PUBLIC INTERFACE FOR THIS CLASS ##############################################
    # Returns a list of object found in the PICS
    # E.g. ['trend log', 'binary input', ...]
    def get_objects_found(self):
        return self.obj_matrix.keys()

    def get_properties_for_object(self, bacnet_object):
        if bacnet_object not in self.obj_matrix.keys():
            print "Requested BACnet object (",bacnet_object,") was not found."
            return dict()

        properties_table = self.obj_matrix[bacnet_object]

        b, s = self.is_multi_column_properties(properties_table)
        
        if self.is_multi_property_cell(properties_table):
            return self.group_properties(properties_table)
        elif b:
            return self.get_multi_column_properties(properties_table)
        else:
            return self.get_single_column_properties(properties_table)

