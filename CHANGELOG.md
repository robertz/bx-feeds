# Changelog

**0.1.0**
- First release.
- `parseFeed()`: RSS 0.9x, 1.0 and 2.0 and Atom through ROME 2.1, and JSON Feed
  1.0 and 1.1, into one struct shape, from a string, bytes or a file path.
- Stable item ids: the feed's own, or a SHA-256 of the link and title.
- Dates as UTC datetimes or null; relative URLs in links, enclosures and
  content made absolute.
- `fetchFeed()`: conditional GET with `etag` and `lastModified`, redirects
  followed with permanent ones reported, a timeout over the whole fetch and a
  maximum body size.
- `discoverFeeds()`: `<link rel="alternate">` autodiscovery.
- No DTD is read: XXE, external DTDs and entity bombs are refused.
- Typed errors: `Feeds.ParseError`, `Feeds.FetchError` and its subtypes.
