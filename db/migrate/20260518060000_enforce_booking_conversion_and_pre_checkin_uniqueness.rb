class EnforceBookingConversionAndPreCheckinUniqueness < ActiveRecord::Migration[8.0]
  class MigrationBooking < ActiveRecord::Base
    self.table_name = "bookings"

    has_many :payment_transactions, class_name: "EnforceBookingConversionAndPreCheckinUniqueness::MigrationPaymentTransaction", foreign_key: :booking_id
    has_one :booking_folio, class_name: "EnforceBookingConversionAndPreCheckinUniqueness::MigrationBookingFolio", foreign_key: :booking_id
    has_many :booking_rooms, class_name: "EnforceBookingConversionAndPreCheckinUniqueness::MigrationBookingRoom", foreign_key: :booking_id
    has_many :booking_guests, class_name: "EnforceBookingConversionAndPreCheckinUniqueness::MigrationBookingGuest", foreign_key: :booking_id
  end

  class MigrationPreCheckin < ActiveRecord::Base
    self.table_name = "pre_checkins"
  end

  class MigrationPaymentTransaction < ActiveRecord::Base
    self.table_name = "payment_transactions"
  end

  class MigrationBookingFolio < ActiveRecord::Base
    self.table_name = "booking_folios"
  end

  class MigrationBookingRoom < ActiveRecord::Base
    self.table_name = "booking_rooms"
  end

  class MigrationBookingGuest < ActiveRecord::Base
    self.table_name = "booking_guests"
  end

  STATUS_PRIORITY = {
    "checked_in" => 60,
    "completed" => 50,
    "confirmed" => 40,
    "no_show" => 30,
    "cancelled" => 20,
    "pending" => 10
  }.freeze

  def up
    resolve_duplicate_quote_bookings!
    resolve_duplicate_pre_checkin_bookings!
    resolve_duplicate_pre_checkin_tokens!

    remove_index :bookings, :booking_quote_id, if_exists: true
    add_index :bookings, :booking_quote_id,
      unique: true,
      where: "booking_quote_id IS NOT NULL",
      name: "index_bookings_on_booking_quote_id_unique",
      if_not_exists: true

    remove_index :pre_checkins, :booking_id, if_exists: true
    add_index :pre_checkins, :booking_id, unique: true, if_not_exists: true
    add_index :pre_checkins, :token, unique: true, if_not_exists: true
  end

  def down
    remove_index :pre_checkins, :token, if_exists: true
    remove_index :pre_checkins, :booking_id, if_exists: true
    add_index :pre_checkins, :booking_id, if_not_exists: true

    remove_index :bookings, name: "index_bookings_on_booking_quote_id_unique", if_exists: true
    add_index :bookings, :booking_quote_id, if_not_exists: true
  end

  private

  def resolve_duplicate_quote_bookings!
    duplicate_quote_ids.each do |quote_id|
      bookings = MigrationBooking.where(booking_quote_id: quote_id).to_a
      winner = bookings.max_by { |booking| booking_score(booking) }

      bookings.each do |booking|
        next if booking.id == winner.id

        booking.update_columns(booking_quote_id: nil, updated_at: Time.current)
      end
    end
  end

  def resolve_duplicate_pre_checkin_bookings!
    duplicate_pre_checkin_booking_ids.each do |booking_id|
      pre_checkins = MigrationPreCheckin.where(booking_id: booking_id).to_a
      winner = pre_checkins.max_by { |pre_checkin| pre_checkin_score(pre_checkin) }

      MigrationPreCheckin.where(id: pre_checkins.map(&:id) - [ winner.id ]).delete_all
    end
  end

  def resolve_duplicate_pre_checkin_tokens!
    duplicate_pre_checkin_tokens.each do |token|
      MigrationPreCheckin.where(token: token).order(:id).to_a.drop(1).each do |pre_checkin|
        pre_checkin.update_columns(token: unique_pre_checkin_token, updated_at: Time.current)
      end
    end
  end

  def duplicate_quote_ids
    select_values(<<~SQL)
      SELECT booking_quote_id
      FROM bookings
      WHERE booking_quote_id IS NOT NULL
      GROUP BY booking_quote_id
      HAVING COUNT(*) > 1
    SQL
  end

  def duplicate_pre_checkin_booking_ids
    select_values(<<~SQL)
      SELECT booking_id
      FROM pre_checkins
      GROUP BY booking_id
      HAVING COUNT(*) > 1
    SQL
  end

  def duplicate_pre_checkin_tokens
    select_values(<<~SQL)
      SELECT token
      FROM pre_checkins
      WHERE token IS NOT NULL
      GROUP BY token
      HAVING COUNT(*) > 1
    SQL
  end

  def booking_score(booking)
    [
      booking.payment_transactions.where(status: "captured").exists? ? 1 : 0,
      booking.booking_folio.present? ? 1 : 0,
      booking.booking_rooms.exists? ? 1 : 0,
      booking.booking_guests.exists? ? 1 : 0,
      STATUS_PRIORITY.fetch(booking.status, 0),
      booking.updated_at || Time.zone.at(0),
      booking.id
    ]
  end

  def pre_checkin_score(pre_checkin)
    [
      pre_checkin.status == "completed" ? 1 : 0,
      pre_checkin.updated_at || Time.zone.at(0),
      pre_checkin.id
    ]
  end

  def unique_pre_checkin_token
    loop do
      token = SecureRandom.hex(20)
      return token unless MigrationPreCheckin.exists?(token: token)
    end
  end
end
