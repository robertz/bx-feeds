# bx-feeds

RSS, Atom, JSON Feed and OPML for BoxLang, built for feed readers. `fetchFeed()` gets a feed with a conditional GET, `parseFeed()` turns it into one plain struct whatever the format, `discoverFeeds()` finds the feeds a web page advertises, and `parseOpml()` / `toOpml()` read and write subscription lists. XML is parsed by [ROME](https://rometools.github.io/rome/), the Java feed library; the module adds what a reader needs on top of it.

- RSS 0.9x, 1.0 (RDF) and 2.0, Atom 0.3 and 1.0, and JSON Feed 1.0 and 1.1, all returned in the same shape.
- Every item has a **stable id** to dedupe on, even when the feed gives none.
- Dates are BoxLang datetimes in UTC, or null. A date that can't be read is null, never an error.
- Relative URLs in links, enclosures and HTML content come back absolute.
- Fetching sends `If-None-Match` / `If-Modified-Since`, follows redirects and tells you which were permanent, stops at a timeout and a maximum size, and refuses private network addresses.
- What a reader schedules and subscribes with: the feed's own address, WebSub hubs, the next page, `<ttl>` and skip hours, `Retry-After`.
- Podcasts and video: durations, artwork, Media RSS thumbnails, and Podcasting 2.0 transcripts, chapters, people and funding.
- No DTD is ever read, so XXE and entity-expansion attacks don't work. See [Security](#security).
- Real feeds are messy: whitespace before `<?xml`, a wrong declared encoding, UTF-8 encoded twice, an attribute repeated on the root element, HTML entities, an old DOCTYPE, a missing guid and a date in the wrong format are all read through.

Requires BoxLang **1.19+** (Java 21). The module ships its jars in `libs/`: ROME 2.1 with its modules, and JDOM 2. See [Dependencies](#dependencies).

## How it differs from `cffeed` and bx-rss

bx-compat-cfml's `new feed()` is a thin shim over a `bx:feed` component that the compat module doesn't contain; that component comes from Ortus's [bx-rss](https://github.com/ortus-boxlang/bx-rss), which also has an `rss()` BIF. bx-rss is a `cffeed` replacement: it reads a feed from a URL or a file into a query or an items array, understands iTunes and Media RSS tags, and can *create* feeds.

bx-feeds doesn't create feeds. It does the things a reader polls with, which bx-rss's documentation doesn't offer: conditional GET, a size limit, permanent-redirect reporting, parsing from a string or bytes you fetched yourself, JSON Feed, stable item ids, relative URL resolution, repairs for broken feeds, polling hints, Podcasting 2.0 tags, OPML, feed autodiscovery, and tested protection against XML attacks. Use bx-rss to port `cffeed` code or publish a feed; use bx-feeds to subscribe to other people's.

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
	podcast     : { persons: [ { name, role, url, image } ], funding: [ { url, label } ] },
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
		podcast     : {
			transcripts : [ { url, type } ],
			chaptersUrl : "https://example.com/hello.chapters.json",
			persons     : [ { name, role, url, image } ],
			soundbites  : [ { startTime, duration, title } ]
		}
	} ]
}
```

Every key is always there, whatever the format. Text that's missing is `""`, a list that's missing is `[]`, a number that's unknown is `0` (an enclosure's `length`, `durationSeconds`, `poll.minutes`), and a date that's missing or unreadable is null. Test dates with `isNull( item.published )`: where bx-compat-cfml is loaded, `keyExists()` is false for a null.

**The feed**

- `link` is the site; `feedUrl` is the feed's `rel="self"` link (JSON `feed_url`), which can differ from where you fetched it.
- `hubs` are its WebSub hubs (`rel="hub"`, JSON `hubs`). `nextUrl` is the page of older entries: RFC 5005's `rel="next"`, else `rel="prev-archive"`, or JSON `next_url`.
- `poll.minutes` is how often the publisher says to check: RSS `<ttl>`, else `sy:updatePeriod` over `sy:updateFrequency`. `skipHours` (0 to 23, UTC) and `skipDays` (lowercase names) are RSS's. They are hints; a schedule that skips every hour or every day is ignored.
- `image` is a podcast's `itunes:image` when it has one, else the RSS `<image>`, the Atom logo or icon, or the JSON Feed icon.
- `podcast.persons` and `podcast.funding` are the channel's `podcast:person` and `podcast:funding`. A `role` that isn't given is `"host"`.

**An item**

- `contentHtml` is the best body the item has: the full content (`content:encoded`, Atom `<content>`, JSON `content_html`) when there is one, otherwise the description, otherwise a Media RSS description (the only text a YouTube video has). Plain text (Atom `type="text"`, JSON `content_text`, Media RSS) is escaped into HTML. `summary` is the feed's own summary or description as it was written, so for an RSS item with only a `<description>` the two are the same.
- `published` and `updated` are what the feed said, with no filling in. Many Atom feeds only have `updated`, so a reader wants `item.published ?: item.updated`.
- `title` is plain text: entities are decoded (once more than XML does, since many feeds escape twice), and tags are stripped only from a title the feed declares as HTML, so `<input> considered harmful` keeps its brackets.
- `authors` and `categories` are trimmed, entity-decoded names with repeats dropped. RSS's `ada@example.com (Ada Lovelace)` becomes `Ada Lovelace`.
- `enclosures` are in feed order, with `podcast:alternateEnclosure` files after the item's own. Choosing which to play is yours.
- `commentsUrl` is RSS `<comments>`, or an Atom `rel="replies"` link to a page.
- `image` is the episode's `itunes:image`, else a Media RSS thumbnail or image, or JSON `image` / `banner_image`. Pictures inside the content aren't looked at.
- `durationSeconds` is from `itunes:duration` (`2710`, `45:10` or `0:45:10`) or a JSON attachment's `duration_in_seconds`. A day or more is taken as a typo and returned as 0.
- `podcast` holds Podcasting 2.0's `podcast:transcript` (all of them, in feed order), `podcast:chapters`, `podcast:person` and `podcast:soundbite`.

**Dates.** ROME reads RFC 822 and ISO 8601 dates. A date in neither is tried against a list of formats seen in real feeds: full day and month names, `2026-11-02 10:00:00` with or without an offset, `November 2, 2026 3:15 PM`, a day alone, C's `asctime`, and a few more. One without a zone is taken as UTC. Anything else is null.

**Repairs.** A feed XML parsers refuse is retried without an attribute repeated on its root element (two podcast plugins both declaring `xmlns:itunes`), then without a `<skipHours>` or `<skipDays>` ROME won't accept. A feed whose UTF-8 was encoded twice ("Itâ€™s") has its characters put back; only a document containing C1 control characters, which real text doesn't, is touched.

### Item ids

A reader dedupes on `item.id`, so the rule is fixed:

1. **The feed's own id, trimmed and otherwise untouched**: RSS `<guid>`, Atom `<id>`, RSS 1.0 `rdf:about`, JSON Feed `id`. A blank one counts as missing.
2. Otherwise **the item's link**, resolved against `baseUrl`.
3. With no link either, `"sha256:"` followed by the SHA-256 (lowercase hex) of the title, a newline, the published time as `2026-11-02T15:00:00Z` (or nothing), a newline, and the content.

Rule 2 means two things. Pass the same `baseUrl` every time you parse a feed (`fetchFeed()` does: the address that answered), or the ids of items with relative links will change. And two items without guids that share a link are one item to a reader. An id from rule 3 changes when the publisher edits the item.

Ids are unique within one feed at best, so store them per feed. Some feeds number each edit in the guid (`https://example.com/story#3`); if you want those to stay one item, strip the number before you store the id.

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
| `userAgent`, `timeoutSeconds`, `maxBytes`, `maxRedirects`, `allowPrivateAddresses` | Override the module settings for this call. |

| Result | Meaning |
|---|---|
| `status` | The HTTP status of the last response. |
| `notModified` | True for a 304. |
| `etag`, `lastModified` | The response's validators, as sent. On a 304 that repeats none, the ones you passed in. |
| `finalUrl` | The address that finally answered, after redirects. Relative URLs in the feed are resolved against it. A redirect's default port (`https://host:443/`) is dropped, so it's the address people type. |
| `permanentUrl` | Where the feed has permanently moved, or `""`. It's the end of the leading run of 301 and 308 redirects; a redirect after a temporary one (302, 303, 307) isn't counted, since the temporary hop may point elsewhere tomorrow. |
| `contentType` | The response's `Content-Type` header, or `""`. |
| `retryAfterSeconds` | How long the server asked to be left alone (`Retry-After`, sent as seconds or as a date), or 0. Worth honoring on a 429 or 503. |
| `links` | The response's `Link` headers as `[ { url, rel } ]`, one entry per rel. Some feeds name their WebSub `hub` and `self` here rather than in the document. |
| `feed` | The `parseFeed()` struct on a 200. Null for any other status, and with `parse: false`. |
| `body` | The 200's bytes with `parse: false`. Null otherwise. |

Only `http` and `https` are fetched, and redirects to anything else are refused. Gzip is asked for and undone. Every address on the way, the first and each redirect's, must be a public one unless `allowPrivateAddresses` is set.

### Discovering feeds

`discoverFeeds( html, baseUrl = "" )` returns the feeds a page links with `<link rel="alternate">`, in page order, with repeats dropped:

```js
discoverFeeds( html, "https://example.com/blog/" )
// [ { url: "https://example.com/feed.xml", type: "application/rss+xml", title: "Posts" } ]
```

It recognizes `application/rss+xml`, `application/atom+xml`, `application/feed+json` and `application/json`, and honors a `<base href>` in the page. It reads the tags with a pattern rather than an HTML parser, which is enough for `<link>` tags. It doesn't fetch the page or guess at addresses like `/feed`.

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

The BIFs are thin wrappers over four classes you can also use directly:

```js
parser    = new bxModules.bxFeeds.models.FeedParser()                       // .parse( input, options )
fetcher   = new bxModules.bxFeeds.models.FeedFetcher( { userAgent: "Mine/1.0" } )  // .fetch( feedUrl, options )
discovery = new bxModules.bxFeeds.models.FeedDiscovery()                    // .discover( html, baseUrl )
opml      = new bxModules.bxFeeds.models.Opml()                             // .parse( input ), .build( list, title )
```

### Runnable example

`examples/smoke.bxs` parses a feed, discovers one, fetches one twice from a server it starts on a free local port, and writes and reads an OPML list:

```bash
boxlang examples/smoke.bxs
```

## Security

**XML attacks.** Feeds and OPML files are XML from strangers. The module never reads a DTD: a DOCTYPE at the top of the document is cut out before parsing (old RSS 0.91 feeds carry one, and are still read), and the XML parser is told to refuse any DOCTYPE that remains. So entities a DTD would define don't exist: an external entity (XXE) can't read a file or call a server, an external DTD isn't fetched, and a "billion laughs" entity bomb fails at once instead of expanding. A document that uses such an entity throws `Feeds.ParseError`. The standard HTML entities (`&nbsp;`, `&copy;`...) still work in feeds; ROME replaces them itself. `tests/specs/SecuritySpec.bx` proves each of these against a canary file and a local server.

**HTML is not sanitized.** `contentHtml` and `summary` are returned as the feed wrote them, with only relative URLs made absolute. They can contain `<script>`, event handlers, `javascript:` links and tracking pixels. Sanitize them before you show them (that's another module's job). `title`, authors and categories are plain text, which can contain `<` and `&`: escape them on output like any other text.

**URLs are not vetted.** Every URL the module returns (`link`, `image`, enclosures, `podcast.persons[].url`, OPML's `feedUrl`...) is whatever the feed said, resolved. It may be `javascript:` or `file:`. Check the scheme before you link to one or fetch it.

**Private addresses.** `fetchFeed()` refuses an address that isn't on the public internet: loopback, private and link-local ranges (including cloud metadata at `169.254.169.254`), carrier-grade NAT, reserved ranges, and IPv6 forms that carry or tunnel to one of those. The check is made for the first address and for every redirect. It resolves the host and then connects, relying on the JVM's DNS cache (30 seconds by default) to connect to what it checked; if you've turned that cache off, a hostile DNS server could answer differently the second time, and an egress proxy is the stronger defense.

**Limits.** `timeoutSeconds` bounds the whole fetch, so a server that trickles bytes can't hold a worker. `maxBytes` is counted after decompression, so a gzip bomb is cut off too. The parser itself has no size limit: if you parse bytes you fetched yourself, limit them yourself.

## Not yet

- The rest of iTunes and Media RSS (explicit flags, seasons and episode numbers, keywords, ratings, credits) and of Podcasting 2.0 (value, location, live items).
- Picking a transcript or an enclosure for you, and taking an item's image from its content: those are a reader's choices.
- Collapsing guids that number each edit (`#3`).
- Dates in other languages, and ambiguous ones like `02/11/2026`.
- `Cache-Control` and `Expires` from the response.
- Fallback User-Agents, remembering a site's 429s, and telling a bot check from a refusal.
- Probing a site for feeds it doesn't advertise (`/feed`, `/rss.xml`).
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
