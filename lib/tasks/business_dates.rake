# frozen_string_literal: true

namespace :business_dates do
  desc "Development only: move a hotel's working date to today. business_dates:advance[hotel_id] or leave blank for all"
  task :advance, [ :hotel_id ] => :environment do |_task, args|
    if Rails.env.production?
      abort "Refusing to run in production. The working date advances by running the night audit."
    end

    scope = args[:hotel_id].present? ? Hotel.where(id: args[:hotel_id]) : Hotel.all
    moved = 0

    scope.find_each do |hotel|
      today = hotel.business_date_for
      current = hotel.current_business_date_record
      next if current.nil? || current.business_date >= today

      # The day is closed and today is opened, leaving the days between with no
      # record at all. That is deliberate: Hotel#date_closed? already reads a
      # missing row as closed, and writing "closed" rows for them would assert
      # that audits ran on those days when they did not.
      #
      # This skips everything the audit does -- room charges, no-show detection,
      # journal batches -- so it resets a stale development database rather than
      # catching one up. Anything that cares about those postings has to run the
      # real audit.
      ActiveRecord::Base.transaction do
        current.update!(status: "closed", closed_at: Time.current)
        hotel.hotel_business_dates.create!(
          business_date: today, status: "open", opened_at: Time.current, blockers_snapshot: {}
        )
      end

      puts "#{hotel.name}: #{current.business_date} -> #{today}"
      moved += 1
    end

    puts moved.zero? ? "Every working date is already current." : "Moved #{moved} hotels."
  end
end
