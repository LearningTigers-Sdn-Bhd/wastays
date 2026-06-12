# frozen_string_literal: true

class ChangeBookingStayDatesToDatetimes < ActiveRecord::Migration[8.0]
  class MigrationBooking < ActiveRecord::Base
    self.table_name = "bookings"
  end

  class MigrationHotel < ActiveRecord::Base
    self.table_name = "hotels"

    has_one :property_policy, class_name: "ChangeBookingStayDatesToDatetimes::MigrationPropertyPolicy", foreign_key: :hotel_id
  end

  class MigrationPropertyPolicy < ActiveRecord::Base
    self.table_name = "property_policies"
  end

  def up
    add_column :bookings, :scheduled_check_in_at, :datetime
    add_column :bookings, :scheduled_check_out_at, :datetime
    MigrationBooking.reset_column_information

    MigrationHotel.includes(:property_policy).find_each do |hotel|
      zone = Time.find_zone(hotel.time_zone.presence || "Kuala Lumpur") || Time.zone
      check_in_time = hotel.property_policy&.check_in_time.presence || "15:00"
      check_out_time = hotel.property_policy&.check_out_time.presence || "12:00"

      MigrationBooking.where(hotel_id: hotel.id).find_each do |booking|
        booking.update_columns(
          scheduled_check_in_at: zone.parse("#{booking.check_in} #{check_in_time}"),
          scheduled_check_out_at: zone.parse("#{booking.check_out} #{check_out_time}")
        )
      end
    end

    change_column_null :bookings, :scheduled_check_in_at, false
    change_column_null :bookings, :scheduled_check_out_at, false
    remove_column :bookings, :check_in
    remove_column :bookings, :check_out
    rename_column :bookings, :scheduled_check_in_at, :check_in
    rename_column :bookings, :scheduled_check_out_at, :check_out
    add_index :bookings, :check_in
    add_index :bookings, :check_out
  end

  def down
    remove_index :bookings, :check_in
    remove_index :bookings, :check_out
    add_column :bookings, :stay_check_in_date, :date
    add_column :bookings, :stay_check_out_date, :date
    MigrationBooking.reset_column_information

    MigrationBooking.find_each do |booking|
      booking.update_columns(
        stay_check_in_date: booking.check_in.to_date,
        stay_check_out_date: booking.check_out.to_date
      )
    end

    change_column_null :bookings, :stay_check_in_date, false
    change_column_null :bookings, :stay_check_out_date, false
    remove_column :bookings, :check_in
    remove_column :bookings, :check_out
    rename_column :bookings, :stay_check_in_date, :check_in
    rename_column :bookings, :stay_check_out_date, :check_out
  end
end
