import type { AccountRole } from "./domain.js";

export interface InvitationEmailDelivery {
  recipientEmail: string;
  inviterName: string;
  role: AccountRole;
  invitationURL: string;
  expiresAt: string;
}

export interface InvitationEmailSender {
  send(delivery: InvitationEmailDelivery): Promise<void>;
}

export class NoopInvitationEmailSender implements InvitationEmailSender {
  async send(): Promise<void> {}
}

export class UnavailableInvitationEmailSender implements InvitationEmailSender {
  async send(): Promise<void> {
    throw new Error("Invitation email delivery is not configured");
  }
}
