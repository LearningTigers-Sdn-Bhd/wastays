# frozen_string_literal: true

require "ostruct"

module Bookings
  class ProcessNoShows
    def self.call(night_audit:, user:)
      new(night_audit: night_audit, user: user).call
    end

    def initialize(night_audit:, user:)
      @night_audit = night_audit
      @hotel = night_audit.hotel
      @business_date = night_audit.business_date.to_date
      @user = user
      @processed = []
    end

    def call
      no_show_candidates.find_each do |booking|
        process_booking(booking)
      end

      OpenStruct.new(success?: true, processed_count: @processed.count, bookings: @processed)
    end

    private

    def no_show_candidates
      @hotel.bookings.confirmed
        .includes(:booking_rooms, :payment_transactions, booking_folio: :folio_transactions)
        .where(check_in: @business_date)
    end

    def process_booking(booking)
      Booking.transaction do
        booking.with_lock do
          booking.reload
          next unless booking.status == "confirmed" && booking.check_in == @business_date

          folio = Folios::InitializeForBooking.call(booking: booking, user: @user, lock: false)
          post_no_show_charges(booking, folio)
          booking.update!(status: "no_show")
          Bookings::InventoryManager.new(booking).release_by_dates(@business_date + 1.day, booking.check_out)
          Bookings::RecordAuditLog.call(
            auditable: booking,
            user: @user,
            action_type: "no_show",
            metadata: { night_audit_id: @night_audit.id, business_date: @business_date.iso8601 }
          )
          @processed << booking
        end
      end
    end

    def post_no_show_charges(booking, folio)
      booking.booking_rooms.each do |booking_room|
        amount = nightly_amount(booking_room.subtotal, booking)
        next if amount.zero?

        insert_charge!(
          folio: folio,
          amount: amount,
          category: "accommodation",
          description: "No-show room penalty - #{@business_date}",
          metadata: no_show_metadata(booking, "accommodation", booking_room.id)
        )
      end

      tax_lines_for(booking).each_with_index do |tax_line, index|
        amount = nightly_amount(tax_line_amount(tax_line), booking)
        next if amount.zero?

        insert_charge!(
          folio: folio,
          amount: amount,
          category: "tax",
          description: "No-show tax penalty: #{tax_line_name(tax_line)} - #{@business_date}",
          metadata: no_show_metadata(booking, "tax", tax_line_identity(tax_line, index)).merge(tax_line: tax_line)
        )
      end
    end

    def insert_charge!(folio:, amount:, category:, description:, metadata:)
      return if already_posted?(folio, metadata[:no_show_charge_key])

      result = Folios::InsertTransaction.new(
        booking_folio: folio,
        amount: amount,
        transaction_type: :charge,
        category: category,
        user: @user,
        description: description,
        posting_date: @business_date,
        options: { metadata: metadata }
      ).call

      return if result.success? || already_posted?(folio, metadata[:no_show_charge_key])

      raise "Failed to post no-show folio charge: #{result.error}"
    end

    def already_posted?(folio, no_show_charge_key)
      folio.folio_transactions.charge.where("metadata->>'no_show_charge_key' = ?", no_show_charge_key).exists?
    end

    def no_show_metadata(booking, charge_kind, identity)
      {
        posting_source: "no_show",
        night_audit_id: @night_audit.id,
        stay_date: @business_date.iso8601,
        booking_id: booking.id,
        charge_kind: charge_kind,
        no_show_charge_key: [ booking.id, @business_date.iso8601, "no_show_penalty", charge_kind, identity ].join(":")
      }
    end

    def nightly_amount(total_amount, booking)
      nights = (booking.check_out.to_date - booking.check_in.to_date).to_i
      return 0.to_d unless nights.positive?

      (total_amount.to_d / nights).round(2)
    end

    def tax_lines_for(booking)
      tax_lines = Array(booking.tax_lines)
      return tax_lines if tax_lines.any?
      return [] unless booking.tourism_tax_amount.to_d.positive?

      [ { "name" => "Tourism Tax", "amount" => booking.tourism_tax_amount, "type" => "tourism_tax" } ]
    end

    def tax_line_amount(tax_line)
      (tax_line["amount"].presence || tax_line[:amount]).to_d
    end

    def tax_line_name(tax_line)
      tax_line["name"].presence || tax_line[:name].presence || "Tax"
    end

    def tax_line_identity(tax_line, index)
      identity = tax_line["type"].presence || tax_line[:type].presence || tax_line_name(tax_line).parameterize.presence || "tax"
      "#{identity}:#{index}"
    end
  end
end
