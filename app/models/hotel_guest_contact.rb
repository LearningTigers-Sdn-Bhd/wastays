# frozen_string_literal: true

# Who a guest reaches when the concierge cannot answer, and when that person is
# there. One row per hotel. The public contact page, the chat handover, and the
# Guest Content overview all read it.
class HotelGuestContact < ApplicationRecord
  # The reasons a hotel can tell the concierge to stop and fetch a person.
  # The order here is the order the settings page shows them.
  ESCALATION_TRIGGER_OPTIONS = [
    { value: "no_answer", label: "Cannot answer",
      description: "The concierge did not find the answer in your content." },
    { value: "guest_asks_for_person", label: "Guest asks for a person",
      description: "The guest asks to speak to a member of staff." },
    { value: "complaint", label: "Complaint",
      description: "The guest reports a problem with the stay." },
    { value: "booking_change", label: "Booking change",
      description: "The guest wants to move, extend, or cancel a stay." },
    { value: "payment_question", label: "Payment or bill",
      description: "The guest asks about a charge, a refund, or a folio." }
  ].freeze

  ESCALATION_TRIGGERS = ESCALATION_TRIGGER_OPTIONS.map { |option| option[:value] }.freeze

  ESCALATION_ATTEMPTS_RANGE = (1..5).freeze

  belongs_to :hotel

  validates :hotel_id, uniqueness: true
  validates :front_desk_opens_at, :front_desk_closes_at,
    presence: true, unless: :front_desk_open_24h?
  validates :escalation_attempts, inclusion: { in: ESCALATION_ATTEMPTS_RANGE }

  # The form sends "07:00". A time column keeps the clock and throws the date
  # away, so parse in UTC and read it back the same way -- the hotel's own zone
  # is applied later, when the clock is compared against now.
  def front_desk_opens_at
    read_attribute(:front_desk_opens_at)&.utc
  end

  def front_desk_opens_at=(value)
    write_clock_attribute(:front_desk_opens_at, value) { super }
  end

  def front_desk_closes_at
    read_attribute(:front_desk_closes_at)&.utc
  end

  def front_desk_closes_at=(value)
    write_clock_attribute(:front_desk_closes_at, value) { super }
  end

  def escalates_on?(trigger)
    escalation_triggers.include?(trigger.to_s)
  end

  def emergency_present?
    [ emergency_phone, emergency_services_number, emergency_instructions ].any?(&:present?)
  end

  private

  def write_clock_attribute(attribute, value)
    if value.is_a?(String) && value.present?
      write_attribute(attribute, Time.find_zone("UTC").parse(value))
    else
      yield
    end
  end
end
