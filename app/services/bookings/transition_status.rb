# frozen_string_literal: true

require "ostruct"

module Bookings
  class TransitionStatus
    def initialize(booking:, status:, timestamp: nil)
      @booking = booking
      @status = status.to_s
      @timestamp = timestamp || Time.current
    end

    def call
      case @status
      when "checked_in"
        check_in
      when "completed"
        check_out
      when "cancelled"
        cancel
      else
        failure("Unsupported status transition: #{@status}")
      end
    rescue StandardError => e
      failure(e.message)
    end

    private

    def check_in
      if @booking.update(status: "checked_in", checked_in_at: @timestamp)
        success
      else
        failure(@booking.errors.full_messages.to_sentence)
      end
    end

    def check_out
      if @booking.update(status: "completed", checked_out_at: @timestamp)
        success
      else
        failure(@booking.errors.full_messages.to_sentence)
      end
    end

    def cancel
      Booking.transaction do
        if @booking.update(status: "cancelled")
          InventoryManager.new(@booking).release
          success
        else
          failure(@booking.errors.full_messages.to_sentence)
        end
      end
    end

    def success
      OpenStruct.new(success?: true, booking: @booking)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
