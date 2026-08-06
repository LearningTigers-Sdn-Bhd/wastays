# frozen_string_literal: true

module Bookings
  class CreateBookingNote
    Result = Data.define(:success?, :note, :errors)

    def self.call(booking:, actor:, body:)
      new(booking:, actor:, body:).call
    end

    def initialize(booking:, actor:, body:)
      @booking = booking
      @actor = actor
      @body = body
    end

    def call
      note = @booking.booking_notes.build(body: @body, user: @actor)
      Booking.transaction do
        note.save!
        record_audit!(note, "note_added", old_value: {}, new_value: { "body" => note.body })
      end
      Result.new(true, note, [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(false, note, e.record.errors.full_messages)
    end

    private

    def record_audit!(note, action_type, old_value:, new_value:)
      Bookings::RecordAuditLog.call!(
        auditable: @booking,
        user: @actor,
        action_type:,
        old_value:,
        new_value:,
        metadata: { "note_id" => note.id }
      )
    end
  end
end
