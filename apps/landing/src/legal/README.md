# Legal content source

The landing app imports the six localized privacy policies and Terms of Use
directly from `apps/ios/Anky/*.lproj`. Those bundled documents are the shared
canonical source so the public pages and shipped iOS resources cannot drift.

Routes and legacy aliases are defined in `src/legalRoutes.ts` and hosting
redirects in `public/_redirects`.
