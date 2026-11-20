# Inventory System widget

Sign in to Enquiry Tracker as an active admin and choose **Inventory System**.
The current sign-in also authorizes this native web widget. There is no iframe,
separate server, or second login. The promoter and Android flows are unchanged.

Inventory uses `is_products`, `is_drafts`, `is_balances` and `is_movements` in
the existing default Firestore database. The Spark quota is shared. The
inventory rules were added to the live default ruleset without replacing its
other clauses. The prior live rules had drifted from the checked-in source;
do not redeploy the entire checked-in rules file until that drift is reconciled.

Stock balances and immutable movement entries are posted together using a
Firestore transaction. Products and drafts allow empty optional fields.
Stock posting requires the type, location, product and quantity. Physical
counts record the variance as a stock movement. The UI caps each query at
101 records to detect when its initial 100-row display is truncated.

Do not use the old separately hosted IS deployment against this Firebase
project. Its independent backup configuration must be explicitly updated
and tested against the shared project's inventory collections.
