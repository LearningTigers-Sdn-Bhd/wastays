module NightAudits
  class RunScheduledJob < ApplicationJob
    queue_as :default

    def perform(business_date = nil)
      Hotel.where(status: %w[approved live]).find_each do |hotel|
        current_record = hotel.current_business_date_record ||
          HotelBusinessDate.initialize_for_hotel!(hotel: hotel, date: business_date.presence || hotel.business_date_for(Time.current))
        target_date = current_record.business_date
        next if business_date.present? && business_date.to_date != target_date
        next if target_date > hotel.latest_closable_business_date

        run_for_hotel(hotel, target_date)
      end
    end

    private

    def run_for_hotel(hotel, business_date)
      NightAudits::Schedule.call(
        hotel: hotel,
        business_date: business_date,
        performed_by_user: nil,
        trigger_mode: "scheduled"
      )
    rescue StandardError => e
      Rails.logger.error("Scheduled night audit trigger failed for Hotel #{hotel.id}: #{e.message}")
    end
  end
end
