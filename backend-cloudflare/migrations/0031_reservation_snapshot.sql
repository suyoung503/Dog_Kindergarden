-- Existing reservations intentionally keep NULL; historical profile data cannot be reconstructed.
-- Photos remain in the existing private pet-photo flow, not in the booking snapshot.
ALTER TABLE reservations ADD COLUMN booking_snapshot TEXT;
