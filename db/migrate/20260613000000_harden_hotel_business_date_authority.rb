class HardenHotelBusinessDateAuthority < ActiveRecord::Migration[8.0]
  CURRENT_STATUSES = %w[open audit_running audit_blocked].freeze
  CLEANUP_REASON = "Migration cleanup: conflicting current business date".freeze
  REOPENED_REASON = "Migration cleanup: reopened is not supported for MVP".freeze

  class MigrationHotel < ActiveRecord::Base
    self.table_name = "hotels"

    has_many :hotel_business_dates, class_name: "HardenHotelBusinessDateAuthority::MigrationHotelBusinessDate",
      foreign_key: :hotel_id

    def expected_business_date
      zone = ActiveSupport::TimeZone[self[:time_zone].presence || "UTC"] || ActiveSupport::TimeZone["UTC"]
      local_time = Time.current.in_time_zone(zone)
      date = local_time.to_date

      return date if business_day_window(date, zone).cover?(local_time)
      return date - 1.day if business_day_window(date - 1.day, zone).cover?(local_time)

      date
    end

    private

    def business_day_window(date, zone)
      starts_at = self[:business_starts_at]&.utc || Time.utc(2000, 1, 1, 6, 0, 0)
      ends_at = self[:business_ends_at]&.utc || Time.utc(2000, 1, 1, 5, 59, 0)
      start_at = zone.local(date.year, date.month, date.day, starts_at.hour, starts_at.min)
      end_date = ends_at.seconds_since_midnight <= starts_at.seconds_since_midnight ? date + 1.day : date
      end_at = zone.local(end_date.year, end_date.month, end_date.day, ends_at.hour, ends_at.min)
      start_at...end_at
    end
  end

  class MigrationHotelBusinessDate < ActiveRecord::Base
    self.table_name = "hotel_business_dates"
  end

  def up
    add_reference :hotel_business_dates, :force_closed_by, foreign_key: { to_table: :users, on_delete: :nullify }
    add_column :hotel_business_dates, :force_closed_at, :datetime
    add_column :hotel_business_dates, :force_close_reason, :text

    execute "LOCK TABLE hotel_business_dates IN ACCESS EXCLUSIVE MODE"
    convert_reopened_rows
    clean_conflicting_current_rows
    backfill_missing_current_rows

    add_index :hotel_business_dates,
      :hotel_id,
      unique: true,
      where: "status IN ('open', 'audit_running', 'audit_blocked')",
      name: "idx_one_current_business_date_per_hotel"
  end

  def down
    remove_index :hotel_business_dates, name: "idx_one_current_business_date_per_hotel"
    remove_column :hotel_business_dates, :force_close_reason
    remove_column :hotel_business_dates, :force_closed_at
    remove_reference :hotel_business_dates, :force_closed_by
  end

  private

  def convert_reopened_rows
    MigrationHotelBusinessDate.where(status: "reopened").update_all(
      status: "force_closed",
      force_closed_at: Time.current,
      force_close_reason: REOPENED_REASON,
      closed_at: Time.current,
      updated_at: Time.current
    )
  end

  def clean_conflicting_current_rows
    duplicate_hotel_ids = MigrationHotelBusinessDate.where(status: CURRENT_STATUSES)
      .group(:hotel_id)
      .having("COUNT(*) > 1")
      .pluck(:hotel_id)

    duplicate_hotel_ids.each do |hotel_id|
      rows = MigrationHotelBusinessDate.where(hotel_id: hotel_id, status: CURRENT_STATUSES)
        .order(:business_date, :id)
        .to_a

      rows.drop(1).each do |row|
        row.update_columns(
          status: "force_closed",
          force_closed_at: Time.current,
          force_close_reason: CLEANUP_REASON,
          closed_at: Time.current,
          updated_at: Time.current
        )
      end
    end
  end

  def backfill_missing_current_rows
    MigrationHotel.find_each do |hotel|
      next if hotel.hotel_business_dates.where(status: CURRENT_STATUSES).exists?

      date = hotel.expected_business_date
      row = hotel.hotel_business_dates.find_or_initialize_by(business_date: date)
      row.update!(
        status: "open",
        opened_at: row.opened_at || Time.current,
        blockers_snapshot: row.blockers_snapshot || {}
      )
    end
  end
end
