import type { Account, FamilyEvent, FamilyInvitation, FamilyMember } from "./domain.js";

export interface RallyrooRepository {
  accountForIdentity(subject: string): Promise<Account | null>;
  provisionParentAccount(subject: string, displayName: string): Promise<Account>;
  saveInvitation(invitation: FamilyInvitation): Promise<void>;
  pendingInvitations(familyID: string): Promise<FamilyInvitation[]>;
  cancelInvitation(familyID: string, invitationID: string): Promise<boolean>;
  rotateInvitation(
    familyID: string,
    invitationID: string,
    codeHash: string,
    expiresAt: string,
  ): Promise<FamilyInvitation | null>;
  consumeInvitation(codeHash: string, subject: string, displayName: string): Promise<Account | null>;
  familyChangeVersion(familyID: string): Promise<number>;
  markFamilyChanged(familyID: string): Promise<void>;
  saveDeviceToken(familyID: string, memberID: string, token: string): Promise<void>;
  deleteDeviceToken(memberID: string, token: string): Promise<void>;
  deviceTokensForFamily(familyID: string): Promise<string[]>;
  eventsForFamily(familyID: string): Promise<FamilyEvent[]>;
  saveEvent(event: FamilyEvent): Promise<void>;
  deleteEvent(familyID: string, eventID: string): Promise<void>;
  membersForFamily(familyID: string): Promise<FamilyMember[]>;
  saveMember(member: FamilyMember): Promise<void>;
  deleteMember(familyID: string, memberID: string): Promise<void>;
}
