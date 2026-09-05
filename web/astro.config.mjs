// @ts-check
import { defineConfig } from 'astro/config';

// Static output. The site is a couple of pages with no server behaviour, so
// there is nothing to run at request time.
export default defineConfig({
  // Where the site actually lives. The canonical link, `og:url` and the share
  // image are all built from this, so it has to be the real address — a
  // placeholder does not degrade those tags, it publishes wrong ones.
  site: 'https://devnotch-ai.vercel.app',
  output: 'static',
  build: { inlineStylesheets: 'auto' },
  devToolbar: { enabled: false },
});
