# frozen_string_literal: true

class MoveHousekeepingOperationsToRoomStatuses < ActiveRecord::Migration[8.0]
  def up
    add_reference :room_statuses, :assigned_to, foreign_key: { to_table: :users }, index: true

    execute <<~SQL.squish
      WITH ranked_tasks AS (
        SELECT
          housekeeping_requests.id,
          COALESCE(housekeeping_requests.hotel_id, bookings.hotel_id) AS hotel_id,
          COALESCE(housekeeping_requests.room_type_id, booking_rooms.room_type_id) AS room_type_id,
          COALESCE(NULLIF(housekeeping_requests.room_number, ''), booking_rooms.room_number) AS room_number,
          housekeeping_requests.request_details,
          housekeeping_requests.metadata,
          ROW_NUMBER() OVER (
            PARTITION BY COALESCE(housekeeping_requests.hotel_id, bookings.hotel_id),
                         COALESCE(housekeeping_requests.room_type_id, booking_rooms.room_type_id),
                         COALESCE(NULLIF(housekeeping_requests.room_number, ''), booking_rooms.room_number)
            ORDER BY COALESCE(housekeeping_requests.requested_at, housekeeping_requests.created_at) DESC,
                     housekeeping_requests.id DESC
          ) AS position
        FROM housekeeping_requests
        LEFT JOIN bookings ON bookings.id = housekeeping_requests.booking_id
        LEFT JOIN LATERAL (
          SELECT booking_rooms.room_type_id, booking_rooms.room_number
          FROM booking_rooms
          WHERE booking_rooms.booking_id = housekeeping_requests.booking_id
            AND (
              housekeeping_requests.room_number IS NULL OR
              housekeeping_requests.room_number = '' OR
              booking_rooms.room_number = housekeeping_requests.room_number
            )
        ) booking_rooms ON TRUE
        WHERE housekeeping_requests.work_context IN ('vacant_room_task', 'checkout_turnover')
          AND housekeeping_requests.archived_at IS NULL
          AND housekeeping_requests.status NOT IN ('completed', 'failed', 'cancelled')
      ), latest_tasks AS (
        SELECT * FROM ranked_tasks
        WHERE position = 1
          AND hotel_id IS NOT NULL
          AND room_type_id IS NOT NULL
          AND NULLIF(room_number, '') IS NOT NULL
      )
      INSERT INTO room_statuses (
        hotel_id, room_type_id, room_number, status, notes, assigned_to_id,
        created_at, updated_at
      )
      SELECT
        latest_tasks.hotel_id,
        latest_tasks.room_type_id,
        latest_tasks.room_number,
        'dirty',
        NULLIF(latest_tasks.request_details, ''),
        CASE
          WHEN latest_tasks.metadata->>'assigned_to' ~ '^[0-9]+$'
            AND EXISTS (
              SELECT 1
              FROM user_hotel_accesses
              JOIN roles ON roles.id = user_hotel_accesses.role_id
              WHERE user_hotel_accesses.user_id = (latest_tasks.metadata->>'assigned_to')::bigint
                AND user_hotel_accesses.hotel_id = latest_tasks.hotel_id
                AND user_hotel_accesses.deactivated_at IS NULL
                AND roles.slug = 'housekeeper'
            )
          THEN (latest_tasks.metadata->>'assigned_to')::bigint
          ELSE NULL
        END,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM latest_tasks
      JOIN room_types ON room_types.id = latest_tasks.room_type_id
                     AND room_types.hotel_id = latest_tasks.hotel_id
      ON CONFLICT (hotel_id, room_type_id, room_number) DO UPDATE SET
        notes = CASE
          WHEN NULLIF(BTRIM(room_statuses.notes), '') IS NULL THEN EXCLUDED.notes
          ELSE room_statuses.notes
        END,
        assigned_to_id = COALESCE(room_statuses.assigned_to_id, EXCLUDED.assigned_to_id),
        updated_at = CURRENT_TIMESTAMP
    SQL

    execute <<~SQL.squish
      UPDATE housekeeping_requests
      SET archived_at = COALESCE(archived_at, CURRENT_TIMESTAMP),
          updated_at = CURRENT_TIMESTAMP
      WHERE work_context IN ('vacant_room_task', 'checkout_turnover')
        AND archived_at IS NULL
    SQL
  end

  def down
    remove_reference :room_statuses, :assigned_to, foreign_key: { to_table: :users }, index: true
  end
end
