import { randomUUID } from "node:crypto";
import { Pool, type PoolConfig } from "pg";
import type {
  Account,
  AccountRole,
  EventRecurrence,
  FamilyEvent,
  FamilyInvitation,
  FamilyMember,
} from "./domain.js";
import type { FamJamRepository } from "./repository.js";

export class PostgresFamJamRepository implements FamJamRepository {
  constructor(private readonly pool: Pool) {}

  static fromConnectionString(connectionString: string): PostgresFamJamRepository {
    const config: PoolConfig = { connectionString, max: 20 };
    return new PostgresFamJamRepository(new Pool(config));
  }

  async accountForIdentity(subject: string): Promise<Account | null> {
    const result = await this.pool.query<AccountRow>(
      `SELECT identity_subject, family_id, member_id, role
       FROM accounts WHERE identity_subject = $1`,
      [subject],
    );
    const row = result.rows[0];
    return row ? accountFromRow(row) : null;
  }

  async provisionParentAccount(subject: string, displayName: string): Promise<Account> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT pg_advisory_xact_lock(hashtextextended($1::text, 0))", [subject]);
      const existing = await client.query<AccountRow>(
        `SELECT identity_subject, family_id, member_id, role
         FROM accounts WHERE identity_subject = $1`,
        [subject],
      );
      const existingRow = existing.rows[0];
      if (existingRow) {
        await client.query("COMMIT");
        return accountFromRow(existingRow);
      }

      const familyID = `family-${randomUUID()}`;
      const memberID = `parent-${randomUUID()}`;
      await client.query(
        `INSERT INTO family_members (family_id, id, name, role, color_tag)
         VALUES ($1, $2, $3, 'parent', 'blue')`,
        [familyID, memberID, displayName],
      );
      await client.query(
        `INSERT INTO accounts (identity_subject, family_id, member_id, role)
         VALUES ($1, $2, $3, 'parent')`,
        [subject, familyID, memberID],
      );
      await client.query("COMMIT");
      return { identitySubject: subject, familyID, memberID, role: "parent" };
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async saveInvitation(invitation: FamilyInvitation): Promise<void> {
    await this.pool.query(
      `INSERT INTO family_invitations (code_hash, family_id, role, expires_at)
       VALUES ($1, $2, $3, $4)`,
      [invitation.codeHash, invitation.familyID, invitation.role, invitation.expiresAt],
    );
  }

  async consumeInvitation(
    codeHash: string,
    subject: string,
    displayName: string,
  ): Promise<Account | null> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT pg_advisory_xact_lock(hashtextextended($1::text, 0))", [subject]);
      const existing = await client.query<AccountRow>(
        `SELECT identity_subject, family_id, member_id, role
         FROM accounts WHERE identity_subject = $1`,
        [subject],
      );
      if (existing.rows[0]) {
        await client.query("COMMIT");
        return accountFromRow(existing.rows[0]);
      }
      const invitationResult = await client.query<InvitationRow>(
        `SELECT family_id, role FROM family_invitations
         WHERE code_hash = $1 AND consumed_at IS NULL AND expires_at > now()
         FOR UPDATE`,
        [codeHash],
      );
      const invitation = invitationResult.rows[0];
      if (!invitation) {
        await client.query("ROLLBACK");
        return null;
      }
      const memberID = `${invitation.role}-${randomUUID()}`;
      await client.query(
        `INSERT INTO family_members (family_id, id, name, role, color_tag)
         VALUES ($1, $2, $3, $4, 'blue')`,
        [invitation.family_id, memberID, displayName, invitation.role],
      );
      await client.query(
        `INSERT INTO accounts (identity_subject, family_id, member_id, role)
         VALUES ($1, $2, $3, $4)`,
        [subject, invitation.family_id, memberID, invitation.role],
      );
      await client.query(
        "UPDATE family_invitations SET consumed_at = now() WHERE code_hash = $1",
        [codeHash],
      );
      await client.query(
        `INSERT INTO family_change_versions (family_id, version) VALUES ($1, 1)
         ON CONFLICT (family_id) DO UPDATE
         SET version = family_change_versions.version + 1, updated_at = now()`,
        [invitation.family_id],
      );
      await client.query("COMMIT");
      return {
        identitySubject: subject,
        familyID: invitation.family_id,
        memberID,
        role: invitation.role,
      };
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async familyChangeVersion(familyID: string): Promise<number> {
    const result = await this.pool.query<{ version: string }>(
      "SELECT version::text FROM family_change_versions WHERE family_id = $1",
      [familyID],
    );
    return Number(result.rows[0]?.version ?? 0);
  }

  async markFamilyChanged(familyID: string): Promise<void> {
    await this.pool.query(
      `INSERT INTO family_change_versions (family_id, version) VALUES ($1, 1)
       ON CONFLICT (family_id) DO UPDATE
       SET version = family_change_versions.version + 1, updated_at = now()`,
      [familyID],
    );
  }

  async eventsForFamily(familyID: string): Promise<FamilyEvent[]> {
    const result = await this.pool.query<EventRow>(
      `SELECT family_id, id::text, title, kid_id, participant_ids, start_time,
              end_time, location, driver, source, status, recurrence
       FROM events WHERE family_id = $1 ORDER BY start_time`,
      [familyID],
    );
    return result.rows.map(eventFromRow);
  }

  async saveEvent(event: FamilyEvent): Promise<void> {
    await this.pool.query(
      `INSERT INTO events (
         family_id, id, title, kid_id, participant_ids, start_time, end_time,
         location, driver, source, status, recurrence
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
       ON CONFLICT (family_id, id) DO UPDATE SET
         title=EXCLUDED.title, kid_id=EXCLUDED.kid_id,
         participant_ids=EXCLUDED.participant_ids, start_time=EXCLUDED.start_time,
         end_time=EXCLUDED.end_time, location=EXCLUDED.location,
         driver=EXCLUDED.driver, source=EXCLUDED.source, status=EXCLUDED.status,
         recurrence=EXCLUDED.recurrence`,
      [
        event.familyID, event.id, event.title, event.kidID, event.participantIDs,
        event.startTime, event.endTime, event.location, event.driver,
        event.source, event.status, event.recurrence ? JSON.stringify(event.recurrence) : null,
      ],
    );
  }

  async deleteEvent(familyID: string, eventID: string): Promise<void> {
    await this.pool.query("DELETE FROM events WHERE family_id = $1 AND id = $2", [familyID, eventID]);
  }

  async membersForFamily(familyID: string): Promise<FamilyMember[]> {
    const result = await this.pool.query<MemberRow>(
      `SELECT family_id, id, name, role, grade_or_birth_year, color_tag
       FROM family_members WHERE family_id = $1 ORDER BY name`,
      [familyID],
    );
    return result.rows.map((row) => ({
      familyID: row.family_id,
      id: row.id,
      name: row.name,
      role: row.role,
      colorTag: row.color_tag,
      ...(row.grade_or_birth_year !== null ? { gradeOrBirthYear: row.grade_or_birth_year } : {}),
    }));
  }

  async saveMember(member: FamilyMember): Promise<void> {
    await this.pool.query(
      `INSERT INTO family_members (family_id, id, name, role, grade_or_birth_year, color_tag)
       VALUES ($1,$2,$3,$4,$5,$6)
       ON CONFLICT (family_id, id) DO UPDATE SET
         name=EXCLUDED.name, role=EXCLUDED.role,
         grade_or_birth_year=EXCLUDED.grade_or_birth_year,
         color_tag=EXCLUDED.color_tag`,
      [
        member.familyID, member.id, member.name, member.role,
        member.gradeOrBirthYear ?? null, member.colorTag,
      ],
    );
  }

  async deleteMember(familyID: string, memberID: string): Promise<void> {
    await this.pool.query(
      "DELETE FROM family_members WHERE family_id = $1 AND id = $2",
      [familyID, memberID],
    );
  }
}

interface AccountRow {
  identity_subject: string;
  family_id: string;
  member_id: string;
  role: AccountRole;
}

interface InvitationRow {
  family_id: string;
  role: AccountRole;
}

interface EventRow {
  family_id: string;
  id: string;
  title: string;
  kid_id: string | null;
  participant_ids: string[];
  start_time: Date | string;
  end_time: Date | string;
  location: string | null;
  driver: string | null;
  source: FamilyEvent["source"];
  status: FamilyEvent["status"];
  recurrence: EventRecurrence | null;
}

interface MemberRow {
  family_id: string;
  id: string;
  name: string;
  role: AccountRole;
  grade_or_birth_year: string | null;
  color_tag: string;
}

function accountFromRow(row: AccountRow): Account {
  return {
    identitySubject: row.identity_subject,
    familyID: row.family_id,
    memberID: row.member_id,
    role: row.role,
  };
}

function eventFromRow(row: EventRow): FamilyEvent {
  return {
    familyID: row.family_id,
    id: row.id,
    title: row.title,
    kidID: row.kid_id,
    participantIDs: row.participant_ids,
    startTime: asISOString(row.start_time),
    endTime: asISOString(row.end_time),
    location: row.location,
    driver: row.driver,
    source: row.source,
    status: row.status,
    recurrence: row.recurrence,
  };
}

function asISOString(value: Date | string): string {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}
