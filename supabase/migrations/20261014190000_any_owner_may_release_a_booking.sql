-- ---------------------------------------------------------------------------
-- Any owner may change or release any booking
--
-- The first cut kept writes with the pilot holding the slot, so that one owner
-- could not quietly take another's Saturday. That is the right rule for a club
-- and the wrong one here: this is two or three people who fly the same
-- aeroplane and talk to each other. "Delete my Saturday, I'm stuck in
-- Vancouver" is a phone call, and the owner who answers it should be able to
-- act on it rather than explain that the app will not let them.
--
-- Nothing is lost by trusting them. Every row names its pilot, so a slot that
-- disappeared is still attributable in conversation, and bookings are
-- intentions -- no money, no logbook, nothing an audit turns on.
--
-- Creating a booking is untouched: you still book for yourself unless you are
-- an admin. Holding the aeroplane in somebody else's name is the one thing
-- here that is not an answer to a phone call.
-- ---------------------------------------------------------------------------

drop policy booking_write_own on public.booking;
drop policy booking_delete_own on public.booking;

create policy booking_write_members on public.booking
  for update to authenticated
  using (public.current_member_id() is not null)
  with check (public.current_member_id() is not null);

create policy booking_delete_members on public.booking
  for delete to authenticated
  using (public.current_member_id() is not null);
