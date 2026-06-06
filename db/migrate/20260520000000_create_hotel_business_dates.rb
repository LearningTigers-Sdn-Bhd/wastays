class CreateHotelBusinessDates < ActiveRecord::Migration[8.0]
  class MigrationHotel < ActiveRecord::Base
    self.table_name = "hotels"

    def business_date_for(time = Time.current)
      zone_name = self[:time_zone].presence || "UTC"
      zone = ActiveSupport::TimeZone[zone_name] || ActiveSupport::TimeZone["UTC"]
      local_time = time.in_time_zone(zone)
      date = local_time.to_date

      return date if business_day_window_for(date, zone).cover?(local_time)
      return date - 1.day if business_day_window_for(date - 1.day, zone).cover?(local_time)

      date
    end

    private

    def business_day_window_for(date, zone)
      starts_at = self[:business_starts_at]&.utc || Time.utc(2000, 1, 1, 6, 0, 0)
      ends_at = self[:business_ends_at]&.utc || Time.utc(2000, 1, 1, 5, 59, 0)
      start_at = zone.local(date.year, date.month, date.day, starts_at.hour, starts_at.min)
      end_date = ends_at.seconds_since_midnight <= starts_at.seconds_since_midnight ? date + 1.day : date
      end_at = zone.local(end_date.year, end_date.month, end_date.day, ends_at.hour, ends_at.min)

      start_at...end_at
    end
  end

  class MigrationNightAudit < ActiveRecord::Base
    self.table_name = "night_audits"
  end

  class MigrationHotelBusinessDate < ActiveRecord::Base
    self.table_name = "hotel_business_dates"
  end

  def up
    create_table :hotel_business_dates do |t|
      t.references :hotel, null: false, foreign_key: true
      t.date :business_date, null: false
      t.string :status, null: false, default: "open"
      t.datetime :opened_at
      t.datetime :audit_started_at
      t.datetime :blocked_at
      t.datetime :closed_at
      t.jsonb :blockers_snapshot, null: false, default: {}

      t.timestamps
    end

    add_index :hotel_business_dates, [ :hotel_id, :business_date ], unique: true
    add_index :hotel_business_dates, [ :hotel_id, :status ]
    add_index :hotel_business_dates, [ :hotel_id, :business_date, :status ]

    backfill_closed_business_dates
    backfill_current_open_business_dates
  end

  def down
    drop_table :hotel_business_dates
  end

  private

  def backfill_closed_business_dates
    MigrationNightAudit.where(status: "completed").find_each do |night_audit|
      business_date = MigrationHotelBusinessDate.find_or_initialize_by(
        hotel_id: night_audit.hotel_id,
        business_date: night_audit.business_date
      )

      business_date.status = "closed"
      business_date.opened_at ||= night_audit.created_at
      business_date.closed_at = night_audit.completed_at || night_audit.updated_at
      business_date.created_at ||= Time.current
      business_date.updated_at = Time.current
      business_date.save!
    end
  end

  def backfill_current_open_business_dates
    MigrationHotel.find_each do |hotel|
      current_business_date = hotel.business_date_for(Time.current)

      MigrationHotelBusinessDate.find_or_create_by!(
        hotel_id: hotel.id,
        business_date: current_business_date
      ) do |business_date|
        business_date.status = "open"
        business_date.opened_at = Time.current
        business_date.created_at = Time.current
        business_date.updated_at = Time.current
      end
    end
  end
end
