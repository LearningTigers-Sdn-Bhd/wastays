# frozen_string_literal: true

require "ostruct"

module Bookings
  class UpdateGroupStay
    BatchFailure = Class.new(StandardError)

    def self.call(group_booking:, booking_ids:, params:, user:, options: {})
      new(group_booking: group_booking, booking_ids: booking_ids, params: params, user: user, options: options).call
    end

    def initialize(group_booking:, booking_ids:, params:, user:, options: {})
      @group_booking = group_booking
      @booking_ids = Array(booking_ids).map { |id| Integer(id, exception: false) }.compact.uniq
      @params = params.to_h.symbolize_keys.slice(:check_in, :check_out)
      @user = user
      @options = options
    end

    def call
      bookings = selected_bookings
      validate_batch!(bookings)

      ActiveRecord::Base.transaction do
        bookings.each do |booking|
          result = ::Bookings::UpdateStayService.new(
            booking: booking,
            params: @params,
            user: @user
          ).call
          raise BatchFailure, result.errors.to_sentence unless result.success?
        end
      end

      OpenStruct.new(success?: true, bookings: bookings, error: nil)
    rescue BatchFailure, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
      OpenStruct.new(success?: false, bookings: [], error: e.message)
    end

    private

    def selected_bookings
      raise BatchFailure, "Select at least one booking." if @booking_ids.empty?

      bookings = @group_booking.bookings.where(id: @booking_ids).to_a
      raise BatchFailure, "One or more selected bookings are not part of this group." unless bookings.size == @booking_ids.size

      bookings
    end

    def validate_batch!(bookings)
      if @params[:check_in].blank? || @params[:check_out].blank?
        raise BatchFailure, "Check-in and check-out dates are required."
      end

      ineligible = bookings.reject { |b| b.status.in?(HotelPortal::BookingLifecycleTargetPresenter::ELIGIBLE_STATUSES.fetch(:amend_stay)) }
      if ineligible.any?
        raise BatchFailure, "One or more selected bookings are no longer eligible for stay amendment."
      end
    end
  end
end
