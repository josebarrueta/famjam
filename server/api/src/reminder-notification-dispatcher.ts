import type { FamilyReminder } from "./domain.js";
import type { PushNotificationProvider } from "./push-notification-provider.js";

export interface ReminderNotificationRepository {
  claimDueReminderNotifications(now: Date, limit: number): Promise<FamilyReminder[]>;
  deviceTokensForMembers(familyID: string, memberIDs: string[]): Promise<string[]>;
  markReminderNotificationSent(familyID: string, reminderID: string, sentAt: Date): Promise<void>;
  releaseReminderNotificationClaim(familyID: string, reminderID: string, claimedAt: Date): Promise<void>;
}

interface Dependencies {
  repository: ReminderNotificationRepository;
  pushNotificationProvider: PushNotificationProvider;
  batchSize?: number;
}

export class ReminderNotificationDispatcher {
  private readonly repository: ReminderNotificationRepository;
  private readonly pushNotificationProvider: PushNotificationProvider;
  private readonly batchSize: number;

  constructor({ repository, pushNotificationProvider, batchSize = 100 }: Dependencies) {
    this.repository = repository;
    this.pushNotificationProvider = pushNotificationProvider;
    this.batchSize = batchSize;
  }

  async dispatchDue(now = new Date()): Promise<void> {
    const reminders = await this.repository.claimDueReminderNotifications(now, this.batchSize);
    const results = await Promise.allSettled(reminders.map(async (reminder) => {
      try {
        const tokens = await this.repository.deviceTokensForMembers(
          reminder.familyID,
          reminder.assigneeIDs,
        );
        if (tokens.length > 0) {
          await this.pushNotificationProvider.send(tokens, {
            title: reminder.title,
            body: "Reminder due. Open Rallyroo to review.",
            data: { reminderID: reminder.id },
          });
        }
        await this.repository.markReminderNotificationSent(reminder.familyID, reminder.id, now);
      } catch (error) {
        await this.repository.releaseReminderNotificationClaim(reminder.familyID, reminder.id, now);
        throw error;
      }
    }));
    const failures = results.filter((result) => result.status === "rejected");
    if (failures.length > 0) {
      throw new AggregateError(failures.map((failure) => failure.reason), "Reminder notification delivery failed");
    }
  }
}
