// @ts-check
import { defineConfig } from 'astro/config';

// Static output. The site is a handful of pages with no server behaviour, so
// there is nothing to run at request time.
export default defineConfig({
  site: 'https://example.com',
  output: 'static',
  build: { inlineStylesheets: 'auto' },
  devToolbar: { enabled: false },
});
