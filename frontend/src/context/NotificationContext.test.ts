import { describe, expect, it } from 'vitest';
import { AppNotification, UserProfile } from '../types';
import { canUserReceiveNotification } from '../utils/notificationAudience';

const notification: AppNotification = {
  id: 'order-ORD-1-PLACED',
  title: 'Order placed',
  message: 'Order #ORD-1 was placed successfully.',
  type: 'order',
  timestamp: new Date(),
  read: false,
  orderNumber: 'ORD-1',
  userId: 'basic-subject',
  username: 'basic_user',
};

const user = (overrides: Partial<UserProfile> = {}): UserProfile => ({
  userId: 'basic-subject',
  username: 'basic_user',
  roles: ['USER'],
  isAdmin: false,
  ...overrides,
});

describe('live order notification audience', () => {
  it('delivers an order event to its owner', () => {
    expect(canUserReceiveNotification(user(), notification)).toBe(true);
  });

  it('does not expose another customer’s order event to a basic user', () => {
    expect(canUserReceiveNotification(user({ userId: 'someone-else', username: 'other_user' }), notification)).toBe(false);
  });

  it('allows administrators to monitor all order events', () => {
    expect(canUserReceiveNotification(user({ userId: 'admin-subject', username: 'admin_user', isAdmin: true }), notification)).toBe(true);
  });

  it('falls back to username only for legacy events without a subject ID', () => {
    expect(canUserReceiveNotification(user(), { ...notification, userId: undefined })).toBe(true);
    expect(canUserReceiveNotification(user({ username: 'other_user' }), { ...notification, userId: undefined })).toBe(false);
  });
});
