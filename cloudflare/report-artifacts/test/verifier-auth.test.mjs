import assert from 'node:assert/strict';
import test from 'node:test';
import {acceptanceControlAuthorized} from '../src/acceptance-auth.ts';

const secret='AbCdEf0123456789_-AbCdEf0123456789_-AbCdEf0123456789_-';

test('exact Bearer acceptance secret authorizes',async()=>assert.equal(await acceptanceControlAuthorized(`Bearer ${secret}`,secret),true));
test('wrong acceptance secret is denied',async()=>assert.equal(await acceptanceControlAuthorized(`Bearer ${secret}x`,secret),false));
test('missing Authorization header is denied',async()=>assert.equal(await acceptanceControlAuthorized(null,secret),false));
test('malformed Bearer header is denied',async()=>assert.equal(await acceptanceControlAuthorized(`Token ${secret}`,secret),false));
test('candidate trailing newline is denied',async()=>assert.equal(await acceptanceControlAuthorized(`Bearer ${secret}\n`,secret),false));
test('configured trailing newline is denied',async()=>assert.equal(await acceptanceControlAuthorized(`Bearer ${secret}`,`${secret}\n`),false));
test('Base64URL characters are accepted',async()=>assert.equal(await acceptanceControlAuthorized(`Bearer ${'_'.repeat(32)}-${'a'.repeat(31)}`,`${'_'.repeat(32)}-${'a'.repeat(31)}`),true));
test('maximum accepted secret length authorizes',async()=>{const maximum='a'.repeat(256);assert.equal(await acceptanceControlAuthorized(`Bearer ${maximum}`,maximum),true)});
test('over-maximum secret length is denied',async()=>{const excessive='a'.repeat(257);assert.equal(await acceptanceControlAuthorized(`Bearer ${excessive}`,excessive),false)});
test('missing configured binding fails closed',async()=>assert.equal(await acceptanceControlAuthorized(`Bearer ${secret}`,undefined),false));
