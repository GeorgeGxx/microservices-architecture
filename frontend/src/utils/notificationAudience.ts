import { AppNotification, UserProfile } from '../types';

export function canUserReceiveNotification(user: UserProfile, notification: AppNotification): boolean {
  if (user.isAdmin) return true;
  if (notification.userId) return notification.userId === user.userId;
  return Boolean(notification.username && notification.username.toLowerCase() === user.username.toLowerCase());
}
