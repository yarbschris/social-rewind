# Privacy

Social Rewind is built to collect nothing.

- **No backend, no accounts, no analytics, no third-party SDKs.**
- **Settings and stats stay on the device**, in the app's App Group container.
- **Platform sessions:** you sign in to each platform directly on that platform's own website. Each platform's cookies sit in a separate, isolated WebKit data store on your device. Social Rewind never reads, stores or sends your credentials.
- **Network:** the app's web view only loads hosts on a built-in allowlist for each platform. Links to other sites open in your default browser, outside Social Rewind.
- **Rule updates (optional, off by default):** when you turn this on, the app downloads `rules/<platform>.json` from this public GitHub repository. Like any web request, this exposes your IP address to GitHub. No identifiers are sent. Rule packs are plain data: they can only hide or redirect things inside a platform's site, and they can't run code or add new hosts.
- **Crash reports:** only Apple's built-in reports, and only if you've turned on sharing with app developers in iOS Settings.

App Store privacy label: **Data Not Collected**.
