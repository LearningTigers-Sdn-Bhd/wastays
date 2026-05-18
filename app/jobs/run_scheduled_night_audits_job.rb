class RunScheduledNightAuditsJob < ApplicationJob
  queue_as :default

  def perform(business_date = nil)
    Hotel.where(status: %w[approved live]).find_each do |hotel|
      target_date = business_date.present? ? business_date.to_date : hotel.latest_closable_business_date
      run_for_hotel(hotel, target_date)
    end
  end

  private

  def run_for_hotel(hotel, business_date)
    HotelOps::RunNightAudit.new(
      hotel: hotel,
      business_date: business_date,
      performed_by_user: nil,
      trigger_mode: "scheduled"
    ).call
  rescue StandardError => e
    Rails.logger.error("Scheduled night audit failed for Hotel #{hotel.id}: #{e.message}")
  end
end
