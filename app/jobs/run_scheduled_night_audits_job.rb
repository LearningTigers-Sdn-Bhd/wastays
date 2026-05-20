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
    return if hotel.night_audits.exists?(business_date: business_date)

    night_audit = hotel.night_audits.build(
      business_date: business_date,
      status: "running",
      trigger_mode: "scheduled",
      started_at: Time.current,
      completed_at: nil,
      performed_by_user: nil,
      force_closed: false
    )
    if night_audit.save
      HotelOps::RunNightAuditJob.perform_later(night_audit.id, nil)
    else
      Rails.logger.error("Scheduled night audit could not be created for Hotel #{hotel.id}: #{night_audit.errors.full_messages.join(', ')}")
    end
  rescue StandardError => e
    Rails.logger.error("Scheduled night audit trigger failed for Hotel #{hotel.id}: #{e.message}")
  end
end
