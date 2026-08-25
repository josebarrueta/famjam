import type { Account, FamilyEvent, FamilyInvitation, FamilyMember } from "./domain.js";

export interface FamJamRepository {
  accountForIdentity(subject: string): Promise<Account | null>;
  provisionParentAccount(subject: string, displayName: string): Promise<Account>;
  saveInvitation(invitation: FamilyInvitation): Promise<void>;
  consumeInvitation(codeHash: string, subject: string, displayName: string): Promise<Account | null>;
  eventsForFamily(familyID: string): Promise<FamilyEvent[]>;
  saveEvent(event: FamilyEvent): Promise<void>;
  deleteEvent(familyID: string, eventID: string): Promise<void>;
  membersForFamily(familyID: string): Promise<FamilyMember[]>;
  saveMember(member: FamilyMember): Promise<void>;
  deleteMember(familyID: string, memberID: string): Promise<void>;
}
