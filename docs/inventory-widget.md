# Inventory System widget

The web admin dashboard contains the Inventory System card. It remains
unconnected until the Inventory System server is available at its own HTTPS
origin. The existing GitHub Pages build serves the dashboard, not the IS Node
server.

1. Deploy the IS server with its dedicated Firebase project and set
   `IS_EMBED_IN_ENQUIRY_TRACKER=1` on that server.
2. In this GitHub repository, open **Settings → Secrets and variables →
   Actions → Variables** and set `IS_WIDGET_URL` to the IS HTTPS origin.
3. Run **Deploy Flutter web app to GitHub Pages** again. Sign in as an admin,
   open **Inventory System**, then sign in with the separate IS account.

Do not use the local demo address in the GitHub configuration. There is no
widget in the promoter or Android interface.
