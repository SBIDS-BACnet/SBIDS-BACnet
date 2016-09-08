from Object_Reader import Object_Reader
from Property_Reader import Property_Reader
from DB_Reader import DB_Reader
from os.path import basename
import Constants as CONST
import re

class Rule_Extractor:
    def __init__(self, xml_file, _host,  _user, _pass, _dbname):
        self.xml_file = xml_file
        self.object_reader = Object_Reader(xml_file)
        self.property_reader = Property_Reader(xml_file)
        self.db_reader = DB_Reader(_host, _user, _pass, _dbname)



    def evaluate_properties_for_object(self, obj):
        props_found = self.get_properties_for_object(obj)
        actual_props = self.read_evaluation_file(self.xml_file, CONST.PRESENT_PROP, obj)
        return self.print_stats(props_found, actual_props)



    def evaluate_present_objects(self):
        objects_found = self.get_objects()
        actual_objects = self.read_evaluation_file(self.xml_file, CONST.PRESENT_OBJ)
        self.print_stats(objects_found, actual_objects)



    def print_stats(self, algorithm_results, actual_results):
        found_len = len(algorithm_results)
        actual_len = len(actual_results)
        
        total_correct = len(self.intersection(algorithm_results, actual_results))
        print "Intersect: ", self.intersection(algorithm_results, actual_results)
        
        if actual_len != 0 :
            pct_correct = (total_correct / float(actual_len)) * 100
        else :
            pct_correct = 0

            
        total_incorrect = len(self.difference(algorithm_results, actual_results))
        print "Difference: ", self.difference(algorithm_results, actual_results)
        
        if found_len != 0 :
            pct_incorrect = (total_incorrect / float(found_len)) * 100
        else:
            pct_incorrect = 0

            
        total_omissions = len(self.difference(actual_results, algorithm_results))
        print "Omissions: ", self.difference(actual_results, algorithm_results)
        
        if actual_len != 0 :
            pct_omissions = (total_omissions / float(actual_len)) * 100
        else:
            pct_omissions = 0
        
        print "Correct  : %.2f%%  %d out of %d" % (pct_correct, total_correct, actual_len)
        print "Incorrect: %.2f%%  %d out of %d" % (pct_incorrect, total_incorrect, found_len)
        print "Omissions: %.2f%%  %d out of %d" % (pct_omissions, total_omissions, actual_len)
        return total_correct, total_incorrect, total_omissions
        
        

    def evaluate_all_properties(self):
        # Set of BACnet objects identified by the Property_Reader class
        identified_objects = self.property_reader.obj_matrix.keys()
        total_correct = 0
        total_incorrect = 0
        total_omissions = 0
        
        for bacnet_obj in identified_objects:
            c, i, o = self.evaluate_properties_for_object(bacnet_obj)
            total_correct += c
            total_incorrect += i
            total_omissions += o
        print "******************************************************************"
        print "Correct  : %d" % (total_correct)
        print "Incorrect: %d" % (total_incorrect)
        print "Omissions: %d" % (total_omissions)
        print "******************************************************************"



    def jaccard_similarity(self, absent, present, reference):
        a, p, r = self.sanitize( absent, present, reference)

        len_p_intersect_r = len(set.intersection(*[set(p), set(r)]))
        len_a_intersect_r = len(set.intersection(*[set(a), set(r)]))
        len_p_union_r = len(set.union(*[set(p), set(r)]))
        len_p_minus_r = len(set.difference(*[set(p), set(r)]))
        
        res = len_p_intersect_r / float(len_p_union_r * (len_a_intersect_r + len_p_minus_r + 1))
        return res


    
    def intersection(self, a, b):
        l1, l2, l3 = self.sanitize(a,b)
        return list(set(l1) & set(l2))



    def union(self, a, b):
        l1, l2, l3 = self.sanitize(a,b)
        return list(set(l1) | set(l2))



    def difference(self, a, b):
        l1, l2, l3 = self.sanitize(a,b)
        return list(set(l1) - set(l2))



    def sanitize(self, a, b, c=[]):
        l1 = [re.sub('[-,_]', ' ', item) for item in a]
        l2 = [re.sub('[-,_]', ' ', item) for item in b]
        l3 = [re.sub('[-,_]', ' ', item) for item in c]
        return (l1, l2, l3)



    def read_evaluation_file(self, file, evaluation_type, obj=''):
        output = set() # Must be a set in case of repeated elements in eval file
        
        file_name_no_path = basename(self.xml_file)
        file_name_no_ext = file_name_no_path.split('.')[0]   # ['BACnet_PICS', 'xml']

        eval_file_path = CONST.EVAL_PATH + file_name_no_ext

        if evaluation_type == CONST.PRESENT_OBJ :
            eval_file_path += '-objects-present.txt'
        elif evaluation_type == CONST.ABSENT_OBJ :
            eval_file_path += '-objects-absent.txt'
        elif evaluation_type == CONST.PRESENT_PROP :
            eval_file_path += '-'+obj+'-properties.txt'
        
        f = open(eval_file_path , 'r')
        for l in f:
            output.add(re.sub('[-,_]', ' ', l.lower().strip()))
    
        return output


    

    def get_winner_tag(self, obj):
        file_name_no_path = basename(self.xml_file)
        file_name_no_ext = file_name_no_path.split('.')[0]   # ['BACnet_PICS', 'xml']

        properties_from_pics = self.property_reader.get_properties_for_object(obj)
        observed_present = set(self.db_reader.get_properties_for_object(file_name_no_ext, obj, CONST.PRESENT_PROP))
        observed_absent = set(self.db_reader.get_properties_for_object(file_name_no_ext, obj, CONST.ABSENT_PROP))
        
        #### Filter out proprietary properties
        observed_present = observed_present.intersection(CONST.PROPERTIES)

        ranking = dict()
        
        for k in properties_from_pics:
            if k == 'all':
                continue
            current_set = properties_from_pics[k]
            print current_set
           
            similarity = self.jaccard_similarity(observed_absent, observed_present, current_set)
                
            ranking[similarity] = k
            print similarity
        
        if 'all' in properties_from_pics.keys():
            current_set = properties_from_pics['all']
            print current_set

            similarity = self.jaccard_similarity(observed_absent, observed_present, current_set)

            ranking[similarity] = 'all'
            print similarity

        if len(ranking) > 0:
            max_score = max(ranking)
            print "Winner: " + ranking[max_score], max_score
            return ranking[max_score]
        return "no-winner-tag"


# PUBLIC INTERFACE FOR THIS CLASS ##############################################
    def get_objects(self):
        file_name_no_path = basename(self.xml_file)
        file_name_no_ext = file_name_no_path.split('.')[0]   # ['BACnet_PICS', 'xml']

        # objects_from_pics is a *dictionary*
        # {'col2-y': set(['calendar']), 'col2-x': set(['device']), ...}
        objects_from_pics = self.object_reader.get_objects_found()

        # objects_from_db is a *list*
        present_objects = self.db_reader.get_objects(file_name_no_ext, CONST.PRESENT_OBJ)
        absent_objects  = self.db_reader.get_objects(file_name_no_ext, CONST.ABSENT_OBJ)

        ranking = dict()
        for k in objects_from_pics:
            if k == 'all':
                continue
            print "Set name: ", k
            current_set = objects_from_pics[k]
            similarity = self.jaccard_similarity(absent_objects, present_objects, current_set)
            ranking[similarity] = k

        if 'all' in objects_from_pics.keys():
            print "Set name: 'all'"
            current_set = objects_from_pics['all']
            similarity = self.jaccard_similarity(absent_objects, present_objects, current_set)
            ranking[similarity] = 'all'

        max_score = max(ranking)
        if max_score == 0 and 'all' in objects_from_pics.keys():
            print "Winner: all"
            return 'all'
        else:
            print "Winner: " + ranking[max_score]
            return objects_from_pics[ranking[max_score]]

        

    def get_properties_for_object(self, obj):
        file_name_no_path = basename(self.xml_file)
        file_name_no_ext = file_name_no_path.split('.')[0]   # ['BACnet_PICS', 'xml']

        properties_from_pics = self.property_reader.get_properties_for_object(obj)
        properties_from_db = self.db_reader.get_properties_for_object(file_name_no_ext, obj, CONST.PRESENT_PROP)

        winner_tag = 'all'                                   # default
        if len(properties_from_db) > CONST.MIN_PROP :
            winner_tag = self.get_winner_tag(obj)
        elif obj != 'device':
            winner_tag = self.get_winner_tag('device')
        else:
            return

        print "--------------------------------------"
        print "winner tag", winner_tag
        print "tags available", properties_from_pics.keys()
        print "--------------------------------------"
        if winner_tag in properties_from_pics.keys():
            return properties_from_pics[winner_tag]
        else:
            return []


