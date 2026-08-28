# frozen_string_literal: true

require "ostruct"

module Rooms
  class SetStatus
    class BookingTransitionFailed < StandardError; end

    ALLOWED_TRANSITIONS = {
      "ready" => %w[dirty out_of_service late_checkout_detected cleaning],
      "dirty" => %w[cleaning ready out_of_service late_checkout_detected],
      "cleaning" => %w[awaiting_inspection ready inspection_failed out_of_service],
      "awaiting_inspection" => %w[ready inspection_failed cleaning out_of_service],
      "inspection_failed" => %w[cleaning ready out_of_service],
      "out_of_service" => %w[ready dirty],
      "late_checkout_detected" => %w[dirty ready out_of_service]
    }.freeze

    def initialize(room_status:, status:, user:, reason: nil, booking: nil, event_type: "room_status_changed", metadata: {},
                   clear_assignment: false, enforce_transition: true)
      @room_status = room_status
      @status = status.to_s
      @user = user
      @reason = reason
      @booking = booking
      @event_type = event_type
      @metadata = metadata
      @clear_assignment = clear_assignment
      @enforce_transition = enforce_transition
    end

    def call
      return success if @room_status.status == @status
      return failure("Unsupported room status: #{@status}.") unless RoomStatus::STATUSES.include?(@status)
      return failure("A checked-in booking is required to report late checkout.") if @status == "late_checkout_detected" && @booking.blank?
      return failure(transition_error) if @enforce_transition && !allowed_transition?

      old_status = @room_status.status

      RoomStatus.transaction do
        updates = {
          status: @status,
          last_changed_by: @user,
          last_changed_at: Time.current,
          notes: @reason.presence || @room_status.notes
        }
        updates[:assigned_to] = nil if @status == "ready" && @clear_assignment

        @room_status.update!(updates)

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

        if @status == "late_checkout_detected"
          transition_result = Bookings::TransitionStatus.new(
            booking: @booking,
            status: "due_out_detected",
            user: @user,
            options: { event: "detect_due_out", reason: @reason }
          ).call
          raise BookingTransitionFailed, transition_result.error unless transition_result.success?
        end
      end

      success
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue BookingTransitionFailed => e
      failure(e.message)
    end

    private

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
