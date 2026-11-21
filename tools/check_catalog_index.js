"use strict";
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=process.argv[2];if(!root)throw Error('Pass the catalog directory');
let full=JSON.parse(fs.readFileSync(path.join(root,'catalog.json'),'utf8'));
if(full.full_manifest)full=JSON.parse(require('node:zlib').gunzipSync(fs.readFileSync(path.join(root,full.full_manifest))));
const sandbox={window:{}};vm.runInNewContext(fs.readFileSync(path.join(root,'catalog-data.js'),'utf8'),sandbox);
const index=JSON.parse(JSON.stringify(sandbox.window.MUSHI_CATALOG));
assert.deepEqual(index.resources,full.resources);
assert.equal(index.observed.length,full.observed.length);
for(let i=0;i<full.observed.length;i++) {
 const expected=full.observed[i],actual=index.observed[i];
 for(const key of ['id','index','resource_index','resource_id','source_rect','width','height','attributes','source','thumbnail','metadata','compression','status','classification','duplicate_of','note'])
  assert.deepEqual(actual[key],expected[key],`${expected.id}: ${key}`);
 assert.equal(actual.observation_count,expected.observations.length);
 for(const key of ['capture','mode','character','shot','frame','command_address'])
  assert.equal(actual.observations[0][key],expected.observations[0][key],`${expected.id}: first ${key}`);
 assert.deepEqual(actual.native_stages,expected.native_stages||[]);
}
console.log(`Browser index matches ${full.resources.length} sheets and ${full.observed.length} exact rectangles.`);
