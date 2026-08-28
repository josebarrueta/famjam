import { randomUUID } from "node:crypto";
import type { Account, FamilyEvent, FamilyInvitation, FamilyMember } from "./domain.js";
import type { RallyrooRepository } from "./repository.js";

interface SeedData {
  accounts?: Account[];
  events?: FamilyEvent[];
  members?: FamilyMember[];
}

export class InMemoryRallyrooRepository implements RallyrooRepository {
  private readonly accounts: Account[];
  private readonly events: FamilyEvent[];
  private readonly members: FamilyMember[];
  private readonly invitations: FamilyInvitation[] = [];
  private readonly changeVersions = new Map<string, number>();
  private readonly devices = new Map<string, { familyID: string; memberID: string }>();

  constructor(seed: SeedData = {}) {
    this.accounts = [...(seed.accounts ?? [])];
    this.events = [...(seed.events ?? [])];
    this.members = [...(seed.members ?? [])];
  }

  async accountForIdentity(subject: string): Promise<Account | null> {
    return this.accounts.find((account) => account.identitySubject === subject) ?? null;
  }

  async provisionParentAccount(subject: string, displayName: string): Promise<Account> {
    const existing = await this.accountForIdentity(subject);
    if (existing) return existing;
    const familyID = `family-${randomUUID()}`;
    const memberID = `parent-${randomUUID()}`;
    const account: Account = {
      identitySubject: subject,
      familyID,
      memberID,
      role: "parent",
    };
    this.members.push({
      id: memberID,
      familyID,
      name: displayName,
      role: "parent",
      colorTag: "blue",
    });
    this.accounts.push(account);
    return account;
  }

  async saveInvitation(invitation: FamilyInvitation): Promise<void> {
    this.invitations.push(invitation);
  }

  async pendingInvitations(familyID: string): Promise<FamilyInvitation[]> {
    return this.invitations.filter((invitation) =>
      invitation.familyID === familyID && new Date(invitation.expiresAt) > new Date()
    );
  }

  async cancelInvitation(familyID: string, invitationID: string): Promise<boolean> {
    const index = this.invitations.findIndex((invitation) =>
      invitation.id === invitationID &&
      invitation.familyID === familyID &&
      new Date(invitation.expiresAt) > new Date()
    );
    if (index < 0) return false;
    this.invitations.splice(index, 1);
    return true;
  }

  async rotateInvitation(
    familyID: string,
    invitationID: string,
    codeHash: string,
    expiresAt: string,
  ): Promise<FamilyInvitation | null> {
    const invitation = this.invitations.find((candidate) =>
      candidate.id === invitationID &&
      candidate.familyID === familyID &&
      new Date(candidate.expiresAt) > new Date()
    );
    if (!invitation) return null;
    invitation.codeHash = codeHash;
    invitation.expiresAt = expiresAt;
    return invitation;
  }

  async consumeInvitation(
    codeHash: string,
    subject: string,
    displayName: string,
  ): Promise<Account | null> {
    const existing = await this.accountForIdentity(subject);
    if (existing) return existing;
    const index = this.invitations.findIndex((invitation) =>
      invitation.codeHash === codeHash && new Date(invitation.expiresAt) > new Date()
    );
    if (index < 0) return null;
    const invitation = this.invitations.splice(index, 1)[0]!;
    const memberID = `${invitation.role}-${randomUUID()}`;
    const account: Account = {
      identitySubject: subject,
      familyID: invitation.familyID,
      memberID,
      role: invitation.role,
    };
    this.members.push({
      id: memberID,
      familyID: invitation.familyID,
      name: displayName,
      role: invitation.role,
      colorTag: "blue",
    });
    this.accounts.push(account);
    await this.markFamilyChanged(invitation.familyID);
    return account;
  }

  async familyChangeVersion(familyID: string): Promise<number> {
    return this.changeVersions.get(familyID) ?? 0;
  }

  async markFamilyChanged(familyID: string): Promise<void> {
    this.changeVersions.set(familyID, (this.changeVersions.get(familyID) ?? 0) + 1);
  }

  async saveDeviceToken(familyID: string, memberID: string, token: string): Promise<void> {
    this.devices.set(token, { familyID, memberID });
  }

  async deleteDeviceToken(memberID: string, token: string): Promise<void> {
    if (this.devices.get(token)?.memberID === memberID) this.devices.delete(token);
  }

  async deviceTokensForFamily(familyID: string): Promise<string[]> {
    return [...this.devices.entries()]
      .filter(([, device]) => device.familyID === familyID)
      .map(([token]) => token);
  }

  async eventsForFamily(familyID: string): Promise<FamilyEvent[]> {
    return this.events.filter((event) => event.familyID === familyID);
  }

  async saveEvent(event: FamilyEvent): Promise<void> {
    const index = this.events.findIndex((candidate) => candidate.id === event.id && candidate.familyID === event.familyID);
    if (index >= 0) this.events[index] = event;
    else this.events.push(event);
  }

  async deleteEvent(familyID: string, eventID: string): Promise<void> {
    const index = this.events.findIndex((event) => event.familyID === familyID && event.id === eventID);
    if (index >= 0) this.events.splice(index, 1);
  }

  async membersForFamily(familyID: string): Promise<FamilyMember[]> {
    return this.members.filter((member) => member.familyID === familyID);
  }

  async saveMember(member: FamilyMember): Promise<void> {
    const index = this.members.findIndex((candidate) => candidate.id === member.id && candidate.familyID === member.familyID);
    if (index >= 0) this.members[index] = member;
    else this.members.push(member);
  }

  async deleteMember(familyID: string, memberID: string): Promise<void> {
    const index = this.members.findIndex((member) => member.familyID === familyID && member.id === memberID);
    if (index >= 0) this.members.splice(index, 1);
  }
}
