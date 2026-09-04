# frozen_string_literal: true

# VIP used to be one boolean on the guest record. A guest record is shared by
# every property the guest has booked with, so one property marking a guest VIP
# showed that guest as VIP everywhere.
#
# VIP now lives in `metadata["vip_hotel_ids"]`, the same shape a blacklist uses.
# This backfill gives each existing VIP guest the flag at every property that
# already sees it: the properties holding their bookings, plus the property that
# created the record. Nothing changes on screen the day this runs. New marks go
# to one property only.
class BackfillGuestVipHotelIds < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      UPDATE guests
      SET metadata = COALESCE(guests.metadata, '{}'::jsonb)
                     || jsonb_build_object('vip_hotel_ids', scoped.hotel_ids)
      FROM (
        SELECT g.id,
               COALESCE(
                 jsonb_agg(DISTINCT h.hotel_id) FILTER (WHERE h.hotel_id IS NOT NULL),
                 '[]'::jsonb
               ) AS hotel_ids
        FROM guests g
        LEFT JOIN LATERAL (
          SELECT b.hotel_id
          FROM booking_guests bg
          JOIN bookings b ON b.id = bg.booking_id
          WHERE bg.guest_id = g.id
          UNION
          SELECT g.created_by_hotel_id AS hotel_id
        ) h ON TRUE
        WHERE g.vip = TRUE
        GROUP BY g.id
      ) AS scoped
      WHERE guests.id = scoped.id
        AND COALESCE(guests.metadata->'vip_hotel_ids', '[]'::jsonb) = '[]'::jsonb;
    SQL

    # A VIP record with no booking and no creating property has nowhere to hold
    # the flag. Leave the list empty and drop the column so it stops reading as
    # VIP at every property.
    execute(<<~SQL)
      UPDATE guests
      SET vip = FALSE
      WHERE vip = TRUE
        AND COALESCE(metadata->'vip_hotel_ids', '[]'::jsonb) = '[]'::jsonb;
    SQL
  end

  def down
    execute("UPDATE guests SET metadata = metadata - 'vip_hotel_ids' WHERE metadata ? 'vip_hotel_ids';")
  end
end
