# frozen_string_literal: true

class CreateBookingConfirmationTokens < ActiveRecord::Migration[8.0]
  TOKEN_CHARSET = (("A".."Z").to_a + ("2".."9").to_a - %w[I O L]).freeze

  def up
    create_table :booking_confirmation_tokens do |t|
      t.string :token, null: false
      t.references :booking, foreign_key: true, index: false
      t.references :group_booking, foreign_key: true, index: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :booking_confirmation_tokens, :token, unique: true
    add_index :booking_confirmation_tokens, :booking_id, unique: true, where: "booking_id IS NOT NULL"
    add_index :booking_confirmation_tokens, :group_booking_id, unique: true, where: "group_booking_id IS NOT NULL"
    add_check_constraint :booking_confirmation_tokens,
      "num_nonnulls(booking_id, group_booking_id) = 1",
      name: "booking_confirmation_tokens_exactly_one_owner"

    execute <<~SQL.squish
      INSERT INTO booking_confirmation_tokens (token, booking_id, metadata, created_at, updated_at)
      SELECT confirmation_token, id, '{}'::jsonb, created_at, updated_at
      FROM bookings
      ORDER BY id
    SQL

    say_with_time "Backfilling group booking confirmation tokens" do
      select_all("SELECT id, confirmation_token, created_at, updated_at FROM group_bookings ORDER BY id").each do |row|
        original = row.fetch("confirmation_token")
        token = original
        token = generate_token while token_exists?(token)

        if token != original
          execute <<~SQL.squish
            UPDATE group_bookings
            SET confirmation_token = #{quote(token)}, updated_at = #{quote(row.fetch("updated_at"))}
            WHERE id = #{quote(row.fetch("id"))}
          SQL
        end

        metadata = token == original ? {} : { migration: "shared_confirmation_tokens", previous_token: original }
        execute <<~SQL.squish
          INSERT INTO booking_confirmation_tokens
            (token, group_booking_id, metadata, created_at, updated_at)
          VALUES
            (#{quote(token)}, #{quote(row.fetch("id"))}, #{quote(metadata.to_json)}::jsonb,
             #{quote(row.fetch("created_at"))}, #{quote(row.fetch("updated_at"))})
        SQL
      end
    end
  end

  def down
    drop_table :booking_confirmation_tokens
  end

  private

  def generate_token
    Array.new(6) { TOKEN_CHARSET.sample }.join
  end

  def token_exists?(token)
    select_value("SELECT 1 FROM booking_confirmation_tokens WHERE token = #{quote(token)} LIMIT 1").present?
  end
end
