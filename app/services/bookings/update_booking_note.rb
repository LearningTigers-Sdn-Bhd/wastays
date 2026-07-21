# frozen_string_literal: true

module Bookings
  class UpdateBookingNote
    Result = Data.define(:success?, :note, :errors)

    def self.call(note:, actor:, body:)
      new(note:, actor:, body:).call
    end

    def initialize(note:, actor:, body:)
      @note = note
      @actor = actor
      @body = body.to_s.strip
    end

    def call
      if @body.blank?
        @note.errors.add(:body, "can't be blank")
        return Result.new(false, @note, @note.errors.full_messages)
      end

      previous_body = @note.body
      history = Array(@note.edit_history)
      if @body != previous_body
        history += [ { body: previous_body, edited_at: Time.current.iso8601, edited_by_name: @actor.name } ]
      end

      Booking.transaction do
        @note.update!(body: @body, edit_history: history)
        Bookings::RecordAuditLog.call!(
          auditable: @note.booking,
          user: @actor,
          action_type: "note_updated",
          old_value: { "body" => previous_body },
          new_value: { "body" => @body },
          metadata: { "note_id" => @note.id }
        )
      end
      Result.new(true, @note, [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(false, @note, e.record.errors.full_messages)
    end
  end
end
