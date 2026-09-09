# Follow-up and notification decisions

- No AI implementation. Potential future discussion only: comment-based purchase suggestions with explicit promoter confirmation; callback extraction; provider and cost undecided.
- Each saved follow-up starts the next 15-business-hour deadline. All calendar days, including weekends, count from 09:00 to 22:00 Asia/Kolkata. Comment wording cannot override it.
- F3 never automatically completes an enquiry. Purchased and Closed without purchase are explicit completed outcomes with timestamps; they stop reminders.
- After F3 has been saved, Add follow-up opens F4, then F5 after F4 is saved. Additional history is preserved and included in search and exports.
- Owners receive summaries for all active promoters. Each promoter receives only their own summary: `<promoter name> has <n> pending followups.` Count means overdue open, non-deleted enquiries.
- Android push registration uses authenticated server calls; recipient UID and approval are checked server-side. Client access to device registrations and delivery state is denied by Firestore's catch-all rule. No public topics.
- Scheduler checks every five minutes during business hours. A changed overdue set triggers another summary; unchanged summaries repeat the next business day. Delivery depends on device permission, connectivity and Android settings. Force-stopped apps need reopening.
- Web keeps in-app overdue indicators; phone push requires the Android build and notification permission. Deploy only registerReminderDevice and sendFollowUpReminders; the email function is separate.
- Scheduled Firebase functions require a billing-enabled Blaze project. Do not upgrade billing automatically. Offline entries enter server notification counts after sync.
- Pending future choices: purchase + new-enquiry combined action, full edit-history auditing, browser push delivery, and configurable reminder repetition.

## Activation

Deployment was attempted but Firebase rejected it because sshtrackingapp is not on Blaze. No billing change was made and push is not live yet.

After the owner enables Blaze in Firebase Console > Usage and billing:

```powershell
cd "D:\Projects\Mobile App"
firebase deploy --only "functions:registerReminderDevice,functions:sendFollowUpReminders" --project sshtrackingapp
```

Install the updated Android APK on owner and promoter phones, open it, sign in and allow notifications. Device registration retries every five minutes while open if deployment or connectivity was unavailable. Web users still see the in-app overdue state; Android installation is required for phone push.

Use updated versions on all devices when editing records with additional follow-ups or completion outcomes. Older versions do not understand those fields.
