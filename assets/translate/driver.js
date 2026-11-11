// Drives Firefox's translation engine (translator.js, MPL-2.0) for ZT
// Browser. Every file it loads, models included, is answered by the app:
// this page has no network.
import {BatchTranslator, TranslatorBacking} from './translator.js';

let translator = null;
let loaded = '';

async function models() {
  const r = await fetch('models/registry.json', {cache: 'no-store'});
  return r.ok ? await r.text() : '[]';
}

async function get() {
  const text = await models();
  if (translator && text === loaded) return translator;
  if (translator) translator.delete();
  loaded = text;
  const registry = JSON.parse(text);
  // An empty registry file keeps the engine from looking anything up.
  const backing = new TranslatorBacking({
    registryUrl: new URL('empty.json', location).href,
    downloadTimeout: 0,
    pivotLanguage: 'en',
  });
  backing.registry = Promise.resolve(registry);
  translator = new BatchTranslator({workers: 1, batchSize: 8, pivotLanguage: 'en'}, backing);
  return translator;
}

function post(msg) {
  ztTranslate.postMessage(JSON.stringify(msg));
}

window.zt = {
  async run(job) {
    try {
      const t = await get();
      const out = await Promise.all(job.texts.map(text =>
        t.translate({from: job.from, to: job.to, text, html: job.html})
          .then(r => r.target.text)));
      post({id: job.id, out});
    } catch (e) {
      post({id: job.id, error: String(e && e.message || e)});
    }
  },
  reset() {
    loaded = '';
  },
};

post({ready: true});
