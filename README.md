# bx-feeds

RSS, Atom and JSON Feed for BoxLang, built for feed readers. Three functions: `fetchFeed()` gets a feed with a conditional GET, `parseFeed()` turns it into one plain struct whatever the format, and `discoverFeeds()` finds the feeds a web page advertises. XML is parsed by [ROME](https://rometools.github.io/rome/), the Java feed library; the module adds what a reader needs on top of it.

- RSS 0.9x, 1.0 (RDF) and 2.0, Atom 0.3 and 1.0, and JSON Feed 1.0 and 1.1, all returned in the same shape.
- Every item has a **stable id** to dedupe on, even when the feed gives none.
- Dates are BoxLang datetimes in UTC, or null. A date that can't be read is null, never an error.
- Relative URLs in links, enclosures and HTML content come back absolute.
- Fetching sends `If-None-Match` / `If-Modified-Since`, follows redirects and tells you which were permanent, and stops at a timeout and a maximum size.
- No DTD is ever read, so XXE and entity-expansion attacks don't work. See [Security](#security).
- Real feeds are messy: whitespace before `<?xml`, a wrong declared encoding, HTML entities, an old DOCTYPE, a missing guid and a bad date are all read through.

Requires BoxLang **1.19+** (Java 21). The module ships its jars in `libs/`: ROME 2.1 and JDOM 2. See [Dependencies](#dependencies).

## How it differs from `cffeed` and bx-rss

bx-compat-cfml's `new feed()` is a thin shim over a `bx:feed` component that the compat module doesn't contain; that component comes from Ortus's [bx-rss](https://github.com/ortus-boxlang/bx-rss), which also has an `rss()` BIF. bx-rss is a `cffeed` replacement: it reads a feed from a URL or a file into a query or an items array, understands iTunes and Media RSS tags, and can *create* feeds.

bx-feeds doesn't create feeds and doesn't read iTunes or Media RSS tags. It does the things a reader polls with, which bx-rss's documentation doesn't offer: conditional GET, a size limit, permanent-redirect reporting, parsing from a string or bytes you fetched yourself, JSON Feed, stable item ids, relative URL resolution, feed autodiscovery, and tested protection against XML attacks. Use bx-rss to port `cffeed` code or publish a feed; use bx-feeds to subscribe to other people's.

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
	title       : "Example Blog",
	link        : "https://example.com/",    // the site, not the feed
	description : "Notes on things",
	language    : "en-GB",
	updated     : {ts '2026-11-03 09:30:00'}, // UTC datetime or null
	image       : "https://example.com/icon.png",
	items       : [ {
		id          : "tag:example.com,2026:hello",
		title       : "Hello, world",
		link        : "https://example.com/hello",
		published   : {ts '2026-11-02 15:00:00'}, // UTC datetime or null
		updated     : null,                       // UTC datetime or null
		authors     : [ "Ada Lovelace" ],
		summary     : "A short hello.",
		contentHtml : "<p>The <em>full</em> hello.</p>",
		categories  : [ "News", "BoxLang" ],
		enclosures  : [ { url: "https://example.com/hello.mp3", type: "audio/mpeg", length: 34216300 } ]
	} ]
}
```

Every key is always there. Text that's missing is `""`, a list that's missing is `[]`, an enclosure of unknown size has `length: 0`, and a date that's missing or unreadable is null. Test dates with `isNull( item.published )`: where bx-compat-cfml is loaded, `keyExists()` is false for a null.

- `contentHtml` is the best body the item has: the full content (`content:encoded`, Atom `<content>`, JSON `content_html`) when there is one, otherwise the description. Plain text (Atom `type="text"`, JSON `content_text`) is escaped into HTML. `summary` is the feed's own summary or description as it was written, so for an RSS item with only a `<description>` the two are the same.
- `published` and `updated` are what the feed said, with no filling in. Many Atom feeds only have `updated`, so a reader wants `item.published ?: item.updated`.
- `authors` and `categories` are trimmed names with repeats dropped. An RSS `<author>` is returned as written, which is often `email (Name)`.
- `title` is returned as the feed gave it. It can hold entities or tags when the publisher escaped it twice.
- `image` is the RSS `<image>`, the Atom logo or icon, a podcast's `itunes:image`, or the JSON Feed icon.

### Item ids

A reader dedupes on `item.id`, so the rule is fixed:

1. **The feed's own id, trimmed and otherwise untouched**: RSS `<guid>`, Atom `<id>`, RSS 1.0 `rdf:about`, JSON Feed `id`. A blank one counts as missing.
2. Otherwise `"sha256:"` followed by the SHA-256 (lowercase hex) of the item's **link as written in the feed**, a newline, and its **title**.
3. With no title, the link, a newline, and the **published time** as `2026-11-02T15:00:00Z`.
4. With no title and no date, the link, a newline, and the content.

The hash uses the link before it's resolved, so an id doesn't change with `baseUrl` or when a feed moves to another host. An id from rule 2 does change if the publisher edits the title, and from rule 4 if they edit the text: that's the price of a feed without guids. Ids are unique within one feed at best, so store them per feed.

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
| `userAgent`, `timeoutSeconds`, `maxBytes`, `maxRedirects` | Override the module settings for this call. |

| Result | Meaning |
|---|---|
| `status` | The HTTP status of the last response. |
| `notModified` | True for a 304. |
| `etag`, `lastModified` | The response's validators, as sent. On a 304 that repeats none, the ones you passed in. |
| `finalUrl` | The address that finally answered, after redirects. Relative URLs in the feed are resolved against it. |
| `permanentUrl` | Where the feed has permanently moved, or `""`. It's the end of the leading run of 301 and 308 redirects; a redirect after a temporary one (302, 303, 307) isn't counted, since the temporary hop may point elsewhere tomorrow. |
| `feed` | The `parseFeed()` struct on a 200. Null for any other status. |

Only `http` and `https` are fetched, and redirects to anything else are refused. Gzip is asked for and undone.

### Discovering feeds

`discoverFeeds( html, baseUrl = "" )` returns the feeds a page links with `<link rel="alternate">`, in page order, with repeats dropped:

```js
discoverFeeds( html, "https://example.com/blog/" )
// [ { url: "https://example.com/feed.xml", type: "application/rss+xml", title: "Posts" } ]
```

It recognizes `application/rss+xml`, `application/atom+xml`, `application/feed+json` and `application/json`, and honors a `<base href>` in the page. It reads the tags with a pattern rather than an HTML parser, which is enough for `<link>` tags. It doesn't fetch the page or guess at addresses like `/feed`.

### Errors

| Type | When |
|---|---|
| `Feeds.ParseError` | The input isn't a readable feed: garbage bytes, HTML, broken XML, JSON that isn't a JSON Feed, a path that isn't a file. `message` is safe to show; `detail` has the parser's reason. |
| `Feeds.FetchError` | The feed couldn't be fetched: DNS, a refused connection, TLS, an address that isn't http(s). `detail` has the reason. |
| `Feeds.FetchError.Timeout` | The fetch took longer than `timeoutSeconds`. |
| `Feeds.FetchError.TooLarge` | The body is over `maxBytes`. |
| `Feeds.FetchError.TooManyRedirects` | More than `maxRedirects` redirects. |

`catch ( "Feeds.FetchError" e )` catches all four fetch errors. An HTTP error status is not an exception: it comes back in `result.status`.

### The models

The BIFs are thin wrappers over three classes you can also use directly:

```js
parser    = new bxModules.bxFeeds.models.FeedParser()                       // .parse( input, options )
fetcher   = new bxModules.bxFeeds.models.FeedFetcher( { userAgent: "Mine/1.0" } )  // .fetch( feedUrl, options )
discovery = new bxModules.bxFeeds.models.FeedDiscovery()                    // .discover( html, baseUrl )
```

### Runnable example

`examples/smoke.bxs` parses a feed, discovers one, and fetches one twice from a server it starts on a free local port:

```bash
boxlang examples/smoke.bxs
```

## Security

**XML attacks.** Feeds are XML from strangers. The module never reads a DTD: a DOCTYPE at the top of the document is cut out before parsing (old RSS 0.91 feeds carry one, and are still read), and the XML parser is told to refuse any DOCTYPE that remains. So entities a DTD would define don't exist: an external entity (XXE) can't read a file or call a server, an external DTD isn't fetched, and a "billion laughs" entity bomb fails at once instead of expanding. A feed that uses such an entity throws `Feeds.ParseError`. The standard HTML entities (`&nbsp;`, `&copy;`...) still work; ROME replaces them itself. `tests/specs/SecuritySpec.bx` proves each of these against a canary file and a local server.

**HTML is not sanitized.** `contentHtml`, `summary` and `title` are returned as the feed wrote them, with only relative URLs made absolute. They can contain `<script>`, event handlers, `javascript:` links and tracking pixels. Sanitize them before you show them (that's another module's job), and treat every link as untrusted.

**Fetching is not restricted to public addresses.** `fetchFeed()` will fetch any http(s) address it's given, and follow redirects to any other, including `localhost` and private network addresses. If your users choose the addresses, check them (and each `finalUrl`) against your own rules, or fetch through an egress proxy that does.

**Limits.** `timeoutSeconds` bounds the whole fetch, so a server that trickles bytes can't hold a worker. `maxBytes` is counted after decompression, so a gzip bomb is cut off too. The parser itself has no size limit: if you parse bytes you fetched yourself, limit them yourself.

## Not yet

- OPML import and export.
- iTunes, Media RSS and Podcasting 2.0 fields (duration, episode artwork, transcripts, chapters). Only a show's `itunes:image` is read.
- Repairs for feeds an XML parser rejects outright: an attribute declared twice on the root element, an out-of-range `<skipHours>`, UTF-8 that was encoded twice.
- Cleaning titles and author names (`email (Name)`, double-escaped entities).
- Dates in formats ROME doesn't know. They are null today.
- `srcset` attributes and CSS `url()` in content aren't made absolute.
- WebSub hubs, `rel="self"`, paging (`rel="next"`), `<ttl>` and other polling hints.
- `Retry-After` and `Cache-Control` from the response.
- Refusing private network addresses in `fetchFeed()`.
- Polling, scheduling and full-text extraction belong in the app, not here.

## Dependencies

`libs/` holds these jars from Maven Central, fetched and checked against Central's SHA-1 by `scripts/fetch-libs.sh`:

| Jar | Version | License |
|---|---|---|
| `com.rometools:rome` | 2.1.0 | Apache 2.0 |
| `com.rometools:rome-utils` | 2.1.0 | Apache 2.0 |
| `org.jdom:jdom2` | 2.0.6.1 | Apache-style (JDOM) |

That's everything ROME needs at runtime. Its fourth dependency, SLF4J, is already inside BoxLang, and JDOM's own dependencies (Jaxen, Xerces, Xalan) are optional and unused: XML is parsed by the JDK. None of the three jars' packages (`com.rometools`, `org.jdom2`) are in the BoxLang runtime jar, so nothing clashes. `rome-modules` (iTunes, Media RSS) is deliberately left out.

Fetching uses the JDK's `HttpURLConnection`, and JSON Feed uses BoxLang's `jsonDeserialize()`, so neither adds a jar.

Calling Java from BoxLang, as checked on 1.19: a BoxLang closure passed where Java expects a functional interface is converted automatically. That held for `java.util.function.Function`, `Supplier` and `Predicate`, and for `com.sun.net.httpserver.HttpHandler` (the specs' local server, whose handler runs on Java's own threads). No `createDynamicProxy()` was needed. The module's own code calls ROME with plain method calls and passes it no callbacks.

To update, change the versions in `scripts/fetch-libs.sh`, run it, run the specs, and commit `libs/`.

## Development

```bash
box install                 # TestBox and bx-compat-cfml
bash scripts/test.sh        # sets up the test homes on first run, then runs the specs in each
```

The specs run in two BoxLang homes of their own: `.tmp/bxhome` (this checkout) and `.tmp/bxhome-compat` (the same plus bx-compat-cfml, which changes how nulls behave). A bx-feeds installed in `~/.boxlang/modules` can't stand in for the code under test. No spec uses the network: feeds come from `tests/resources/`, and the fetch specs talk to a server started on a random free port.

## License

MIT
