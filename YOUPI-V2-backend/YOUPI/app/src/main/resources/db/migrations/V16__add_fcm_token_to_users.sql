-- ═══════════════════════════════════════════════════════════
-- V16: users -- add fcm_token for push notifications
--
-- Needed for the "recharge confirmed while app was closed" case:
-- when a recharge's fulfillment takes longer than the app's own
-- foreground polling/retry windows (see RechargeViewModel's
-- _pollOrderStatus and HomeScreen's _checkPendingCoinAnimation on the
-- Flutter side), the backend can now push a notification directly to
-- the device the moment RECHARGE_SUCCESS is reached -- even if the
-- user has since closed the app entirely. Tapping the notification
-- (or the app already being open) shows the gold coin reward
-- animation using the data carried in the push payload.
--
-- Nullable: a user with no token yet (denied permission, hasn't
-- opened the app on this build yet, etc.) just doesn't get a push --
-- PushNotificationService.kt already no-ops safely on a null/blank
-- token rather than failing the recharge confirmation itself.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE users
    ADD COLUMN fcm_token VARCHAR(255);