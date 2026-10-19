# LHS Life Privacy Policy

_Effective October 2026_

LHS Life is a student-built companion app for La Salle High School in Yakima, WA. It's designed to keep as much as possible on your own device. This policy explains what the app stores, what leaves your device, how long it's kept, and how to delete it.

**The short version:** your school email, grades, assignments, and settings never reach an LHS Life server. The only thing the app sends to its own server is what it needs to update the bell schedule on your Lock Screen, and only if you turn Live Activities on. There are no ads, no analytics, no tracking, and no third-party SDKs.

## What stays on your device

- **Your school email and graduation year.** You sign in with your school email. It's saved on your device and never sent to an LHS Life server. Your graduation year can be changed in Settings.
- **Your preferences.** Period names and colors, which periods you have, notification choices, ASB settings, and Live Activity settings.
- **A copy of the school calendar**, so the app opens fast and works offline.

## What syncs through your iCloud

If you're signed in to iCloud, LHS Life uses Apple's iCloud key-value storage to sync your setup between your own devices (like an iPhone and an iPad). Synced items include your school email, graduation year, period names and colors, and whether you've signed in. Alert settings (Pro Dress, Late Start, ASB and Live Activities) stay on each device, so you choose separately where you get reminders. This data lives in **your** private iCloud account. The LHS Life developers can't see it.

## What's sent to the LHS Life server (only with Live Activities on)

To keep the bell schedule on your Lock Screen and Dynamic Island up to date, a small server sends one update at each bell through Apple's push service, and Apple delivers that same update to every phone showing the LHS Life Live Activity. Each phone works out its own class from the schedule it already has. So the server never needs to know which phones are listening — the app sends it only:

| Data | Why |
|---|---|
| Today's period start and end times (not counting periods you turned off) | So the server sends an update at each of your bells. |

The app also says whether it's an App Store or a test build, which the server ignores. Nothing identifies your device: no device ID, no push token, no app or iOS version. Phones on the same schedule send the same times, so the server keeps each different schedule once, with nothing to say whose it is.

**Not sent:** your name, school email, graduation year, period names, grades, assignments, location, or contacts.

**How long it's kept:** the bell times are deleted automatically after about 3 days.

## Problem reports

When something breaks in a way the school can fix — the school calendar can't be reached, a posted schedule can't be read, a school website won't load — the app tells the same server, so the school can see how many devices are affected instead of waiting for someone to report it. It sends a random install ID, the app and iOS version, and a short description of the failure, at most once per device per problem per day. It never sends what you typed, what you were looking at, or anything about you. These reports are deleted automatically after 7 days.

## Who else is involved

- **Cloudflare** hosts the LHS Life server. Cloudflare can see the IP address of each request. The server doesn't store IP addresses, but Cloudflare keeps short-term request logs (a few days), which include the random install ID sent with problem reports.
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

- **Turn off Live Activities** (LHS Life Settings) to stop sending your bell times to the LHS Life server.
- **Turn off notifications, calendar, or reminders access** at any time in the iOS Settings app, under LHS Life.
- **Sign Out** (LHS Life Settings) clears your email and graduation year.
- **Delete All Data** (LHS Life Settings) resets all LHS Life settings on your device and in iCloud, clears the saved copy of the school calendar, signs you out of PowerSchool, Schoology, and lunch ordering, and gives your device a new random ID for any future problem reports.
- **Deleting the app** removes everything it stored on your device.

Because the server doesn't know who you are, there's nothing about you to look up or delete on request beyond the steps above. If you have questions, contact us below.

## Children

LHS Life is built for La Salle High School students, families, and staff. It doesn't knowingly collect personal information from children under 13, and none of the data described above is linked to anyone's identity.

## Changes

If this policy changes, the updated version will be posted here with a new effective date.

## Contact

Questions? Contact La Salle High School ASB at **[contact email]**.
