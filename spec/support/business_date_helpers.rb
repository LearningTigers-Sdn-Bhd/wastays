# frozen_string_literal: true

module BusinessDateHelpers
  def current_business_date_record(hotel)
    hotel.reload.current_business_date_record
  end

  def initialize_business_date(hotel, date:)
    HotelBusinessDate.initialize_for_hotel!(hotel: hotel, date: date)
  end

  def start_business_date_audit(hotel, actor: nil, system_context: actor.nil?)
    BusinessDates::StartAudit.call!(hotel: hotel, actor: actor, system_context: system_context)
  end

  def block_business_date_audit(hotel, blockers: {}, actor: nil, system_context: actor.nil?)
    BusinessDates::BlockAudit.call!(
      hotel: hotel,
      blockers: blockers,
      actor: actor,
      system_context: system_context
    )
  end

  def retry_business_date_audit(hotel, actor: nil, system_context: actor.nil?)
    BusinessDates::RetryAudit.call!(hotel: hotel, actor: actor, system_context: system_context)
  end

  def close_and_open_next_business_date(hotel, actor: nil, system_context: actor.nil?)
    BusinessDates::CloseAndOpenNext.call!(hotel: hotel, actor: actor, system_context: system_context)
  end

  def force_close_business_date(hotel, actor:, reason:, blockers: nil)
    BusinessDates::ForceClose.call!(hotel: hotel, actor: actor, reason: reason, blockers: blockers)
  end

  def advance_business_date_to(hotel, date, actor: nil, system_context: actor.nil?)
    target_date = date.to_date

    while hotel.reload.current_business_date < target_date
      start_business_date_audit(hotel, actor: actor, system_context: system_context)
      close_and_open_next_business_date(hotel, actor: actor, system_context: system_context)
    end

    current_business_date_record(hotel)
  end
end

RSpec.configure do |config|
  config.include BusinessDateHelpers
end
