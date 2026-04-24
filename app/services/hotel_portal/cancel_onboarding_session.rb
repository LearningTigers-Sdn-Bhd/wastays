# frozen_string_literal: true

module HotelPortal
  class CancelOnboardingSession
    Result = Struct.new(:success?, :error)

    def initialize(session, reason)
      @session = session
      @reason = reason.to_s.strip
    end

    def call
      return Result.new(false, "Only scheduled sessions can be cancelled.") unless @session.status == "scheduled"
      return Result.new(false, "Please provide a reason before cancelling the session.") if @reason.blank?

      if @session.update(
        status: "cancelled",
        notes: [ @session.notes.presence, "CANCELLED: #{@reason}" ].compact.join("\n")
      )
        Result.new(true, nil)
      else
        Result.new(false, @session.errors.full_messages.to_sentence)
      end
    rescue => e
      Result.new(false, e.message)
    end
  end
end
