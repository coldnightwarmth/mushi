import io
import json
import unittest
from mushi.json_stream import array_records, manifest_records


class Chunks(io.StringIO):
    def __init__(self,text,size):super().__init__(text);self.size=size
    def read(self,size=-1):return super().read(min(size,self.size))


class StreamingManifest(unittest.TestCase):
    def test_every_token_boundary(self):
        records=[{'id':'虫\\"\n','value':-1.2e+30,'nested':[True,None,False,[],{}]},
                 {'id':'next','value':1.23456789e-20},123456789,0,-1]
        document={'coverage':{'count':len(records)},'resources':[],
                  'observed':records,'animation_catalog':'animations/catalog.json'}
        expected=[('coverage',document['coverage']),('resources',[])]+[('observed_record',r) for r in records]+[('animation_catalog','animations/catalog.json')]
        for size in range(1,65):
            self.assertEqual(list(array_records(Chunks(json.dumps(records),size))),records)
            self.assertEqual(list(manifest_records(Chunks(json.dumps(document,ensure_ascii=False),size))),expected)

    def test_rejects_truncation_and_trailing_data(self):
        for text in ['[1,','[1e','[1.]','["missing]','[1] garbage','[1,]']:
            with self.assertRaises((ValueError,json.JSONDecodeError)):
                list(array_records(Chunks(text,1)))
        for text in ['{"observed":[1]', '{"observed":[1]} garbage','{"observed":[1],}']:
            with self.assertRaises((ValueError,json.JSONDecodeError)):
                list(manifest_records(Chunks(text,2)))

if __name__=='__main__':unittest.main()
