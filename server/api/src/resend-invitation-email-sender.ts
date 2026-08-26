import type {
  InvitationEmailDelivery,
  InvitationEmailSender,
} from "./invitation-email-sender.js";

interface ResendConfiguration {
  apiKey: string;
  from: string;
  fetch?: typeof globalThis.fetch;
}

export class ResendInvitationEmailSender implements InvitationEmailSender {
  private readonly fetch: typeof globalThis.fetch;

  constructor(private readonly configuration: ResendConfiguration) {
    this.fetch = configuration.fetch ?? globalThis.fetch;
  }

  async send(delivery: InvitationEmailDelivery): Promise<void> {
    const subject = `${delivery.inviterName} invited you to FamJam`;
    const role = delivery.role === "kid" ? "kid" : "parent";
    const text = [
      `${delivery.inviterName} invited you to join their family on FamJam as a ${role}.`,
      "",
      `Open this secure, single-use link: ${delivery.invitationURL}`,
      "",
      `This invitation expires ${delivery.expiresAt}.`,
    ].join("\n");
    const response = await this.fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        authorization: `Bearer ${this.configuration.apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        from: this.configuration.from,
        to: [delivery.recipientEmail],
        subject,
        text,
        html: `<p>${escapeHTML(delivery.inviterName)} invited you to join their family on FamJam as a ${role}.</p>`
          + `<p><a href="${escapeHTML(delivery.invitationURL)}">Join the family on FamJam</a></p>`
          + `<p>This secure invitation can only be used once and expires ${escapeHTML(delivery.expiresAt)}.</p>`,
      }),
    });
    if (!response.ok) throw new Error(`Resend returned ${response.status}`);
  }
}

function escapeHTML(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
