# frozen_string_literal: true

module Concierge
  # Is a person on the desk right now, and what do we tell the guest if not.
  #
  # One class answers for three surfaces -- the contact page badge, the chat
  # handover line, and the after-hours cards -- so the guest never reads two
  # different stories about the same desk.
  #
  # A hotel that has not filled the Contact and Escalation page answers
  # `render? == false`. Nothing is shown, rather than a guess.
  class FrontDeskStatusPresenter
    MINUTES_PER_DAY = 24 * 60

    def initialize(hotel:, now: Time.current)
      @hotel = hotel
      @now = now
    end

    def render? = contact.present?

    def always_open? = render? && contact.front_desk_open_24h?

    def open?
      return false unless render?
      return true if always_open?
      return false if opens_minute.nil? || closes_minute.nil?

      if crosses_midnight?
        current_minute >= opens_minute || current_minute < closes_minute
      else
        current_minute >= opens_minute && current_minute < closes_minute
      end
    end

    def headline
      return nil unless render?
      return "Front desk is open 24 hours" if always_open?
      return "Front desk is closed" unless open?
      return "Front desk is open" if closes_minute.nil?

      "Front desk is open until #{format_minute(closes_minute)}"
    end

    # Only a closed desk needs a second line, and only when it says something
    # the headline does not.
    def detail
      return nil if !render? || open? || opens_minute.nil?

      "Opens again at #{format_minute(opens_minute)}"
    end

    def after_hours_message = contact&.after_hours_message.presence

    def duty_manager_phone = contact&.duty_manager_phone.presence

    # What the chat writes to the guest who asked for a person.
    def handover_message
      return DEFAULT_HANDOVER if !render? || open?

      after_hours_message || closed_handover_message
    end

    def support_message(reason: nil)
      prefix = reason.to_s == "emergency" ? emergency_message : nil
      handoff = if !render? || open?
        "I have asked a team member to join. You can continue chatting while you wait."
      else
        closed_support_message
      end

      [ prefix, handoff ].compact_blank.join(" ")
    end

    DEFAULT_HANDOVER = "You asked to speak to a team member. Someone will join shortly."

    private

    attr_reader :hotel, :now

    def contact
      return @contact if defined?(@contact)

      @contact = hotel&.guest_contact
    end

    def closed_handover_message
      parts = [ "The front desk is closed." ]
      parts << "Call the duty manager on #{duty_manager_phone} for urgent help." if duty_manager_phone
      parts << "We answer other messages after #{format_minute(opens_minute)}." if opens_minute
      parts.join(" ")
    end

    def closed_support_message
      parts = [ "The front desk is closed." ]
      parts << after_hours_message if after_hours_message
      parts << "Call the duty manager on #{duty_manager_phone} for urgent help." if duty_manager_phone
      parts << "The team will answer other messages after #{format_minute(opens_minute)}." if opens_minute
      parts.join(" ")
    end

    def emergency_message
      parts = []
      parts << contact&.emergency_instructions.to_s.squish if contact&.emergency_instructions.present?
      parts << "Call #{contact.emergency_phone}." if contact&.emergency_phone.present?
      if contact&.emergency_services_number.present?
        parts << "Local emergency services: #{contact.emergency_services_number}."
      end
      parts.presence&.join(" ") || "If anyone is in immediate danger, call local emergency services now."
    end

    def crosses_midnight? = closes_minute <= opens_minute

    def opens_minute = @opens_minute ||= minute_of_day(contact.front_desk_opens_at)

    def closes_minute = @closes_minute ||= minute_of_day(contact.front_desk_closes_at)

    def current_minute
      @current_minute ||= minute_of_day(now.in_time_zone(hotel.hotel_time_zone))
    end

    def minute_of_day(time)
      return nil if time.blank?

      (time.hour * 60) + time.min
    end

    def format_minute(minute)
      Time.utc(2000, 1, 1, minute / 60, minute % 60).strftime("%-I:%M %p")
    end
  end
end
