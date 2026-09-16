# LHS Life Privacy Policy

_Effective September 2026_

LHS Life is a student-built companion app for La Salle High School in Yakima, WA. It's designed to keep as much as possible on your own device. This policy explains what the app stores, what leaves your device, how long it's kept, and how to delete it.

**The short version:** your school email, grades, assignments, and settings never reach an LHS Life server. The only thing the app sends to its own server is what it needs to update the bell schedule on your Lock Screen, and only if you turn Live Activities on. There are no ads, no analytics, no tracking, and no third-party SDKs.

## What stays on your device

- **Your school email and graduation year.** You sign in with your school email. It's saved on your device and never sent to an LHS Life server. Your graduation year can be changed in Settings.
- **Your preferences.** Period names and colors, which periods you have, notification choices, ASB settings, and Live Activity settings.
- **A copy of the school calendar**, so the app opens fast and works offline.

## What syncs through your iCloud

If you're signed in to iCloud, LHS Life uses Apple's iCloud key-value storage to sync your setup between your own devices (like an iPhone and an iPad). Synced items include your school email, graduation year, period names and colors, Pro Dress and ASB settings, and whether you've signed in. This data lives in **your** private iCloud account. The LHS Life developers can't see it.

## What's sent to the LHS Life server (only with Live Activities on)

To keep the bell schedule on your Lock Screen and Dynamic Island up to date, a small server sends updates to your device at each bell. To do that, the app sends it:

| Data | Why |
|---|---|
| A random device ID created by the app | Keeps your registration separate from other devices. Not tied to your name, email, or Apple ID. |
| A Live Activity push token from Apple | Lets the server send your Lock Screen updates through Apple's push service. |
| Today's period start and end times (not counting periods you turned off) | So updates arrive at the right moments for your schedule. |
| App version and iOS version | Helps figure out which version is involved when something breaks. |

**Not sent:** your name, school email, graduation year, period names, grades, assignments, location, or contacts.

**How long it's kept:** the server keeps a device's record only while that device's Live Activity is running. The record is deleted when the Live Activity ends, when Apple reports the push token is no longer valid, or when you use Delete All Data.

## Who else is involved

- **Cloudflare** hosts the LHS Life server. Cloudflare can see the IP address of each request. The server doesn't store IP addresses, but Cloudflare keeps short-term request logs (a few days), which include the random device ID.
- **Apple** delivers Lock Screen updates and notifications through the Apple Push Notification service, and runs iCloud.

LHS Life only uses these providers to run the features described here. Their handling of this data is covered by the [Cloudflare Privacy Policy](https://www.cloudflare.com/privacypolicy/) and the [Apple Privacy Policy](https://www.apple.com/legal/privacy/), which protect it at least as well as this policy does. LHS Life doesn't sell or share your data with anyone else.

## School websites inside the app

The PowerSchool, Schoology, and lunch-ordering tabs show those websites directly. When you sign in there, your username, password, and everything you do goes straight to those services, under their own privacy policies. LHS Life doesn't read, store, or send your passwords or school data.

LHS Life changes those pages in only three ways: it adjusts how they look (dark mode), lets you print, and fills in your school email on your school's Microsoft sign-in page so you don't have to type it. Your password is left to iOS Keychain autofill, which LHS Life can't see. Your device keeps those sites' login cookies so you stay signed in, like a web browser would.

The school calendar is downloaded from La Salle's public calendar feed. That request doesn't include any information about you.

## Permissions the app asks for

- **Notifications**, after you sign in: Pro Dress reminders, schedule-change alerts, ASB reminders, and Live Activity nudges. They're all scheduled on your device.
- **Calendars (add events only):** only when you tap "Save to Calendar." LHS Life can add the event to your calendar but can't see anything already on it.
- **Reminders:** only when you add homework. Assignments go into a list in your own Reminders app.
- **Live Activities:** to show the bell schedule on your Lock Screen.

Anything saved to Calendar or Reminders belongs to you and stays there, even if you delete LHS Life or use Delete All Data.

## Your choices and deleting your data

- **Turn off Live Activities** (LHS Life Settings) to stop sending anything to the LHS Life server. Your record there is removed when the current Live Activity ends.
- **Turn off notifications, calendar, or reminders access** at any time in the iOS Settings app, under LHS Life.
- **Sign Out** (LHS Life Settings) clears your email and graduation year.
- **Delete All Data** (LHS Life Settings) resets all LHS Life settings on your device and in iCloud, signs you out of PowerSchool, Schoology, and lunch ordering, and removes your device from the LHS Life server.
- **Deleting the app** removes everything it stored on your device.

Because the server doesn't know who you are, there's nothing about you to look up or delete on request beyond the steps above. If you have questions, contact us below.

## Children

LHS Life is built for La Salle High School students, families, and staff. It doesn't knowingly collect personal information from children under 13, and none of the data described above is linked to anyone's identity.

## Changes

If this policy changes, the updated version will be posted here with a new effective date.

## Contact

Questions? Contact La Salle High School ASB at **[contact email]**.
