# frozen_string_literal: true

require "ostruct"

module Bookings
  class FinalizeNoShow
    include Folios::Charges::NightlyChargeCalculation

    def self.call(booking:, user:, night_audit: nil, automatic: false, reason: nil)
      new(booking: booking, user: user, night_audit: night_audit, automatic: automatic, reason: reason).call
    end

    def initialize(booking:, user:, night_audit: nil, automatic: false, reason: nil)
      @booking = booking
      @user = user
      @night_audit = night_audit
      @automatic = automatic
      @reason = reason.to_s.strip.presence
    end

    def call
      NightAudits::OperationalChangeGuard.call!(
        hotel: @booking.hotel,
        action: :finalize_no_show,
        night_audit: @night_audit
      )

      Booking.transaction do
        @booking.with_lock do
          @booking.reload
          return success if @booking.status == "no_show"
          return failure("Only bookings with a detected no-show can be marked as no-show.") unless @booking.status == "no_show_detected"

          @business_date = @booking.no_show_detected_business_date
          return failure("No-show detection business date is missing.") unless @business_date

          folio = Folios::Lifecycle::InitializeForBooking.call(
            booking: @booking,
            user: @user,
            options: { posting_source: "no_show", night_audit: @night_audit },
            lock: false
          )
          post_no_show_charges(folio)
          @closure_result = Folios::Lifecycle::CloseNoShowFolios.call(
            booking: @booking,
            user: @user,
            business_date: @business_date,
            night_audit: @night_audit
          )
          raise @closure_result.error unless @closure_result.success?
          @booking.transition_status_to!("no_show", event: @automatic ? "auto_mark_no_show" : "mark_no_show")
          Bookings::InventoryManager.new(@booking).release_by_dates(@business_date + 1.day, @booking.check_out.to_date)
          release_assigned_rooms_to_ready
          Bookings::RecordAuditLog.call!(
            auditable: @booking,
            user: @user,
            action_type: "no_show",
            source: @night_audit.present? ? "night_audit" : (@user.present? ? "staff" : "system"),
            old_value: { "status" => "no_show_detected" },
            new_value: { "status" => "no_show" },
            reason: @reason,
            metadata: audit_metadata
          )
        end
      end
      success
    rescue StandardError => e
      failure(e.message)
    end

    private

    # Billed nights come from the hotel's no-show policy. Each night is charged
    # from that night's rate snapshot together with that night's snapshot tax
    # lines, so the tax always describes exactly the nights billed — which is why
    # the policy is constrained (in the database) to whole nights.
    def post_no_show_charges(folio)
      return if no_show_policy.present? && !no_show_policy.active?

      billed_dates.each { |date| post_no_show_night(folio, date) }
    end

    def post_no_show_night(folio, date)
      @booking.booking_rooms.each do |booking_room|
        amount = nightly_room_amount(booking_room, date)
        next if amount.zero?

        insert_charge!(
          folio: folio,
          amount: amount,
          category: "no_show_charge",
          description: "No-show room charge - #{date}",
          metadata: no_show_metadata("no_show_charge", booking_room.id, date).merge(
            rate_source: nightly_rate_snapshot_for(booking_room, date).present? ? "nightly_rate_snapshot" : "legacy_subtotal_average",
            nightly_rate_snapshot: nightly_rate_snapshot_for(booking_room, date)
          )
        )
      end

      tax_postings_for(@booking, date).reject { |tax_line| Booking.tourism_tax_line?(tax_line) }.each_with_index do |tax_line, index|
        amount = tax_line_amount(tax_line)
        next if amount.zero?

        insert_charge!(
          folio: folio,
          amount: amount,
          category: "tax",
          description: "No-show tax charge: #{tax_line_name(tax_line)} - #{date}",
          metadata: no_show_metadata("tax", tax_line_identity(tax_line, index), date).merge(tax_line: tax_line)
        )
      end
    end

    # The detection date first, then whatever nights of the stay follow it, capped
    # at the number the policy bills. Every posting still lands on the detection
    # business date — only the night being billed changes.
    def billed_dates
      nights = no_show_policy&.whole_nights.to_i
      nights = 1 if nights < 1

      following = booking_stay_dates(@booking).select { |date| date > @business_date }
      ([ @business_date ] + following).first(nights)
    end

    def no_show_policy
      return @no_show_policy if defined?(@no_show_policy)

      ReservationPolicies::EnsureDefaults.call(@booking.hotel)
      @no_show_policy = @booking.hotel.hotel_reservation_policies.find_by(policy_type: "no_show")
    end

    def insert_charge!(folio:, amount:, category:, description:, metadata:)
      return if already_posted?(folio, metadata[:no_show_charge_key])

      options = { metadata: metadata, posting_source: "no_show", night_audit: @night_audit }
      if @booking.hotel.date_closed?(@business_date) || @business_date < @booking.hotel.current_business_date
        options.merge!(
          override_night_audit: true,
          system_posting: true,
          correction_reason: "finalize_no_show_detection",
          correction_note: "Finalized no-show detection for original arrival business date #{@business_date}."
        )
      end

      result = Folios::Transactions::InsertTransaction.new(
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

    def no_show_metadata(charge_kind, identity, stay_date = @business_date)
      {
        posting_source: "no_show",
        night_audit_id: @night_audit&.id,
        stay_date: stay_date.iso8601,
        booking_id: @booking.id,
        charge_kind: charge_kind,
        no_show_charge_key: Folios::Charges::ChargePostingKeys.no_show_charge_key(
          booking: @booking,
          date: stay_date,
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
        reason: @reason.presence || "Booking finalized as no-show",
        metadata: audit_metadata.merge("source" => "bookings_finalize_no_show", "booking_id" => @booking.id)
      )
      raise result.error unless result.success?
    end

    def audit_metadata
      {
        "night_audit_id" => @night_audit&.id,
        "business_date" => @business_date.iso8601,
        "automatic" => @automatic,
        "reason" => @reason
      }.compact
    end

    def success
      OpenStruct.new(
        success?: true,
        booking: @booking,
        closed_folios: @closure_result&.closed_folios || [],
        skipped_folios: @closure_result&.skipped_folios || []
      )
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error, closed_folios: [], skipped_folios: [])
    end
  end
end
