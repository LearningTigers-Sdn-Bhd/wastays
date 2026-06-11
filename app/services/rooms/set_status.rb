# frozen_string_literal: true

require "ostruct"

module Rooms
  class SetStatus
    ALLOWED_TRANSITIONS = {
      "ready" => %w[dirty out_of_service late_checkout_detected cleaning],
      "dirty" => %w[cleaning ready out_of_service late_checkout_detected],
      "cleaning" => %w[awaiting_inspection ready inspection_failed out_of_service],
      "awaiting_inspection" => %w[ready inspection_failed cleaning out_of_service],
      "inspection_failed" => %w[cleaning ready out_of_service],
      "out_of_service" => %w[ready dirty],
      "late_checkout_detected" => %w[dirty ready out_of_service]
    }.freeze

    def initialize(room_status:, status:, user:, reason: nil, booking: nil, event_type: "room_status_changed", metadata: {})
      @room_status = room_status
      @status = status.to_s
      @user = user
      @reason = reason
      @booking = booking
      @event_type = event_type
      @metadata = metadata
    end

    def call
      return success if @room_status.status == @status
      return failure("Unsupported room status: #{@status}.") unless RoomStatus::STATUSES.include?(@status)
      return failure("Notes are mandatory when marking a room as ready.") if @status == "ready" && @reason.blank?
      return failure(transition_error) unless allowed_transition?

      old_status = @room_status.status

      RoomStatus.transaction do
        @room_status.update!(
          status: @status,
          last_changed_by: @user,
          last_changed_at: Time.current,
          notes: @reason.presence || @room_status.notes
        )

        RoomOperationalAuditLog.create!(
          hotel: @room_status.hotel,
          room_type: @room_status.room_type,
          booking: @booking,
          user: @user,
          room_number: @room_status.room_number,
          event_type: @event_type,
          old_status: old_status,
          new_status: @status,
          reason: @reason,
          metadata: audit_metadata
        )

        if @status == "late_checkout_detected" && (booking_to_transition = find_active_booking).present?
          Bookings::TransitionStatus.new(
            booking: booking_to_transition,
            status: "review_due_out",
            user: @user,
            options: { event: "detect_late_checkout", reason: @reason }
          ).call
        end
      end

      success
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def find_active_booking
      @booking || @room_status.hotel.bookings.checked_in.joins(:booking_rooms)
                             .find_by(booking_rooms: { room_number: @room_status.room_number })
    end

    def allowed_transition?
      ALLOWED_TRANSITIONS.fetch(@room_status.status, []).include?(@status)
    end

    def transition_error
      "Cannot change room #{@room_status.room_number} from #{@room_status.status} to #{@status}."
    end

    def audit_metadata
      @metadata.presence || { "source" => "rooms_set_status" }
    end

    def success
      OpenStruct.new(success?: true, room_status: @room_status)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
