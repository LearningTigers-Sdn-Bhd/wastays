# frozen_string_literal: true

require "ostruct"

module Bookings
  class FinalizeNoShow
    include Folios::NightlyChargeCalculation

    def self.call(booking:, user:, night_audit: nil, automatic: false)
      new(booking: booking, user: user, night_audit: night_audit, automatic: automatic).call
    end

    def initialize(booking:, user:, night_audit: nil, automatic: false)
      @booking = booking
      @user = user
      @night_audit = night_audit
      @automatic = automatic
    end

    def call
      Booking.transaction do
        @booking.with_lock do
          @booking.reload
          return success if @booking.status == "no_show"
          return failure("Only bookings pending no-show review can be marked as no-show.") unless @booking.status == "review_no_show"

          @business_date = @booking.no_show_review_business_date
          return failure("No-show review business date is missing.") unless @business_date

          folio = Folios::InitializeForBooking.call(
            booking: @booking,
            user: @user,
            options: { posting_source: "no_show" },
            lock: false
          )
          post_no_show_charges(folio)
          folio.folio_forecasted_charges.supersede_all!
          @booking.transition_status_to!("no_show", event: @automatic ? "auto_mark_no_show" : "mark_no_show")
          Bookings::InventoryManager.new(@booking).release_by_dates(@business_date + 1.day, @booking.check_out.to_date)
          release_assigned_rooms_to_ready
          Bookings::RecordAuditLog.call!(
            auditable: @booking,
            user: @user,
            action_type: "no_show",
            source: @night_audit.present? ? "night_audit" : (@user.present? ? "staff" : "system"),
            old_value: { "status" => "review_no_show" },
            new_value: { "status" => "no_show" },
            metadata: audit_metadata
          )
        end
      end
      success
    rescue StandardError => e
      failure(e.message)
    end

    private

    def post_no_show_charges(folio)
      @booking.booking_rooms.each do |booking_room|
        amount = nightly_room_amount(booking_room, @business_date)
        next if amount.zero?

        insert_charge!(
          folio: folio,
          amount: amount,
          category: "no_show_charge",
          description: "No-show room charge - #{@business_date}",
          metadata: no_show_metadata("no_show_charge", booking_room.id).merge(
            rate_source: nightly_rate_snapshot_for(booking_room, @business_date).present? ? "nightly_rate_snapshot" : "legacy_subtotal_average",
            nightly_rate_snapshot: nightly_rate_snapshot_for(booking_room, @business_date)
          )
        )
      end

      tax_postings_for(@booking, @business_date).each_with_index do |tax_line, index|
        amount = tax_line_amount(tax_line)
        next if amount.zero?

        insert_charge!(
          folio: folio,
          amount: amount,
          category: "tax",
          description: "No-show tax charge: #{tax_line_name(tax_line)} - #{@business_date}",
          metadata: no_show_metadata("tax", tax_line_identity(tax_line, index)).merge(tax_line: tax_line)
        )
      end
    end

    def insert_charge!(folio:, amount:, category:, description:, metadata:)
      return if already_posted?(folio, metadata[:no_show_charge_key])

      options = { metadata: metadata, posting_source: "no_show" }
      if @booking.hotel.date_closed?(@business_date) || @business_date < @booking.hotel.business_date_for
        options.merge!(
          override_night_audit: true,
          system_posting: true,
          correction_reason: "finalize_no_show_review",
          correction_note: "Finalized no-show review for original arrival business date #{@business_date}."
        )
      end

      result = Folios::InsertTransaction.new(
        booking_folio: folio,
        amount: amount,
        transaction_type: :charge,
        category: category,
        user: @user,
        description: description,
        posting_date: @business_date,
        options: options
      ).call
      return if result.success? || already_posted?(folio, metadata[:no_show_charge_key])

      raise "Failed to post no-show folio charge: #{result.error}"
    end

    def already_posted?(folio, no_show_charge_key)
      folio.folio_transactions.charge.where(voided_by_transaction_id: nil)
        .where("metadata->>'no_show_charge_key' = ?", no_show_charge_key).exists?
    end

    def no_show_metadata(charge_kind, identity)
      {
        posting_source: "no_show",
        night_audit_id: @night_audit&.id,
        stay_date: @business_date.iso8601,
        booking_id: @booking.id,
        charge_kind: charge_kind,
        no_show_charge_key: Folios::ChargePostingKeys.no_show_charge_key(
          booking: @booking,
          date: @business_date,
          charge_kind: charge_kind,
          identity: identity
        )
      }.compact
    end

    def release_assigned_rooms_to_ready
      result = Bookings::ReleaseAssignedRooms.call(
        booking: @booking,
        user: @user,
        event_type: "no_show_released",
        reason: "Booking finalized as no-show",
        metadata: audit_metadata.merge("source" => "bookings_finalize_no_show", "booking_id" => @booking.id)
      )
      raise result.error unless result.success?
    end

    def audit_metadata
      {
        "night_audit_id" => @night_audit&.id,
        "business_date" => @business_date.iso8601,
        "automatic" => @automatic
      }.compact
    end

    def success
      OpenStruct.new(success?: true, booking: @booking)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
