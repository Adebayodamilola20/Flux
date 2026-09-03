// @ts-check
import { defineConfig } from 'astro/config';

// Static output. The site is a couple of pages with no server behaviour, so
// there is nothing to run at request time.
export default defineConfig({
  // PLACEHOLDER — set this to the real domain before deploying. It is what
  // `<link rel="canonical">` and `og:url` are built from, so shipping as-is
  // would point every canonical at example.com.
  // If it is unset entirely, Base.astro omits those two tags rather than
  // failing to render — see the comment on `canonical` there.
  site: 'https://example.com',
  output: 'static',
  build: { inlineStylesheets: 'auto' },
  devToolbar: { enabled: false },
});
