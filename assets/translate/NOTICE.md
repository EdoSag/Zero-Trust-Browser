# Translation engine

`translator.js` and `worker/` are Firefox's translation engine, Bergamot
(`@browsermt/bergamot-translator` 0.4.9, https://github.com/browsermt/bergamot-translator),
under the Mozilla Public License 2.0 (https://mozilla.org/MPL/2.0/). They are
unchanged. `driver.js` and `index.html` are ZT Browser's own.

The language models are Mozilla's Firefox Translations models
(https://github.com/mozilla/translations, MPL-2.0), copied to this repository's
"translation-models" release by `.github/workflows/translation-models.yml`.
