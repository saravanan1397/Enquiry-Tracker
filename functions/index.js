const admin = require("firebase-admin");
const { logger } = require("firebase-functions");
const { defineSecret } = require("firebase-functions/params");
const { HttpsError, onCall } = require("firebase-functions/v2/https");

admin.initializeApp();
Object.assign(exports, require('./reminders'));

const resendApiKey = defineSecret("RESEND_API_KEY");
const exportFromEmail = defineSecret("EXPORT_FROM_EMAIL");
const maxEncodedAttachmentLength = 8 * 1024 * 1024;

exports.sendCustomerExport = onCall(
  {
    region: "asia-south1",
    timeoutSeconds: 60,
    memory: "256MiB",
    secrets: [resendApiKey, exportFromEmail],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in as the owner first.");
    }

    const owner = await admin
      .firestore()
      .collection("users")
      .doc(request.auth.uid)
      .get();
    if (owner.data()?.role !== "admin" || owner.data()?.active !== true) {
      throw new HttpsError("permission-denied", "Only the owner can email exports.");
    }

    const recipient = String(request.data?.recipient || "").trim();
    const fileName = String(request.data?.fileName || "enquiry_tracker_export.xlsx")
      .replace(/[^A-Za-z0-9._-]/g, "_");
    const fileBase64 = String(request.data?.fileBase64 || "");
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(recipient)) {
      throw new HttpsError("invalid-argument", "Enter a valid recipient email address.");
    }
    if (!fileBase64 || fileBase64.length > maxEncodedAttachmentLength) {
      throw new HttpsError(
        "invalid-argument",
        "The Excel export is missing or is too large to email.",
      );
    }

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendApiKey.value()}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: exportFromEmail.value(),
        to: [recipient],
        subject: "Enquiry Tracker customer follow-ups",
        text: "Attached is the latest Enquiry Tracker customer export.",
        attachments: [
          {
            filename: fileName,
            content: fileBase64,
          },
        ],
      }),
    });

    if (!response.ok) {
      logger.error("Export email delivery failed", {
        status: response.status,
        response: await response.text(),
      });
      throw new HttpsError("internal", "The email provider could not send the export.");
    }

    return { sent: true };
  },
);
