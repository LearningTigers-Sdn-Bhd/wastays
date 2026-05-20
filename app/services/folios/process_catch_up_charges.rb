# frozen_string_literal: true

module Folios
  class ProcessCatchUpCharges
    include NightlyChargeCalculation

    def self.call(booking:, user:, is_reinstate: false)
      new(booking: booking, user: user, is_reinstate: is_reinstate).call
    end

    def initialize(booking:, user:, is_reinstate: false)
      @booking = booking
      @folio = booking.booking_folio
      @user = user
      @hotel = booking.hotel
      @is_reinstate = is_reinstate
    end

    def call
      return unless @folio

      @folio.with_lock do
        reverse_no_show_penalties
        post_missing_nightly_charges
      end
    end

    private

    def reverse_no_show_penalties
      @folio.folio_transactions.where("metadata->>'posting_source' = ?", "no_show").find_each do |penalty|
        # Avoid double-reversing if already corrected
        next if already_corrected?(penalty)

        description = @is_reinstate ? "Void Penalty: Reinstated Reservation" : "Auto-reversal of no-show penalty: #{penalty.description}"

        result = Folios::InsertTransaction.new(
          booking_folio: @folio,
          amount: -penalty.amount, # Negative adjustment to zero it out
          transaction_type: :adjustment,
          category: :correction,
          user: @user,
          description: description,
          posting_date: penalty.posting_date,
          options: {
            override_night_audit: true,
            metadata: {
              source: "late_checkin_correction",
              reversed_transaction_id: penalty.id,
              is_reinstate: @is_reinstate
            }
          }
        ).call

        raise "Failed to reverse no-show penalty: #{result.error}" unless result.success?
      end
    end

    def post_missing_nightly_charges
      # We need to check every date from booking.check_in up to (but not including) the current open business date.
      # Charges are posted for dates that are already closed by Night Audit.
      dates_to_check.each do |date|
        post_accommodation_catch_up(date)
        post_tax_catch_up(date)
      end
    end

    def dates_to_check
      final_stay_date = @booking.check_out.to_date - 1.day
      return [] if final_stay_date < @booking.check_in.to_date

      @hotel.night_audits.where(status: "completed")
        .where(business_date: @booking.check_in.to_date..final_stay_date)
        .order(:business_date)
        .pluck(:business_date)
    end

    def post_accommodation_catch_up(date)
      @booking.booking_rooms.each do |room|
        # Unique key to prevent double-posting if they check in, out, and in again (unlikely but safe)
        charge_key = [ "catch_up", @booking.id, date.iso8601, "accommodation", room.id ].join(":")
        next if already_posted?(charge_key)

        amount = nightly_room_amount(room, date)
        next if amount.zero?

        description = @is_reinstate ? "Reinstate Charge - #{date.strftime('%d %b %Y')}" : "Unexpected Check-in (Room Charge) - #{date.strftime('%d %b %Y')}"

        result = Folios::InsertTransaction.new(
          booking_folio: @folio,
          amount: amount,
          transaction_type: :charge,
          category: :accommodation,
          user: @user,
          description: description,
          posting_date: date,
          options: {
            override_night_audit: true,
            metadata: {
              posting_source: "catch_up",
              catch_up_key: charge_key,
              stay_date: date.iso8601,
              rate_source: nightly_rate_snapshot_for(room, date).present? ? "nightly_rate_snapshot" : "legacy_subtotal_average",
              nightly_rate_snapshot: nightly_rate_snapshot_for(room, date),
              is_reinstate: @is_reinstate
            }
          }
        ).call

        raise "Failed to post accommodation catch-up charge: #{result.error}" unless result.success?
      end
    end

    def post_tax_catch_up(date)
      tax_postings_for(@booking, date).each_with_index do |tax_line, index|
        tax_identity = tax_line_identity(tax_line, index)
        charge_key = [ "catch_up", @booking.id, date.iso8601, "tax", tax_identity ].join(":")
        next if already_posted?(charge_key)

        amount = tax_line_amount(tax_line)
        next if amount.zero?

        description = if @is_reinstate
          "Reinstate Tax: #{tax_line_name(tax_line)} - #{date.strftime('%d %b %Y')}"
        else
          "Unexpected Check-in Tax: #{tax_line_name(tax_line)} - #{date.strftime('%d %b %Y')}"
        end

        result = Folios::InsertTransaction.new(
          booking_folio: @folio,
          amount: amount,
          transaction_type: :charge,
          category: :tax,
          user: @user,
          description: description,
          posting_date: date,
          options: {
            override_night_audit: true,
            metadata: {
              posting_source: "catch_up",
              catch_up_key: charge_key,
              stay_date: date.iso8601,
              tax_line: tax_line,
              is_reinstate: @is_reinstate
            }
          }
        ).call

        raise "Failed to post tax catch-up charge: #{result.error}" unless result.success?
      end
    end

    def already_corrected?(penalty)
      @folio.folio_transactions.adjustment
        .where("metadata->>'reversed_transaction_id' = ?", penalty.id.to_s)
        .exists?
    end

    def already_posted?(charge_key)
      # Check both standard audit keys and catch-up keys to be safe
      @folio.folio_transactions.charge
        .where("metadata->>'catch_up_key' = ? OR metadata->>'nightly_charge_key' = ?", charge_key, charge_key.sub("catch_up:", ""))
        .exists?
    end
  end
end
