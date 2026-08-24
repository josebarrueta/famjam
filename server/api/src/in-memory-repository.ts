import type { Account, FamilyEvent, FamilyMember } from "./domain.js";
import type { FamJamRepository } from "./repository.js";

interface SeedData {
  accounts?: Account[];
  events?: FamilyEvent[];
  members?: FamilyMember[];
}

export class InMemoryFamJamRepository implements FamJamRepository {
  private readonly accounts: Account[];
  private readonly events: FamilyEvent[];
  private readonly members: FamilyMember[];

  constructor(seed: SeedData = {}) {
    this.accounts = [...(seed.accounts ?? [])];
    this.events = [...(seed.events ?? [])];
    this.members = [...(seed.members ?? [])];
  }

  async accountForIdentity(subject: string): Promise<Account | null> {
    return this.accounts.find((account) => account.identitySubject === subject) ?? null;
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
