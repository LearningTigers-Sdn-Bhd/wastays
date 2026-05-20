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
    existing_audit = hotel.night_audits.find_by(business_date: business_date)
    if existing_audit
      return if existing_audit.completed? || existing_audit.running?

      HotelOps::RunNightAuditJob.perform_later(existing_audit.id, nil)
      return
    end

    night_audit = hotel.night_audits.build(
      business_date: business_date,
      status: "pending",
      trigger_mode: "scheduled",
      started_at: nil,
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
