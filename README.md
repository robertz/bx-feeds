# bx-feeds

RSS, Atom, JSON Feed and OPML for BoxLang, built for feed readers. `fetchFeed()` gets a feed with a conditional GET, `parseFeed()` turns it into one plain struct whatever the format, `findFeeds()` turns a pasted address into the feeds behind it, `parseOpml()` / `toOpml()` read and write subscription lists, and `webSub()` subscribes to a feed's hub so new posts are pushed to you. XML is parsed by [ROME](https://rometools.github.io/rome/), the Java feed library; the module adds what a reader needs on top of it.

- RSS 0.9x, 1.0 (RDF) and 2.0, Atom 0.3 and 1.0, and JSON Feed 1.0 and 1.1, all returned in the same shape.
- Every item has a **stable id** to dedupe on, even when the feed gives none.
- Dates are BoxLang datetimes in UTC, or null. A date that can't be read is null, never an error.
- Relative URLs in links, enclosures and HTML content come back absolute.
- Fetching sends `If-None-Match` / `If-Modified-Since`, follows redirects and tells you which were permanent, stops at a timeout and a maximum size, and refuses private network addresses.
- It copes with sites that make fetching hard: fallback User-Agents for ones that refuse yours, a flag for bot checks no fetch can pass, and a pause for a site that answers 429.
- What a reader schedules and subscribes with: the feed's own address, WebSub hubs, the next page, `<ttl>` and skip hours, `Retry-After`.
- Podcasts and video: durations, artwork, seasons and episodes, Media RSS thumbnails, and Podcasting 2.0 transcripts, chapters, people, funding, value and live items.
- No DTD is ever read, so XXE and entity-expansion attacks don't work. See [Security](#security).
- Real feeds are messy: whitespace before `<?xml`, a wrong declared encoding, UTF-8 encoded twice, an attribute repeated on the root element, HTML entities, an old DOCTYPE, a missing guid and a date in the wrong format are all read through.

Requires BoxLang **1.19+** (Java 21). The module ships its jars in `libs/`: ROME 2.1 with its modules, and JDOM 2. See [Dependencies](#dependencies).

## How it differs from `cffeed` and bx-rss

bx-compat-cfml's `new feed()` is a thin shim over a `bx:feed` component that the compat module doesn't contain; that component comes from Ortus's [bx-rss](https://github.com/ortus-boxlang/bx-rss), which also has an `rss()` BIF. bx-rss is a `cffeed` replacement: it reads a feed from a URL or a file into a query or an items array, understands iTunes and Media RSS tags, and can *create* feeds.

bx-feeds doesn't create feeds. It does the things a reader polls with, which bx-rss's documentation doesn't offer: conditional GET, a size limit, permanent-redirect reporting, parsing from a string or bytes you fetched yourself, JSON Feed, stable item ids, relative URL resolution, repairs for broken feeds, polling hints, Podcasting 2.0 tags, OPML, finding a site's feeds, WebSub, and tested protection against XML attacks. Use bx-rss to port `cffeed` code or publish a feed; use bx-feeds to subscribe to other people's.

## Install

```bash
install-bx-module bx-feeds        # into BoxLang HOME
install-bx-module bx-feeds --local  # into ./boxlang_modules
box install bx-feeds              # with CommandBox
```

To try a local checkout before it's on ForgeBox (`install-bx-module` only installs from ForgeBox), copy the module's files into your project's `boxlang_modules`:

```bash
mkdir -p boxlang_modules/bx-feeds && cp -R /path/to/bx-feeds/{ModuleConfig.bx,box.json,bifs,libs,models} boxlang_modules/bx-feeds/
```

A copy in BoxLang HOME (`~/.boxlang/modules`) wins over one in `./boxlang_modules`, so remove an older install there first.

## Settings

Set these in `boxlang.json`:

```json
"modules": {
	"bxFeeds": {
		"settings": {
			"userAgent": "Feedhouse/1.0 (+https://feedhouse.app)",
			"timeoutSeconds": 15
		}
	}
}
```

Or pass any of them in the options of one call: `fetchFeed( feedUrl, { timeoutSeconds: 5 } )`.

| Setting | Default | Meaning |
|---|---|---|
| `userAgent` | `"bx-feeds/<version> (+https://github.com/robertz/bx-feeds)"` | The `User-Agent` sent with every fetch. Set it to your app's name and a URL: publishers block clients they can't identify. |
| `timeoutSeconds` | `20` | The longest a whole fetch may take, redirects and body included. |
| `maxBytes` | `10485760` (10 MB) | The largest response body accepted, counted after gzip is undone. |
| `maxRedirects` | `5` | How many redirects to follow before giving up. |
| `fallbackUserAgents` | `[]` | User-Agents to try, in order, when a site refuses `userAgent` with a 401 or 403. Some sites let only browsers through, so a browser's User-Agent string here gets their feeds. See [Sites that make fetching hard](#sites-that-make-fetching-hard). |
| `pauseAfter429` | `true` | After a site answers a feed fetch with 429, leave it alone for a while: fetches of its feeds return a 429 marked `paused` without asking it. |
| `retryNotFound` | `{ pattern: "", delaysMs: [] }` | For hosts that now and then answer 404 for a feed that exists: an address matching `pattern` (a regular expression) that gets a 404 is asked again after each of `delaysMs`. |
| `allowPrivateAddresses` | `false` | Let `fetchFeed()` reach `localhost` and private, link-local and other non-public addresses. Leave it off wherever users choose what's fetched. Turn it on for feeds on your own network, and in tests against a local server. |

## Usage

### Parsing

`parseFeed( input, options = {} )` takes the feed as a string, as bytes, or as the path of a file.

```js
feed = parseFeed( bytes, { baseUrl: "https://example.com/blog/feed.xml", contentType: "text/xml; charset=ISO-8859-1" } )
```

| Option | Meaning |
|---|---|
| `baseUrl` | Where the feed came from. Relative URLs are resolved against it. Without it they are returned as written. |
| `contentType` | The HTTP `Content-Type` header the bytes came with, used to work out their charset. |
| `httpOnly` | `true` to take out every returned URL that isn't http(s): a single one becomes `""`, one in a list (`hubs`, `enclosures`, transcripts, funding) is dropped with its entry. URLs inside `contentHtml` and `summary` are left for your sanitizer, and ids aren't touched. |
| `collapseRevisions` | `true` to take the `#3` off an id that is the item's own link plus an edit number, as some news feeds write their guids. Without it every edit is a new item. |
| `maxItems` | Keep only the first so many items. `0`, the default, keeps them all. |
| `maxLength` | Refuse a document of more characters than this with `Feeds.ParseError`. `0`, the default, is no limit. |

It returns:

```js
{
	type        : "rss_2.0",       // rss_0.9, rss_0.91U, rss_0.92, rss_1.0, rss_2.0, atom_0.3, atom_1.0, json_1, json_1.1
	title       : "Example Show",
	link        : "https://example.com/",          // the site
	feedUrl     : "https://example.com/feed.xml",  // what the feed says its own address is
	description : "Two people talking",
	language    : "en-GB",
	updated     : {ts '2026-11-03 09:30:00'},      // UTC datetime or null
	image       : "https://example.com/art.jpg",
	hubs        : [ "https://hub.example/" ],      // WebSub
	nextUrl     : "https://example.com/feed.xml?page=2",
	poll        : { minutes: 180, skipHours: [ 3, 4 ], skipDays: [ "sunday" ] },
	podcast     : { author, owner, type, explicit, categories, persons, funding, ... },  // see Podcasts
	items       : [ {
		id          : "tag:example.com,2026:hello",
		title       : "Hello, world",
		link        : "https://example.com/hello",
		published   : {ts '2026-11-02 15:00:00'},  // UTC datetime or null
		updated     : null,                        // UTC datetime or null
		authors     : [ "Ada Lovelace" ],
		summary     : "A short hello.",
		contentHtml : "<p>The <em>full</em> hello.</p>",
		categories  : [ "News", "BoxLang" ],
		enclosures  : [ { url: "https://example.com/hello.mp3", type: "audio/mpeg", length: 34216300 } ],
		commentsUrl : "https://example.com/hello#comments",
		image       : "https://example.com/hello.jpg",
		durationSeconds : 2710,
		podcast     : { season, episode, episodeType, explicit, transcripts, chaptersUrl, persons, ... }  // see Podcasts
	} ]
}
```

Every key is always there, whatever the format. Text that's missing is `""`, a list that's missing is `[]`, a number that's unknown is `0` (an enclosure's `length`, `durationSeconds`, `poll.minutes`), and a date that's missing or unreadable is null. Test dates with `isNull( item.published )`: where bx-compat-cfml is loaded, `keyExists()` is false for a null.

**The feed**

- `link` is the site; `feedUrl` is the feed's `rel="self"` link (JSON `feed_url`), which can differ from where you fetched it.
- `hubs` are its WebSub hubs (`rel="hub"`, JSON `hubs`). `nextUrl` is the page of older entries: RFC 5005's `rel="next"`, else `rel="prev-archive"`, or JSON `next_url`.
- `poll.minutes` is how often the publisher says to check: RSS `<ttl>`, else `sy:updatePeriod` over `sy:updateFrequency`. `skipHours` (0 to 23, UTC) and `skipDays` (lowercase names) are RSS's. They are hints; a schedule that skips every hour or every day is ignored.
- `image` is a podcast's `itunes:image` when it has one, else the RSS `<image>`, the Atom logo or icon, or the JSON Feed icon.

**An item**

- `contentHtml` is the best body the item has: the full content (`content:encoded`, Atom `<content>`, JSON `content_html`) when there is one, otherwise the description, otherwise a Media RSS description (the only text a YouTube video has). Plain text (Atom `type="text"`, JSON `content_text`, Media RSS) is escaped into HTML. `summary` is the feed's own summary or description as it was written, so for an RSS item with only a `<description>` the two are the same.
- `published` and `updated` are what the feed said, with no filling in. Many Atom feeds only have `updated`, so a reader wants `item.published ?: item.updated`.
- `title` is plain text: entities are decoded (once more than XML does, since many feeds escape twice), and tags are stripped only from a title the feed declares as HTML, so `<input> considered harmful` keeps its brackets.
- `authors` and `categories` are trimmed, entity-decoded names with repeats dropped. RSS's `ada@example.com (Ada Lovelace)` becomes `Ada Lovelace`.
- `enclosures` are in feed order, with `podcast:alternateEnclosure` files after the item's own. Choosing which to play is yours.
- `commentsUrl` is RSS `<comments>`, or an Atom `rel="replies"` link to a page.
- `image` is the episode's `itunes:image`, else a Media RSS thumbnail or image, or JSON `image` / `banner_image`. Pictures inside the content aren't looked at.
- `durationSeconds` is from `itunes:duration` (`2710`, `45:10` or `0:45:10`) or a JSON attachment's `duration_in_seconds`. A day or more is taken as a typo and returned as 0.

**Podcasts.** Every feed and every item has a `podcast` struct with the same keys, empty when the feed isn't a podcast. iTunes tags and [Podcasting 2.0](https://podcastindex.org/namespace/1.0) tags are read into it:

```js
feed.podcast = {
	author     : "Example Media",                       // itunes:author
	owner      : { name: "Olive Owner", email: "olive@example.com" },
	type       : "episodic",                            // or "serial": play oldest first
	explicit   : false,
	complete   : false,                                 // true: no more episodes are coming
	newFeedUrl : "",                                    // itunes:new-feed-url: the show has moved here
	categories : [ "Technology", "Technology > Tech News" ],
	guid       : "917393e3-1b1e-5cef-ace4-edaa54e1f810", // podcast:guid, the same in every copy of the feed
	locked     : true,                                  // podcast:locked: don't import this feed elsewhere
	medium     : "podcast",                             // or music, video, audiobook, newsletter...
	location   : { name: "Austin, TX", geo: "geo:30.2672,97.7431", osm: "R113314" },
	persons    : [ { name: "Ada Host", role: "host", url: "", image: "" } ],
	funding    : [ { url: "https://example.com/support", label: "Support the show" } ],
	value      : { type: "lightning", method: "keysend", suggested: 0.00000005,
	               recipients: [ { name, type, address, split, fee, customKey, customValue } ] },
	liveItems  : [ { status: "live", start, end, id, title, link, enclosures, contentLinks: [ { url, label } ] } ]
}

item.podcast = {
	season      : 2,                                    // 0 when the episode doesn't say
	episode     : 5,
	episodeType : "full",                               // or "trailer", "bonus"
	explicit    : false,
	transcripts : [ { url: "https://example.com/5.vtt", type: "text/vtt" } ],  // all of them, in feed order
	chaptersUrl : "https://example.com/5.chapters.json",
	persons     : [ { name: "Grace Guest", role: "guest", url: "", image: "" } ],
	soundbites  : [ { startTime: 73.5, duration: 60, title: "The best minute" } ],
	location    : { name: "", geo: "", osm: "" },
	value       : { type: "", method: "", suggested: 0, recipients: [] }
}
```

A person's `role` is `"host"` when the feed doesn't give one. `season` and `episode` come from `podcast:season` and `podcast:episode` when the feed has them, else from the iTunes tags. A live item's `start` and `end` are UTC datetimes or null; live items are not in `items`. An item's `persons`, `location` and `value` are its own: when they're empty, the show's apply.

**Dates.** ROME reads RFC 822 and ISO 8601 dates. A date in neither is tried against a list of formats seen in real feeds: full day and month names, `2026-11-02 10:00:00` with or without an offset, `November 2, 2026 3:15 PM`, a day alone, C's `asctime`, and a few more. One without a zone is taken as UTC. Anything else is null.

**Repairs.** A feed XML parsers refuse is retried without an attribute repeated on its root element (two podcast plugins both declaring `xmlns:itunes`), then without a `<skipHours>` or `<skipDays>` ROME won't accept. A feed whose UTF-8 was encoded twice ("Itâ€™s") has its characters put back; only a document containing C1 control characters, which real text doesn't, is touched.

### Item ids

A reader dedupes on `item.id`, so the rule is fixed:

1. **The feed's own id, trimmed and otherwise untouched**: RSS `<guid>`, Atom `<id>`, RSS 1.0 `rdf:about`, JSON Feed `id`. A blank one counts as missing.
2. Otherwise **the item's link**, resolved against `baseUrl`.
3. With no link either, `"sha256:"` followed by the SHA-256 (lowercase hex) of the title, a newline, the published time as `2026-11-02T15:00:00Z` (or nothing), a newline, and the content.

Rule 2 means two things. Pass the same `baseUrl` every time you parse a feed (`fetchFeed()` does: the address that answered), or the ids of items with relative links will change. And two items without guids that share a link are one item to a reader. An id from rule 3 changes when the publisher edits the item.

Ids are unique within one feed at best, so store them per feed. Some feeds number each edit in the guid (`https://example.com/story#3`); pass `collapseRevisions: true` to keep those one item. Choose once: turning it on later changes the ids of such items.

### Fetching

`fetchFeed( feedUrl, options = {} )` fetches and parses in one call.

```js
result = fetchFeed( feed.url, { etag: feed.etag, lastModified: feed.lastModified } )

if ( len( result.permanentUrl ) ) {
	// the feed moved for good: save result.permanentUrl as its address
}
if ( result.notModified ) {
	// nothing new
} else if ( result.status == 200 ) {
	// result.feed is the parsed feed; save result.etag and result.lastModified for next time
} else {
	// 404, 410, 429, 500...: result.feed is null
}
```

| Option | Meaning |
|---|---|
| `etag`, `lastModified` | The values a previous fetch returned. They are sent as `If-None-Match` and `If-Modified-Since`. |
| `parse` | `false` to get a 200's bytes in `body` instead of a parsed `feed`: for a page you'll run `discoverFeeds()` on, or anything else you want fetched with the same limits. |
| Any module setting | Overrides it for this call: `userAgent`, `timeoutSeconds`, `maxBytes`, `maxRedirects`, `fallbackUserAgents`, `pauseAfter429`, `retryNotFound`, `allowPrivateAddresses`. |
| `accept` | An `Accept` header, for fetching something that isn't a feed. |
| `httpOnly`, `collapseRevisions`, `maxItems` | Passed on to the parser. See [Parsing](#parsing). |

| Result | Meaning |
|---|---|
| `status` | The HTTP status of the last response. |
| `notModified` | True for a 304. |
| `etag`, `lastModified` | The response's validators, as sent. On a 304 that repeats none, the ones you passed in. |
| `finalUrl` | The address that finally answered, after redirects. Relative URLs in the feed are resolved against it. A redirect's default port (`https://host:443/`) is dropped, so it's the address people type. |
| `permanentUrl` | Where the feed has permanently moved, or `""`. It's the end of the leading run of 301 and 308 redirects; a redirect after a temporary one (302, 303, 307) isn't counted, since the temporary hop may point elsewhere tomorrow. |
| `contentType` | The response's `Content-Type` header, or `""`. |
| `retryAfterSeconds` | How long the server asked to be left alone (`Retry-After`, sent as seconds or as a date), or 0. Worth honoring on a 429 or 503. |
| `maxAgeSeconds` | How long the server says its answer stays fresh: `Cache-Control: max-age`, else the time left until `Expires`, or 0 (also for `no-cache` and `no-store`). A reason not to poll sooner. |
| `challenged` | True when a refusal (401, 403, 429 or 503) is a bot check: Cloudflare's "Just a moment", or a CAPTCHA from DataDome, PerimeterX, reCAPTCHA or hCaptcha. No fetch can pass one, so retrying won't help. |
| `paused` | True when no request was made because the site is being left alone after a 429. `status` is 429 and `retryAfterSeconds` is how much longer. |
| `links` | The response's `Link` headers as `[ { url, rel } ]`, one entry per rel. Some feeds name their WebSub `hub` and `self` here rather than in the document. |
| `feed` | The `parseFeed()` struct on a 200. Null for any other status, and with `parse: false`. |
| `body` | The 200's bytes with `parse: false`. Null otherwise. |

Only `http` and `https` are fetched, and redirects to anything else are refused. Gzip is asked for and undone. Every address on the way, the first and each redirect's, must be a public one unless `allowPrivateAddresses` is set.

### Sites that make fetching hard

**Sites that refuse your User-Agent.** With `fallbackUserAgents` set, a 401 or 403 is asked again as each fallback in turn. The first one a host accepts is remembered, and later fetches to that host use it straight away; when your own `userAgent` works again, it's forgotten. With no fallbacks, or none accepted, you get the refusal as it came.

**Bot checks.** A refusal whose page is a bot check comes back with `challenged: true`. Fallbacks aren't tried on one, since it refuses every client alike. Tell the user the site wants a browser, rather than "feed not found".

**Sites that answer 429.** When a feed fetch gets a 429, the whole site is left alone: for as long as its `Retry-After` says (an hour at most), or 15 minutes when it doesn't say, doubling for each 429 in a row up to four hours. Until then `fetchFeed()` for any feed on that site returns at once with `status: 429` and `paused: true`, making no request. A site here is the registrable domain, so every `*.tumblr.com` blog shares one pause, as they share one limit. The first 200 or 304 resets the doubling. A 429 for a fetch with `parse: false` (a page, an image) doesn't pause anything, and such fetches aren't held back. Turn all of it off with `pauseAfter429: false`.

**Hosts that answer 404 by mistake.** `retryNotFound: { pattern: "^https://www\.youtube\.com/feeds/", delaysMs: [ 500, 2000 ] }` asks a matching address again after each delay while it keeps answering 404. Everything stays inside `timeoutSeconds`.

What's remembered (accepted User-Agents, pauses) is held in memory and shared by every fetch in the BoxLang runtime; it's gone on restart, and isn't shared between servers. The model shows and clears it:

```js
fetcher = new bxModules.bxFeeds.models.FeedFetcher()
fetcher.pausedSites()                      // [ { site: "tumblr.com", seconds: 840, refusals: 1 } ], soonest back first
fetcher.pausedSeconds( feedUrl )           // 0 when the site may be asked now
fetcher.endPause( feedUrl )                // ask again now, keeping count of its 429s
fetcher.forget( feedUrl )                  // forget this site's pause, count and accepted User-Agent
fetcher.forget()                           // forget everything
```

### Finding a site's feeds

`findFeeds( pageUrl, options = {} )` is for an "add a feed" box: give it whatever was pasted and it returns the feeds behind it, each one fetched and parsed to make sure.

```js
findFeeds( "example.com/blog", { userAgent: "Feedhouse/1.0 (+https://feedhouse.app)" } )
// [ { url: "https://example.com/feed.xml", title: "Example Blog", link: "https://example.com/", type: "rss_2.0", source: "advertised" } ]
```

It tries four things in order, and the first that finds anything ends the search:

| `source` | What |
|---|---|
| `itself` | The address is already a feed. |
| `advertised` | The feeds its page links with `<link rel="alternate">`: up to five, every one that really is a feed. |
| `pattern` | A site whose feed address follows from the page's: a Reddit subreddit or user, a GitHub repository (its releases) or user, a Mastodon profile or hashtag. |
| `path` | The paths feeds usually live at (`/feed`, `/rss`, `/feed.xml`, `/rss.xml`, `/atom.xml`, `/index.xml`, `/feed.json` and two more), stopping at the first that works. |

An address without a scheme is taken as `https://`. A feed's `url` is the one asked for, unless the server said it has permanently moved. Nothing found is an empty array. A page that can't be reached at all throws `Feeds.FetchError`; a candidate that can't is skipped.

`options` takes everything `fetchFeed()` does, applied to every request, plus `budgetSeconds` (60 by default): the longest the whole search may take. At worst it makes about sixteen requests, all to the site you named or to addresses its page gave, each held to the same limits and the same private-address check as any fetch.

### Discovering feeds in a page you have

`discoverFeeds( html, baseUrl = "" )` is the step of `findFeeds()` that reads the page, for when you fetched it yourself. It returns the feeds the page links with `<link rel="alternate">`, in page order, with repeats dropped:

```js
discoverFeeds( html, "https://example.com/blog/" )
// [ { url: "https://example.com/feed.xml", type: "application/rss+xml", title: "Posts" } ]
```

It recognizes `application/rss+xml`, `application/atom+xml`, `application/feed+json` and `application/json`, and honors a `<base href>` in the page. It reads the tags with a pattern rather than an HTML parser, which is enough for `<link>` tags. It makes no requests, so nothing it returns has been checked.

### OPML

`parseOpml( input )` reads a subscription list from a string, bytes or a file path. Folders stay nested as they are in the file:

```js
list = parseOpml( fileRead( "subscriptions.opml" ) )
// { title: "My feeds", outlines: [
//   { title: "Example", feedUrl: "https://example.com/feed.xml", siteUrl: "https://example.com/", outlines: [] },
//   { title: "News", feedUrl: "", siteUrl: "", outlines: [ { title: "Daily", feedUrl: "https://news.example/rss", ... } ] }
// ] }
```

An outline with a `feedUrl` is a subscription. One without is a folder, and its `outlines` are what's in it. Addresses are returned as written: check they are http(s) before you subscribe to them. An `&` the exporter forgot to escape is read through.

`toOpml( list, title = "" )` writes OPML 2.0 from the same shape, or from just an array of outlines:

```js
xml = toOpml( [ { title: "News", outlines: [ { title: "Daily", feedUrl: "https://news.example/rss" } ] } ], "My feeds" )
```

### WebSub

A feed with a hub (`feed.hubs`) can push new posts to you the moment they're published, instead of you polling for them. `webSub( overrides = {} )` returns the subscriber's side of [WebSub](https://www.w3.org/TR/websub/) (and PubSubHubbub before it). You keep the state and serve the callback address; it does the protocol. There are three moments:

```js
hub = webSub()

// 1. Ask the hub to push. Keep the secret with the subscription.
secret = hub.newSecret()
answer = hub.subscribe( feed.hubs[ 1 ], feed.feedUrl, "https://example.com/websub/#token#", { secret: secret } )
// { accepted: true, status: 202, body: "" }

// 2. The hub checks with a GET to your callback. Echo its challenge, or refuse.
check = hub.challenge( queryParams, feed.feedUrl )
// { mode: "subscribe", accepted: true, challenge: "...", leaseSeconds: 864000, reason: "" }
if ( check.accepted ) {
	// reply 200 with check.challenge as the body; you're subscribed for check.leaseSeconds
} else {
	// reply 404; when check.mode is "denied" the hub refused, and check.reason says why
}

// 3. The hub POSTs new content to your callback. Reply 2xx either way; use it only if it's signed.
if ( hub.isSigned( rawBody, headers[ "X-Hub-Signature" ], secret ) ) {
	feed = parseFeed( rawBody, { baseUrl: feedUrl } )
}
```

- `subscribe( hubUrl, topicUrl, callbackUrl, options )`: the topic is the feed's own address, its `feedUrl`. `options.leaseSeconds` (10 days by default) is a request; the hub decides, and tells you in step 2. Renew before the lease runs out by subscribing again. `unsubscribe( hubUrl, topicUrl, callbackUrl )` asks the hub to stop; it checks that the same way, with mode `"unsubscribe"`, and `accepted` only says the request is well-formed: agree only if you really want to stop.
- Put something unguessable in each callback address (the `token` above) so you can tell which subscription a request is for, and so nobody else can find it.
- `isSigned( body, signature, secret )` takes the body exactly as it arrived, as bytes or a string, and the `X-Hub-Signature` header (`sha1=`, `sha256=`, `sha384=` or `sha512=` and a hex HMAC). It compares in constant time. Without a secret nothing counts as signed, so always subscribe with one.
- Requests to the hub use the module's `userAgent` and `timeoutSeconds`, don't follow redirects, and refuse private addresses unless `allowPrivateAddresses` is set. Pass overrides to `webSub( { ... } )`.
- A pushed body may hold only the new items, so merge it into what you have rather than replacing it. Keep polling too, less often: hubs fail quietly.

### Errors

| Type | When |
|---|---|
| `Feeds.ParseError` | The input isn't a readable feed or OPML file: garbage bytes, HTML, broken XML, JSON that isn't a JSON Feed, a path that isn't a file. `message` is safe to show; `detail` has the parser's reason. |
| `Feeds.FetchError` | The feed couldn't be fetched: DNS, a refused connection, TLS, an address that isn't http(s). `detail` has the reason. |
| `Feeds.FetchError.Timeout` | The fetch took longer than `timeoutSeconds`. |
| `Feeds.FetchError.TooLarge` | The body is over `maxBytes`. |
| `Feeds.FetchError.TooManyRedirects` | More than `maxRedirects` redirects. |
| `Feeds.FetchError.PrivateAddress` | The address, or one it redirected to, isn't a public one and `allowPrivateAddresses` is off. |

`catch ( "Feeds.FetchError" e )` catches all five fetch errors. An HTTP error status is not an exception: it comes back in `result.status`.

### The models

The BIFs are thin wrappers over six classes you can also use directly:

```js
parser    = new bxModules.bxFeeds.models.FeedParser()                       // .parse( input, options )
fetcher   = new bxModules.bxFeeds.models.FeedFetcher( { userAgent: "Mine/1.0" } )  // .fetch( feedUrl, options )
discovery = new bxModules.bxFeeds.models.FeedDiscovery()                    // .discover( html, baseUrl )
finder    = new bxModules.bxFeeds.models.FeedFinder( { userAgent: "Mine/1.0" } )   // .find( pageUrl, options )
opml      = new bxModules.bxFeeds.models.Opml()                             // .parse( input ), .build( list, title )
hub       = new bxModules.bxFeeds.models.WebSub()                           // .subscribe(), .unsubscribe(), .challenge(), .isSigned()
```

### Runnable example

`examples/smoke.bxs` parses a feed, fetches one twice and finds one from a page, all from a server it starts on a free local port, writes and reads an OPML list, and checks a WebSub signature:

```bash
boxlang examples/smoke.bxs
```

## Security

**XML attacks.** Feeds and OPML files are XML from strangers. The module never reads a DTD: a DOCTYPE at the top of the document is cut out before parsing (old RSS 0.91 feeds carry one, and are still read), and the XML parser is told to refuse any DOCTYPE that remains. So entities a DTD would define don't exist: an external entity (XXE) can't read a file or call a server, an external DTD isn't fetched, and a "billion laughs" entity bomb fails at once instead of expanding. A document that uses such an entity throws `Feeds.ParseError`. The standard HTML entities (`&nbsp;`, `&copy;`...) still work in feeds; ROME replaces them itself. `tests/specs/SecuritySpec.bx` proves each of these against a canary file and a local server.

**HTML is not sanitized.** `contentHtml` and `summary` are returned as the feed wrote them, with only relative URLs made absolute. They can contain `<script>`, event handlers, `javascript:` links and tracking pixels. Sanitize them before you show them (that's another module's job). `title`, authors and categories are plain text, which can contain `<` and `&`: escape them on output like any other text.

**URLs are as the feed wrote them, unless you ask.** Every URL the module returns (`link`, `image`, enclosures, `podcast.persons[].url`...) is whatever the feed said, resolved. It may be `javascript:` or `file:`. Pass `httpOnly: true` to `parseFeed()` or `fetchFeed()` to have every one that isn't http(s) taken out. OPML addresses are always as written: check them before you subscribe.

**Private addresses.** `fetchFeed()` refuses an address that isn't on the public internet: loopback, private and link-local ranges (including cloud metadata at `169.254.169.254`), carrier-grade NAT, reserved ranges, and IPv6 forms that carry or tunnel to one of those. The check is made for the first address and for every redirect. It resolves the host and then connects, relying on the JVM's DNS cache (30 seconds by default) to connect to what it checked; if you've turned that cache off, a hostile DNS server could answer differently the second time, and an egress proxy is the stronger defense.

**WebSub.** Anyone who learns a callback address can POST to it. Treat a push as a feed from a stranger: accept it only when `isSigned()` says so, which needs a secret at subscribe time, and parse it with the same care as any other. Give each subscription its own secret and its own unguessable callback.

**Fallback User-Agents** make your fetcher claim to be something it isn't. Sites that block feed readers sometimes mean to; use a fallback for getting feeds a site publishes for the public, not for getting around a block on purpose.

**Limits.** `timeoutSeconds` bounds the whole fetch, so a server that trickles bytes can't hold a worker. `maxBytes` is counted after decompression, so a gzip bomb is cut off too. When you parse a document you got some other way, `maxLength` and `maxItems` do the same job for `parseFeed()`.

## Not yet

- The rest of Media RSS (ratings, credits, keywords) and of Podcasting 2.0 (value time splits, trailers, licenses, `podcast:txt`, remote items).
- Picking a transcript or an enclosure for you, and taking an item's image from its content: those are a reader's choices.
- Dates in other languages, and ambiguous ones like `02/11/2026`.
- Sharing pauses and accepted User-Agents between servers, or keeping them across a restart.
- More site patterns for `findFeeds()` (YouTube handles, Substack, Medium).
- Publishing to a hub, and storing WebSub subscriptions: the module does the protocol, the state is yours.
- Polling, scheduling, HTML sanitizing and full-text extraction belong in the app or another module, not here.

## Dependencies

`libs/` holds these jars from Maven Central, fetched and checked against Central's SHA-1 by `scripts/fetch-libs.sh`:

| Jar | Version | License |
|---|---|---|
| `com.rometools:rome` | 2.1.0 | Apache 2.0 |
| `com.rometools:rome-utils` | 2.1.0 | Apache 2.0 |
| `com.rometools:rome-modules` | 2.1.0 | Apache 2.0 |
| `org.jdom:jdom2` | 2.0.6.1 | Apache-style (JDOM) |

That's everything ROME needs at runtime. Its other dependency, SLF4J, is already inside BoxLang, and JDOM's own dependencies (Jaxen, Xerces, Xalan) are optional and unused: XML is parsed by the JDK. `rome-modules` reads iTunes and Media RSS tags and needs nothing beyond ROME. None of these jars' packages (`com.rometools`, `org.jdom2`) are in the BoxLang runtime jar, so nothing clashes.

Three things come from BoxLang or the JDK rather than a jar:

- Fetching uses the JDK's `HttpURLConnection`.
- JSON Feed uses BoxLang's `jsonDeserialize()`.
- HTML entities in titles are decoded by the Apache commons-text inside the BoxLang runtime (`StringEscapeUtils.unescapeHtml4`). It knows the HTML 4 entities and numeric references, not names HTML5 added such as `&apos;`. jsoup would know them all, and was tried: with the bx-jsoup module installed, BoxLang handed this module bx-jsoup's bundled jsoup instead of its own, so a version shipped here couldn't be relied on. If a future BoxLang drops commons-text, titles will need another decoder.

`rome-modules` logs a warning with a stack trace for each tag it skips, such as an empty `<media:content/>`. The parser turns its logger down to errors when BoxLang's logging is Logback, as it is by default.

Calling Java from BoxLang, as checked on 1.19: a BoxLang closure passed where Java expects a functional interface is converted automatically. That held for `java.util.function.Function`, `Supplier` and `Predicate`, and for `com.sun.net.httpserver.HttpHandler` (the specs' local server, whose handler runs on Java's own threads). No `createDynamicProxy()` was needed. The module's own code calls ROME with plain method calls and passes it no callbacks. One trap: a method of your own named like a BoxLang BIF (`attempt()`, say) calls the BIF.

To update, change the versions in `scripts/fetch-libs.sh`, run it, run the specs, and commit `libs/`.

## Development

```bash
box install                 # TestBox and bx-compat-cfml
bash scripts/test.sh        # sets up the test homes on first run, then runs the specs in each
```

The specs run in two BoxLang homes of their own: `.tmp/bxhome` (this checkout) and `.tmp/bxhome-compat` (the same plus bx-compat-cfml, which changes how nulls behave). A bx-feeds installed in `~/.boxlang/modules` can't stand in for the code under test. No spec uses the network: feeds come from `tests/resources/`, and the fetch specs talk to a server started on a random free port, with `allowPrivateAddresses` on.

## License

MIT
