# Install Meridian on iPhone (sideload)

Meridian 2.0 for iPhone is on its way to App Review. Until it's on the App Store, you can install it yourself with
**AltStore** or **Sideloadly**. Both sign the app with your own Apple ID, so it runs on your iPhone
like any other app, widgets included.

You need an iPhone on iOS 17 or later, a Mac or Windows PC, a USB cable, and a free Apple ID.

**Download:** [Meridian-iOS.ipa](https://github.com/bradleycowdrey/meridian/releases/latest/download/Meridian-iOS.ipa),
attached to the latest [release](https://github.com/bradleycowdrey/meridian/releases). The newest build from `main`,
ahead of releases, is [here](https://github.com/bradleycowdrey/meridian/raw/ci-ios/Meridian-iOS.ipa).

## Option 1: Sideloadly (Mac or Windows)

1. Install Sideloadly from [sideloadly.io](https://sideloadly.io). On Windows, also install iTunes and iCloud
   from Apple's website (not the Microsoft Store).
2. Connect your iPhone with a cable and tap **Trust** on the iPhone if asked.
3. Open Sideloadly, drag **Meridian-iOS.ipa** onto it, enter your Apple ID and click **Start**.
4. On the iPhone: Settings → General → **VPN & Device Management**, tap your Apple ID, then **Trust**.
5. iOS 16 or later: Settings → Privacy & Security → **Developer Mode** → on, then restart when asked.

## Option 2: AltStore (Mac or Windows)

1. Install **AltServer** from [altstore.io](https://altstore.io) on your Mac or PC. On Windows, also install
   iTunes and iCloud from Apple's website.
2. Connect your iPhone, then use AltServer (menu bar on Mac, system tray on Windows) → **Install AltStore** →
   your iPhone, and sign in with your Apple ID.
3. On the iPhone, trust your Apple ID (Settings → General → **VPN & Device Management**) and turn on
   **Developer Mode** (Settings → Privacy & Security) as above.
4. Download **Meridian-iOS.ipa** on the iPhone, tap Share → **AltStore**, or open AltStore → My Apps → **+**
   and choose the file.

## Widgets

Open Meridian once after installing and add your cities. Then touch and hold the Home Screen,
tap **Edit** → **Add Widget**, and search for **Meridian**. The widgets read your cities from the app,
so they show cities once the app has been opened. Each city sits on its photo with its hour tiles, and with
fewer cities the rows grow to fill the widget.

The widgets share the app's cities through an App Group, which AltStore and Sideloadly register for you
when they sign the app. Nothing to set up yourself.

## Every 7 days (free Apple ID)

Apps signed with a free Apple ID stop opening after 7 days until they're signed again. Your cities and
settings stay.

- **AltStore** refreshes it for you over Wi-Fi while AltServer is running on your computer, or tap
  **Refresh All** in AltStore.
- **Sideloadly**: install the same file again, or turn on its automatic refresh.

A paid Apple Developer account lasts a year instead. A free Apple ID can have up to 3 sideloaded apps
at once; Meridian counts as one, and its widget uses one of the 10 app IDs a free Apple ID can register each week.

## Updating

Download the newest **Meridian-iOS.ipa** from the link above and install it the same way. It replaces
the old version and keeps your cities. When Meridian is on the App Store, delete the sideloaded app and
install it from there.
