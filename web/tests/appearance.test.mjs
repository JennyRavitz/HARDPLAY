import test from 'node:test';
import assert from 'node:assert/strict';
import {presets,normalizeTheme} from '../public/appearance.mjs';
test('appearance restores safe bounds from invalid saved preferences',()=>{
 const t=normalizeTheme({preset:'missing',accent:'url(javascript:bad)',buttonSize:999,textScale:-2,opacity:'NaN',radius:-1});
 assert.equal(t.preset,'Stage');assert.equal(t.accent,'#93c5f4');assert.equal(t.buttonSize,90);assert.equal(t.textScale,.9);assert.equal(t.opacity,.85);assert.equal(t.radius,0);
});
test('all stage and tape presets can round trip without changing colors or ranges',()=>{
 assert.deepEqual(Object.keys(presets),['Stage','Flightcase','Cables','Cinema','Theatre','Minimal','Tape Blue','Tape White','Tape Black']);
 for(const t of Object.values(presets))assert.deepEqual(normalizeTheme(JSON.parse(JSON.stringify(t))),t);
 assert.equal(presets.Minimal.texture,false);
});
