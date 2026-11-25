# Changelog

**0.5.0**
- `fallbackUserAgents`: a site that refuses the User-Agent with a 401 or 403
  is asked again as each fallback, and the one a host accepts is remembered.
- `challenged` on the fetch result: the refusal is a bot check (Cloudflare,
  or a CAPTCHA) that no fetch can pass.
- A site that answers a feed fetch with 429 is left alone, for its
  `Retry-After` or 15 minutes doubling up to four hours. Until then fetches of
  its feeds return a 429 marked `paused` without a request. `pauseAfter429:
  false` turns this off.
- `retryNotFound`: addresses matching a pattern are asked again after a 404.
- `FeedFetcher` gains `pausedSites()`, `pausedSeconds()`, `endPause()`,
  `forget()` and `siteOf()`.

**0.4.0**
- `findFeeds()`: the feeds behind a pasted address. The address itself, the
  feeds its page advertises, a known site pattern (Reddit, GitHub, Mastodon)
  or a common path, each fetched and parsed, within a time budget.
- `webSub()`: subscribe to and unsubscribe from a feed's hub, read the hub's
  check, and verify a push's `X-Hub-Signature`.
- More of a podcast. On the feed: `author`, `owner`, `type`, `explicit`,
  `complete`, `newFeedUrl`, `categories`, `guid`, `locked`, `medium`,
  `location`, `value` and `liveItems`. On an item: `season`, `episode`,
  `episodeType`, `explicit`, `location` and `value`.
- `fetchFeed()` takes an `accept` option, and `FeedFetcher.postForm()` posts
  a form with the same address checks as a fetch.

**0.3.0**
- `httpOnly` option: every returned URL that isn't http(s) is blanked, or
  dropped with its entry when it's in a list.
- `collapseRevisions` option: an id that is the item's link plus an edit
  number (`.../story#3`) loses the number, so an edited item stays one item.
- `maxItems` and `maxLength` options limit what `parseFeed()` returns and
  accepts.
- `fetchFeed()` passes those options to the parser, and reports
  `maxAgeSeconds` from `Cache-Control: max-age` or `Expires`.

**0.2.0**
- **Breaking:** `fetchFeed()` refuses addresses that aren't public (loopback,
  private, link-local and the like), on every redirect too, with
  `Feeds.FetchError.PrivateAddress`. Set `allowPrivateAddresses` to allow them.
- **Breaking:** an item without a guid gets its link as its id, not a hash of
  the link and title. Only an item with neither is hashed.
- **Breaking:** titles, authors and categories are plain text with entities
  decoded; a title declared as HTML loses its tags, and an RSS author written
  `email (Name)` is the name.
- Feeds XML parsers refuse are repaired: an attribute repeated on the root
  element, a `<skipHours>` or `<skipDays>` ROME won't take, and UTF-8 that
  was encoded twice.
- Dates in formats ROME doesn't read (full names, `2026-11-02 10:00:00`,
  `November 2, 2026 3:15 PM`, a day alone and others) are read.
- New on the feed: `feedUrl`, `hubs`, `nextUrl`, `poll` (`<ttl>`,
  `sy:updatePeriod`, skip hours and days) and `podcast` (persons, funding).
- New on items: `commentsUrl`, `image`, `durationSeconds` and `podcast`
  (transcripts, chapters, persons, soundbites). Alternate enclosures join
  `enclosures`. A Media RSS description is the content when there's no other.
- iTunes and Media RSS are read by `rome-modules` 2.1.0, now in `libs/`. A
  show's `itunes:image` is preferred as the feed's `image`.
- `srcset` candidates and `url()` in `style` attributes are made absolute.
- `fetchFeed()` reports `contentType`, `retryAfterSeconds` and the `Link`
  header's `links`, drops a redirect's default port, and with `parse: false`
  returns the bytes in `body` instead of a feed.
- `parseOpml()` and `toOpml()`: OPML subscription lists in and out, folders
  nested, read as safely as feeds are.

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
