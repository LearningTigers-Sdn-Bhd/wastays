# frozen_string_literal: true

class RenameDetectedBookingStatuses < ActiveRecord::Migration[8.0]
  JSON_COLUMNS = {
    booking_audit_logs: %i[old_value new_value metadata],
    room_operational_audit_logs: %i[metadata],
    night_audits: %i[summary exceptions blocked_details],
    night_audit_logs: %i[metadata],
    folio_transactions: %i[metadata],
    financial_audit_events: %i[metadata]
  }.freeze

  def up
    rename_column :bookings, :no_show_review_business_date, :no_show_detected_business_date
    rename_index :bookings,
      "index_bookings_on_hotel_status_no_show_review_date",
      "index_bookings_on_hotel_status_no_show_detected_date"
    rename_vocabulary!("up")
  end

  def down
    rename_vocabulary!("down")
    rename_index :bookings,
      "index_bookings_on_hotel_status_no_show_detected_date",
      "index_bookings_on_hotel_status_no_show_review_date"
    rename_column :bookings, :no_show_detected_business_date, :no_show_review_business_date
  end

  private

  def rename_vocabulary!(direction)
    create_rename_functions!

    execute <<~SQL.squish
      UPDATE bookings
      SET status = CASE status
        WHEN #{quote(old_or_new(direction, "review_no_show", "no_show_detected"))}
          THEN #{quote(old_or_new(direction, "no_show_detected", "review_no_show"))}
        WHEN #{quote(old_or_new(direction, "review_due_out", "due_out_detected"))}
          THEN #{quote(old_or_new(direction, "due_out_detected", "review_due_out"))}
        ELSE status
      END
      WHERE status IN (
        #{quote(old_or_new(direction, "review_no_show", "no_show_detected"))},
        #{quote(old_or_new(direction, "review_due_out", "due_out_detected"))}
      )
    SQL

    rename_room_operational_columns!(direction)
    rename_financial_history!(direction)
    rename_json_columns!(direction)
  ensure
    execute("DROP FUNCTION IF EXISTS pg_temp.rename_detected_booking_json(jsonb, text)")
    execute("DROP FUNCTION IF EXISTS pg_temp.rename_detected_booking_event(text, text)")
    execute("DROP FUNCTION IF EXISTS pg_temp.rename_detected_booking_token(text, text)")
  end

  def rename_room_operational_columns!(direction)
    from_no_show = old_or_new(direction, "review_no_show", "no_show_detected")
    to_no_show = old_or_new(direction, "no_show_detected", "review_no_show")
    from_due_out = old_or_new(direction, "review_due_out", "due_out_detected")
    to_due_out = old_or_new(direction, "due_out_detected", "review_due_out")
    from_event = old_or_new(direction, "review_no_show_cancelled", "no_show_detection_cancelled")
    to_event = old_or_new(direction, "no_show_detection_cancelled", "review_no_show_cancelled")

    %i[old_status new_status].each do |column|
      execute <<~SQL.squish
        UPDATE room_operational_audit_logs
        SET #{column} = CASE #{column}
          WHEN #{quote(from_no_show)} THEN #{quote(to_no_show)}
          WHEN #{quote(from_due_out)} THEN #{quote(to_due_out)}
          ELSE #{column}
        END
        WHERE #{column} IN (#{quote(from_no_show)}, #{quote(from_due_out)})
      SQL
    end

    execute <<~SQL.squish
      UPDATE room_operational_audit_logs
      SET event_type = #{quote(to_event)}
      WHERE event_type = #{quote(from_event)}
    SQL
  end

  def rename_json_columns!(direction)
    search_tokens = if direction == "up"
      %w[review_no_show review_due_out detect_late_checkout due_out_review finalize_no_show_review]
    else
      %w[no_show_detected no_show_detection due_out_detected detect_no_show detect_due_out due_out_detection finalize_no_show_detection]
    end

    JSON_COLUMNS.each do |table, columns|
      columns.each do |column|
        predicate = search_tokens.map { |token| "#{column}::text LIKE #{quote("%#{token}%")}" }.join(" OR ")
        json_direction = direction == "down" && table == :night_audit_logs ? "down_log" : direction
        execute <<~SQL.squish
          UPDATE #{table}
          SET #{column} = pg_temp.rename_detected_booking_json(#{column}, #{quote(json_direction)})
          WHERE #{predicate}
        SQL
      end
    end
  end

  def rename_financial_history!(direction)
    from = old_or_new(direction, "finalize_no_show_review", "finalize_no_show_detection")
    to = old_or_new(direction, "finalize_no_show_detection", "finalize_no_show_review")

    execute <<~SQL.squish
      UPDATE folio_transactions
      SET correction_reason = #{quote(to)}
      WHERE correction_reason = #{quote(from)}
    SQL

    execute <<~SQL.squish
      UPDATE financial_audit_events
      SET reason = #{quote(to)}
      WHERE reason = #{quote(from)}
    SQL
  end

  def create_rename_functions!
    execute <<~SQL
      CREATE OR REPLACE FUNCTION pg_temp.rename_detected_booking_token(token text, direction text)
      RETURNS text
      LANGUAGE plpgsql
      IMMUTABLE
      STRICT
      AS $function$
      BEGIN
        IF direction = 'up' THEN
          RETURN CASE token
            WHEN 'review_no_show' THEN 'no_show_detected'
            WHEN 'review_due_out' THEN 'due_out_detected'
            WHEN 'detect_late_checkout' THEN 'detect_due_out'
            WHEN 'review_no_show_cancelled' THEN 'no_show_detection_cancelled'
            WHEN 'review_no_show_count' THEN 'no_show_detected_count'
            WHEN 'reviewed_no_show_count' THEN 'no_show_detected_count'
            WHEN 'reviewed_due_out_count' THEN 'due_out_detected_count'
            WHEN 'due_out_review' THEN 'due_out_detection'
            WHEN 'finalize_no_show_review' THEN 'finalize_no_show_detection'
            ELSE CASE
              WHEN token LIKE 'due_out_review:%'
                THEN 'due_out_detection:' || substr(token, length('due_out_review:') + 1)
              ELSE token
            END
          END;
        END IF;

        RETURN CASE token
          WHEN 'no_show_detected' THEN 'review_no_show'
          WHEN 'due_out_detected' THEN 'review_due_out'
          WHEN 'detect_due_out' THEN 'detect_late_checkout'
          WHEN 'no_show_detection_cancelled' THEN 'review_no_show_cancelled'
          WHEN 'no_show_detected_count' THEN CASE
            WHEN direction = 'down_log' THEN 'reviewed_no_show_count'
            ELSE 'review_no_show_count'
          END
          WHEN 'due_out_detected_count' THEN 'reviewed_due_out_count'
          WHEN 'due_out_detection' THEN 'due_out_review'
          WHEN 'finalize_no_show_detection' THEN 'finalize_no_show_review'
          ELSE CASE
            WHEN token LIKE 'due_out_detection:%'
              THEN 'due_out_review:' || substr(token, length('due_out_detection:') + 1)
            ELSE token
          END
        END;
      END;
      $function$;
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION pg_temp.rename_detected_booking_event(event_name text, direction text)
      RETURNS text
      LANGUAGE plpgsql
      IMMUTABLE
      STRICT
      AS $function$
      BEGIN
        IF direction = 'up' THEN
          RETURN CASE event_name
            WHEN 'review_no_show' THEN 'detect_no_show'
            WHEN 'detect_late_checkout' THEN 'detect_due_out'
            ELSE pg_temp.rename_detected_booking_token(event_name, direction)
          END;
        END IF;

        RETURN CASE event_name
          WHEN 'detect_no_show' THEN 'review_no_show'
          WHEN 'detect_due_out' THEN 'detect_late_checkout'
          ELSE pg_temp.rename_detected_booking_token(event_name, direction)
        END;
      END;
      $function$;
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION pg_temp.rename_detected_booking_json(payload jsonb, direction text)
      RETURNS jsonb
      LANGUAGE plpgsql
      IMMUTABLE
      STRICT
      AS $function$
      DECLARE
        rewritten jsonb;
      BEGIN
        CASE jsonb_typeof(payload)
        WHEN 'object' THEN
          SELECT COALESCE(
            jsonb_object_agg(
              pg_temp.rename_detected_booking_token(entry.key, direction),
              CASE
                WHEN entry.key IN ('event', 'trigger_event') AND jsonb_typeof(entry.value) = 'string'
                  THEN to_jsonb(pg_temp.rename_detected_booking_event(entry.value #>> '{}', direction))
                WHEN entry.key IN (
                  'status', 'booking_status', 'old_status', 'new_status', 'previous_status',
                  'from', 'to', 'event_type', 'target_status', 'item_type', 'type',
                  'correction_reason', 'override_reason'
                ) AND jsonb_typeof(entry.value) = 'string'
                  THEN to_jsonb(pg_temp.rename_detected_booking_token(entry.value #>> '{}', direction))
                WHEN entry.key = 'item_key' AND jsonb_typeof(entry.value) = 'string'
                  THEN to_jsonb(pg_temp.rename_detected_booking_token(entry.value #>> '{}', direction))
                ELSE pg_temp.rename_detected_booking_json(entry.value, direction)
              END
            ),
            '{}'::jsonb
          )
          INTO rewritten
          FROM jsonb_each(payload) AS entry;
          RETURN rewritten;
        WHEN 'array' THEN
          SELECT COALESCE(
            jsonb_agg(pg_temp.rename_detected_booking_json(item.value, direction) ORDER BY item.position),
            '[]'::jsonb
          )
          INTO rewritten
          FROM jsonb_array_elements(payload) WITH ORDINALITY AS item(value, position);
          RETURN rewritten;
        ELSE
          RETURN payload;
        END CASE;
      END;
      $function$;
    SQL
  end

  def old_or_new(direction, up_value, down_value)
    direction == "up" ? up_value : down_value
  end

  def quote(value)
    connection.quote(value)
  end
end
