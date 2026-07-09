# frozen_string_literal: true

require "ostruct"
require "digest"

module FolioRouting
  class ApplyGroupBatch
    def self.call(group_booking:, actor:, booking_routes:, confirmation:, forecast_confirmation: nil, reason:, idempotency_key:)
      new(group_booking:, actor:, booking_routes:, confirmation:, forecast_confirmation:, reason:, idempotency_key:).call
    end

    def self.preview(group_booking:, booking_routes:)
      new(group_booking:, actor: nil, booking_routes:, confirmation: nil, forecast_confirmation: nil, reason: nil).preview
    end

    def initialize(group_booking:, actor:, booking_routes:, confirmation:, forecast_confirmation: nil, reason:, idempotency_key: nil)
      @group_booking = group_booking
      @actor = actor
      @booking_routes = booking_routes.to_h.transform_keys(&:to_s).transform_values { |routes| routes.to_h }
      @confirmation = confirmation.to_s
      @forecast_confirmation = forecast_confirmation.to_s
      @reason = reason.to_s.strip
      @idempotency_key = idempotency_key.to_s
    end

    def call
      return failure("Select at least one booking to change.") if @booking_routes.empty?
      return failure("This group billing-route request is missing its idempotency key.") if @idempotency_key.blank?
      return failure("One or more selected bookings are not part of this group.") if bookings.size != @booking_routes.keys.size

      moved = []
      touched_ids = []
      ActiveRecord::Base.transaction do
        @group_booking.lock!
        bookings.each(&:lock!)

        batch = @group_booking.group_billing_change_batches.find_by(idempotency_key: @idempotency_key)
        if batch && batch.payload_digest != payload_digest
          raise ActiveRecord::Rollback, (@error = "This idempotency key was already used for a different group billing change.")
        end
        if batch&.completed_at?
          return OpenStruct.new(success?: true, transactions: [], touched_booking_ids: [])
        end
        batch ||= @group_booking.group_billing_change_batches.create!(
          hotel: @group_booking.hotel, actor: @actor, idempotency_key: @idempotency_key, payload_digest: payload_digest
        )

        bookings.each do |booking|
          routes = @booking_routes.fetch(booking.id.to_s, {})
          next if routes.blank?

          preview = ApplyBatch.preview(booking: booking, routes: routes)
          unless preview.success?
            raise ActiveRecord::Rollback, (@error = "Booking No. #{booking.formatted_reservation_number}: #{preview.error}")
          end
          next if preview.changes.empty? && preview.child_changes.empty? && preview.tax_changes.empty?

          result = ApplyBatch.call(
            booking: booking, actor: @actor, routes: routes,
            confirmation: @confirmation, forecast_confirmation: @forecast_confirmation,
            reason: @reason, idempotency_key: "#{@idempotency_key}:#{booking.id}"
          )
          unless result.success?
            raise ActiveRecord::Rollback, (@error = "Booking No. #{booking.formatted_reservation_number}: #{result.error}")
          end

          moved.concat(result.transactions)
          touched_ids << booking.id
        end

        raise ActiveRecord::Rollback if @error

        BookingAuditLog.create!(hotel: @group_booking.hotel, auditable: @group_booking, user: @actor,
          action_type: "group_billing_routes_changed", category: "financial", source: "booking_control_panel",
          occurred_at: Time.current, new_value: { booking_ids: touched_ids, confirmation: @confirmation,
            forecast_confirmation: @forecast_confirmation, reason: @reason })
        batch.update!(status: "completed", completed_at: Time.current)
      end
      return failure(@error) if @error

      OpenStruct.new(success?: true, transactions: moved, touched_booking_ids: touched_ids)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    def preview
      results = bookings.filter_map do |booking|
        routes = @booking_routes.fetch(booking.id.to_s, {})
        next if routes.blank?

        booking_preview = ApplyBatch.preview(booking: booking, routes: routes)
        return failure(booking_preview.error) unless booking_preview.success?

        { booking: booking, preview: booking_preview }
      end

      OpenStruct.new(success?: true, bookings: results,
        count: results.sum { |item| item[:preview].count },
        amount: results.sum { |item| item[:preview].amount },
        upcoming_count: results.sum { |item| item[:preview].upcoming_count },
        upcoming_amount: results.sum { |item| item[:preview].upcoming_amount },
        review_required?: results.any? { |item| item[:preview].review_required? })
    end

    private

    def bookings
      @bookings ||= @group_booking.bookings.where(id: @booking_routes.keys).order(:id).to_a
    end

    def payload_digest
      @payload_digest ||= Digest::SHA256.hexdigest({
        group_booking_id: @group_booking.id,
        booking_routes: @booking_routes.sort.to_h,
        confirmation: @confirmation,
        forecast_confirmation: @forecast_confirmation
      }.to_json)
    end

    def failure(message)
      OpenStruct.new(success?: false, error: message)
    end
  end
end
