# frozen_string_literal: true

class EncryptBookingGuestSensitiveSnapshots < ActiveRecord::Migration[8.0]
  class MigrationBookingGuest < ActiveRecord::Base
    self.table_name = "booking_guests"

    encrypts :email_snapshot, deterministic: true
    encrypts :phone_snapshot, deterministic: true
    encrypts :government_id_snapshot, deterministic: true
  end

  COLUMNS = %w[email_snapshot phone_snapshot government_id_snapshot].freeze

  def up
    MigrationBookingGuest.reset_column_information

    MigrationBookingGuest.find_each do |booking_guest|
      attrs = raw_snapshot_values(booking_guest.id).transform_values { |value| normalize_snapshot(value) }
      # update_columns writes the freshly-computed values directly, without going
      # through assign_attributes/save!'s dirty-check — which would force AR to
      # decrypt the *original* stored ciphertext just to compare it, defeating the
      # rescue-wrapped decrypt above for rows encrypted under since-rotated keys.
      booking_guest.update_columns(attrs)
    end
  end

  def down
    # Sensitive snapshots should not be intentionally downgraded to plaintext.
  end

  private

  def raw_snapshot_values(id)
    row = select_one(<<~SQL.squish)
      SELECT #{COLUMNS.join(", ")}
      FROM booking_guests
      WHERE id = #{quote(id)}
    SQL

    row.slice(*COLUMNS)
  end

  def normalize_snapshot(value)
    text = value.to_s.strip
    return nil if text.blank?

    decrypt_snapshot(text) || (envelope_like?(text) ? nil : text)
  end

  def decrypt_snapshot(text)
    return unless envelope_like?(text)

    ActiveRecord::Encryption.encryptor.decrypt(text)
  rescue ActiveRecord::Encryption::Errors::Base, JSON::ParserError, ArgumentError
    nil
  end

  def envelope_like?(text)
    text.start_with?("{\"p\":", "{\"p\"=>", "{\"ct\":", "{\"iv\":") || text.include?("\"_rails\"") || text.include?("\"ciphertext\"")
  end
end
