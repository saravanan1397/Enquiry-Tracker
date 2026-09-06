# Backend contract to implement next

The app is designed around these server concepts:

## Core records

- `shops`: shop identity and active status.
- `promoters`: promoter identity, assigned PIN hash, assigned shops, and active/revoked status.
- `admins`: admin PIN hash, role, and active status.
- `leads`: customer name, mobile number, shop, promoter, timestamps, sync version, and deleted timestamp.
- `follow_ups`: one row per follow-up, with stage 1, 2, or 3, comment, timestamp, and author.

## Sync rules

1. Every local change has a stable client-generated ID.
2. Uploads are idempotent, so retrying after a dropped connection cannot create duplicates.
3. Deletions are soft deletes first and sync as tombstones so an old offline device cannot resurrect a deleted record.
4. The owner dashboard shows only records confirmed by the server.
5. A promoter PIN is validated against the server when signing in on a new phone.

## Access rules

- Revoking a promoter PIN blocks new access after the device reconnects.
- Promoters can only see records allowed by their promoter/shop assignment.
- Admins can filter across all shops and promoters.
- Permanent deletion requires owner confirmation and is separate from moving a record to the recycle bin.
