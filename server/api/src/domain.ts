export type AccountRole = "parent" | "kid";

export interface Identity {
  subject: string;
  displayName: string;
  email?: string;
}

export interface Account {
  identitySubject: string;
  familyID: string;
  memberID: string;
  role: AccountRole;
}

export interface FamilyMember {
  id: string;
  familyID: string;
  name: string;
  role: AccountRole;
  gradeOrBirthYear?: string | null;
  colorTag: string;
}

export interface EventRecurrence {
  frequency: "daily" | "weekly" | "monthly";
  interval: number;
  endDate: string;
}

export interface FamilyEvent {
  id: string;
  familyID: string;
  title: string;
  kidID: string | null;
  participantIDs: string[];
  startTime: string;
  endTime: string;
  location: string | null;
  driver: string | null;
  source: "manual" | "email_suggested" | "voice";
  status: "confirmed" | "pending_review";
  recurrence?: EventRecurrence | null;
}

export interface EventConflict {
  kind: "overlapping_participant" | "double_booked_driver";
  memberID: string | null;
  driver: string | null;
  eventIDs: string[];
}
