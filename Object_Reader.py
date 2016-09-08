import Constants as CONST
from Reader import Reader

class Object_Reader(Reader):
    def __init__(self, xml_file):
        Reader.__init__(self, xml_file)
        self.matrix = list()
        self.obj_matrix = dict()  # {obj1:[ [][][] ], obj2: [ [][][] ], ...}

        self.parse_rows(self.root)



    def parse_rows(self, root):
        for row in root.iter(CONST.Row_tag):
            # parsed_row is [ 'cell1',  'cell2',  'cell3',  ...]
            parsed_row = self.process_row(row)
            levenshtein_fixed = self.fix_typos_obj(parsed_row)
            for cell_txt in levenshtein_fixed:
                if cell_txt in CONST.OBJECTS:
                    self.matrix.append(levenshtein_fixed)



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
    def create_object_groups(self):
        output = [dict() for i in range(len(self.matrix[0]))]#As many dicts as columns
        counts = self.count_obj_per_col()
        objects_index = counts.index(max(counts))

        for row in self.matrix:
            bacnet_object = row[objects_index]
            for col_num in range(len(row)):
                token = row[col_num]
                column_dict = output[col_num]
                if col_num == objects_index or token == '' or bacnet_object == '':
                    continue
                if token in column_dict.keys():
                    token_list = column_dict[token]
                    column_dict[token] = token_list + [bacnet_object]
                else:
                    column_dict[token] = [bacnet_object]
        return output



    def get_single_column_objects(self):
        l_of_dicts = self.create_object_groups()
        output = dict()
        for index in range(len(l_of_dicts)):
            for k in l_of_dicts[index]:
                output['col'+str(index)+'-'+k] = set(l_of_dicts[index][k])
        merge_all = self.merge_dos(output)
        output['all'] = merge_all
        return output



# [['device', '', 'x'],        Input: matrix on the left
#  ['calendar', '', 'y'],      Output: amount of objects per column
#  ['a', 'device', 'asdf']]            e.g.  [2, 1, 0]
    def count_obj_per_col(self):
        #All sublists must have the same length (i.e. max_num_cols)
        results = [0] * self.max_num_cols
        for index in range(self.max_num_cols):
            for row in self.matrix:
                if row[index] in CONST.OBJECTS:
                    results[index] += 1
        return results



# PUBLIC INTERFACE FOR THIS CLASS ##############################################
    def get_objects_found(self):
        return self.get_single_column_objects()


