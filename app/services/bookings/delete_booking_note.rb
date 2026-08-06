# frozen_string_literal: true

module Bookings
  class DeleteBookingNote
    Result = Data.define(:success?, :errors)

    def self.call(note:, actor:)
      new(note:, actor:).call
    end

    def initialize(note:, actor:)
      @note = note
      @actor = actor
    end

    def call
      body = @note.body
      note_id = @note.id
      Booking.transaction do
        @note.destroy!
        Bookings::RecordAuditLog.call!(
          auditable: @note.booking,
          user: @actor,
          action_type: "note_deleted",
          old_value: { "body" => body },
          new_value: {},
          metadata: { "note_id" => note_id }
        )
      end
      Result.new(true, [])
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
      Result.new(false, e.record.errors.full_messages)
    end
  end
end
