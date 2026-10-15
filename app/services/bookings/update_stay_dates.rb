# frozen_string_literal: true

require "digest"
require "ostruct"

module Bookings
  class UpdateStayDates
    PURPOSE = "stay-date-correction".freeze
    Failure = Class.new(StandardError)
    StaleReview = Class.new(Failure)

    class CorrectionContext
      attr_reader :plans, :reason

      def initialize(preview:, reason: nil, expected_plans: nil)
        @preview = preview
        @reason = reason
        @plans = []
        @required = false
        @expected_plans = expected_plans
      end

      def preview?
        @preview
      end

      def required?
        @required
      end

      def add(plan, required:)
        @plans << plan
        @required ||= required
        if @expected_plans && @expected_plans.find { |expected| expected[:booking_id] == plan[:booking_id] } != plan
          raise StaleReview, "The correction details changed. Review them again before confirming."
        end
      end
    end

    def self.call(**attributes)
      new(**attributes).call
    end

    def initialize(bookings:, params:, user:, correction_reason: nil, correction_review_token: nil, retry_stale_review: true)
      @bookings = Array(bookings).uniq(&:id).sort_by(&:id)
      @params = params.to_h.symbolize_keys.slice(:check_in, :check_out)
      @user = user
      @reason = correction_reason.to_s.strip
      @token = correction_review_token.to_s
      @hotel = @bookings.first&.hotel
      @retry_stale_review = retry_stale_review
    end

    def call
      raise Failure, "Select at least one booking." if @bookings.empty?
      raise Failure, "Selected bookings must belong to this hotel." unless @bookings.all? { |booking| booking.hotel_id == @hotel.id }
      raise Failure, "You do not have permission to update this booking." unless allowed?("manage_bookings")
      raise Failure, "Check-in and check-out dates are required." if @params.values_at(:check_in, :check_out).any?(&:blank?)

      ActiveRecord::Base.transaction(requires_new: true) do
        record = @hotel.hotel_business_dates.current.lock.first
        raise Failure, "Hotel has no current accounting business date." unless record
        raise Failure, "Accounting business date changed. Reload the booking and try again." unless @hotel.current_business_date_record&.id == record.id
        @bookings.each(&:lock!)
        BookingFolio.where(booking_id: @bookings.map(&:id)).order(:id).lock.load
        eligible = HotelPortal::BookingLifecycleTargetPresenter::ELIGIBLE_STATUSES.fetch(:amend_stay)
        raise Failure, "One or more selected bookings are no longer eligible for stay amendment." unless @bookings.all? { |booking| booking.status.in?(eligible) }
        return success(corrected: true) if duplicate_confirmation? && correction_allowed? && @reason.present?

        @preview = CorrectionContext.new(preview: true)
        ActiveRecord::Base.transaction(requires_new: true) do
          update_bookings(@preview)
          raise ActiveRecord::Rollback
        end
        @bookings.each(&:reload)

        if @preview.required? || @token.present?
          @payload = review_payload
          unless verifier.verified(@token, purpose: PURPOSE) == @payload
            return review_result(message: @token.present? ? "The correction details changed or expired. Review them again before confirming." : nil)
          end
          return review_result(error: "An authorized manager must confirm this correction.") unless correction_allowed?
          return review_result(error: "Reason for correction is required.") if @reason.blank?
        end

        expected = @preview.plans if @preview.required? || @token.present?
        update_bookings(CorrectionContext.new(preview: false, reason: @reason, expected_plans: expected))
        success(corrected: @preview.required?)
      end
    rescue StaleReview => e
      @bookings.each(&:reload)
      return review_result(error: e.message) unless @retry_stale_review

      self.class.new(bookings: @bookings, params: @params, user: @user,
        correction_reason: @reason, correction_review_token: @token, retry_stale_review: false).call
    rescue StandardError => e
      @bookings.each(&:reload)
      review_result(error: e.message)
    end

    private

    def update_bookings(context)
      @bookings.each do |booking|
        result = UpdateStayService.new(booking: booking, params: @params, user: @user, correction_context: context).call
        raise Failure, "#{booking.reservation_reference.presence || booking.confirmation_token}: #{result.errors.to_sentence}" unless result.success?
      end
    end

    def allowed?(permission)
      @user&.superadmin? || @user&.has_permission?(permission, hotel: @hotel)
    end

    def correction_allowed?
      allowed?("manage_night_audit") && allowed?("override_financial_date_lock")
    end

    def verifier
      Rails.application.message_verifier(PURPOSE)
    end

    def scope_payload
      { "actor_id" => @user.id, "hotel_id" => @hotel.id, "booking_ids" => @bookings.map(&:id),
        "dates" => @params.transform_values { |value| value.to_s }.stringify_keys }
    end

    def review_payload
      scope_payload.merge("fingerprint" => Digest::SHA256.hexdigest(JSON.generate(@preview.plans)))
    end

    def duplicate_confirmation?
      return false if @token.blank?
      payload = verifier.verified(@token, purpose: PURPOSE)
      return false unless payload && payload.except("fingerprint") == scope_payload
      @bookings.all? do |booking|
        %i[check_in check_out].all? do |kind|
          booking.public_send(kind) == ScheduledStay.at_hotel_time(hotel: @hotel, value: @params.fetch(kind), kind: kind)
        end
      end
    end

    def review_result(error: nil, message: nil)
      plans = @preview&.plans || []
      token = @payload && verifier.generate(@payload, expires_in: 15.minutes, purpose: PURPOSE)
      OpenStruct.new(success?: false, correction_review: (plans if @preview&.required? || @token.present?),
        correction_review_token: token, correction_allowed?: @hotel && correction_allowed?,
        errors: Array(error), error: error, review_message: message)
    end

    def success(corrected: false)
      OpenStruct.new(success?: true, bookings: @bookings, booking: @bookings.first, corrected?: corrected)
    end
  end
end
