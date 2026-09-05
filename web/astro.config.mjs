// @ts-check
import { defineConfig } from 'astro/config';

// Static output. The site is a couple of pages with no server behaviour, so
// there is nothing to run at request time.
export default defineConfig({
  // The public address, once there is one. Set it and the canonical link,
  // `og:url` and the share image become absolute and correct.
  //
  // Deliberately unset rather than left on a placeholder: every one of those
  // is built from this, so a stand-in domain does not degrade the tags, it
  // publishes wrong ones — a canonical pointing somewhere else entirely, and
  // a share card whose image is fetched from a site nobody owns. Base.astro
  // omits all three when this is absent, which is the honest state for a
  // deployment whose address is not yet known.
  //
  // site: 'https://devnotch.example',
  output: 'static',
  build: { inlineStylesheets: 'auto' },
  devToolbar: { enabled: false },
});
