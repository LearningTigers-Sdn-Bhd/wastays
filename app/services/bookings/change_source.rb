# frozen_string_literal: true

module Bookings
  # Corrects the channel a booking was recorded under, e.g. a Booking.com
  # reservation keyed at the desk as "Phone".
  #
  # Most of what depends on the source (OTA pricing, commission, reports) is
  # derived from `booking.source` on read, so the column is all that changes.
  # The exceptions are records that were built *for* the old source: a channel
  # manager owns its bookings' source, and settlements, OTA billing parties and
  # issued e-invoices were all made against it. Those bookings are refused.
  class ChangeSource
    Result = Data.define(:success?, :booking, :errors)

    BLOCKING_E_INVOICE_STATUSES = %w[pending submitted valid].freeze

    def self.call(booking:, actor:, source:)
      new(booking:, actor:, source:).call
    end

    # Why the source cannot be changed, or nil when it can. Public so the
    # workspace can hide the action instead of offering one that will fail.
    def self.locked_reason(booking)
      if booking.channel_manager_reference.present?
        "This booking came from the channel manager, which owns its source."
      elsif booking.channel_settlements.exists?
        "This booking has channel settlements recorded against its source."
      elsif booking.booking_billing_parties.active.where(party_kind: "ota").exists?
        "This booking has an OTA billing party for its current source."
      elsif booking.e_invoice_submissions.guest_facing.where(status: BLOCKING_E_INVOICE_STATUSES).exists?
        "An e-invoice has already been issued for this booking."
      end
    end

    def initialize(booking:, actor:, source:)
      @booking = booking
      @actor = actor
      @source = BookingSource.normalize(source)
    end

    def call
      return failure("Choose a booking source.") if @source.blank?
      return failure("#{@source.tr('_', ' ').titleize} is not an available booking source.") unless selectable_source?
      return failure("The booking is already recorded as #{source_label(@source)}.") if @source == @booking.source

      locked = self.class.locked_reason(@booking)
      return failure(locked) if locked

      previous_source = @booking.source
      Booking.transaction do
        @booking.update!(source: @source)
        Bookings::RecordAuditLog.call!(
          auditable: @booking,
          user: @actor,
          action_type: "source_changed",
          old_value: { "source" => previous_source },
          new_value: { "source" => @source }
        )
      end
      Result.new(true, @booking, [])
    rescue ActiveRecord::RecordInvalid => e
      failure(*e.record.errors.full_messages)
    end

    private

    # Only sources staff could have picked when creating the booking: system
    # sources are reserved for integrations and are hidden from dropdowns.
    def selectable_source?
      record = BookingSource.registry[@source]
      record.present? && record.active? && record.kind != "system"
    end

    def source_label(key)
      BookingSource.find_by_source(key)&.label || key.to_s.tr("_", " ").titleize
    end

    def failure(*errors)
      Result.new(false, @booking, errors)
    end
  end
end
