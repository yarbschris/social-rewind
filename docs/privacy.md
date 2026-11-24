# Privacy

Social Rewind is built to collect nothing.

- **No backend, no accounts, no analytics, no third-party SDKs.**
- **Settings and stats stay on the device**, in the app's App Group container.
- **Platform sessions:** you sign in to each platform directly on that platform's own website. Each platform's cookies sit in a separate, isolated WebKit data store on your device. Social Rewind never reads, stores or sends your credentials.
- **Network:** the app's web view only loads hosts on a built-in allowlist for each platform. Links to other sites open in your default browser, outside Social Rewind.
- **Rule updates (optional, off by default):** when you turn this on, the app downloads `rules/<platform>.json` from this public GitHub repository. Like any web request, this exposes your IP address to GitHub. No identifiers are sent. Rule packs are plain data. They can hide content and redirect between pages *of the same platform site*. They can't run code, add hosts or redirect to another site: this is checked by the schema, the engine and the app. Before rule updates ship in a release, packs will also be cryptographically signed.
- **Crash reports:** only Apple's built-in reports, and only if you've turned on sharing with app developers in iOS Settings.

App Store privacy label: **Data Not Collected**.
