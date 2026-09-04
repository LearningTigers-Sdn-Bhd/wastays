# frozen_string_literal: true

module Reports
  module Bookings
    # Normalizes a booking into what a tourism tax voucher has to state.
    #
    # Tourism tax is charged per room per night, to foreign guests only, so the two facts
    # the document lives or dies on are the quantity it is charging for and the nationality
    # that made it chargeable. Both come from the booking's tax posting snapshot, which
    # holds one line per stay date carrying the rate, the rooms it applied to and the
    # amount — everything a charge row needs, without the renderer recomputing anything.
    class GenerateTourismTaxVoucherRecords
      ChargeRow = Data.define(:description, :quantity, :rate, :amount)

      PdfTheme = HotelPortal::Reports::Exports::PdfTheme
      # Set by Folios::Payments::RecordTourismTaxPayment on every tourism tax payment it
      # posts. Matched ahead of the posting source so a tax collected anywhere other than
      # check-in still finds its date.
      PAYMENT_METADATA_KEY = "tourism_tax"
      PAYMENT_SOURCE = Folios::Payments::RecordTourismTaxPayment::METADATA_SOURCE

      COLLECTED_NOTE = "This voucher is evidence that the guest has paid the tourism tax recorded above."
      PAYABLE_NOTE = "This voucher records the tourism tax payable for this stay. It is not evidence of payment."

      attr_reader :booking, :hotel

      def initialize(booking:, printed_by: nil)
        @booking = booking
        @hotel = booking.hotel
        @printed_by = printed_by
        @booking_rooms = booking.booking_rooms.includes(:room_type).to_a
      end

      def call = self

      def voucher_number = booking.formatted_tourism_tax_voucher_number

      def collected? = booking.tourism_tax_collected?

      def total = booking.tourism_tax_total

      def currency = tax_lines.first&.dig("currency").presence || booking.currency.presence || "MYR"

      def pdf_title = "Tourism Tax Voucher - #{voucher_number}"

      # The badge answers the question the holder has already asked: has this been paid.
      def status_badge
        collected? ? { label: "Collected", variant: :positive } : { label: "Payable", variant: :warning }
      end

      def hotel_identifier_line = Reports::HotelIdentifierLine.for_hotel(hotel)

      def closing_note = collected? ? COLLECTED_NOTE : PAYABLE_NOTE

      # Nationality leads the guest block: it is the reason this guest was charged a tax
      # most guests do not pay, and without it nothing on the document explains itself.
      def party_blocks
        address = PostalAddresses::Presenter.from_booking_guest(
          booking.booking_guests.find(&:primary?),
          fallback_booking: booking
        )

        [
          {
            heading: "Guest details",
            entries: [
              [ "Name", booking.guest_name ],
              [ "Nationality", booking.guest_country.presence || "Not recorded" ],
              [ "Address", address.display.presence || "Not provided" ]
            ]
          },
          {
            heading: "Stay details",
            entries: [
              [ "Booking", booking.formatted_reservation_number ],
              [ "Room", room_label ],
              { columns: [ [ "Arrival", PdfTheme.format_date(booking.check_in) ],
                           [ "Departure", PdfTheme.format_date(booking.check_out) ] ] },
              [ "Nights", booking.duration_in_nights.to_s ]
            ]
          },
          {
            heading: "Collection details",
            entries: [
              [ "Status", collected? ? "Collected" : "Payable" ],
              [ "Collected on", collected_on_label ],
              [ "Folio", booking.folio_account_reference_display.presence || "Not yet assigned" ],
              [ "Issued by", @printed_by&.name.presence || "System" ]
            ]
          }
        ]
      end

      # One row when the rate held for the whole stay, which is the ordinary case, and a
      # row per night when it did not — a rate that changed mid-stay cannot be stated as a
      # single unit price without inventing one.
      def charge_rows
        return [ fallback_row ] if tax_lines.empty?
        return per_night_rows unless uniform_rate?

        [ ChargeRow.new(description: "Tourism tax", quantity: room_nights.to_s, rate: money(unit_rate), amount: money(total)) ]
      end

      def total_row = [ "Total", nil, nil, money(total) ]

      def money(value) = PdfTheme.money(value)

      # Room-nights, summed from what was actually posted rather than from nights times
      # rooms: a room added or dropped mid-stay is in the snapshot and not in the
      # multiplication.
      def room_nights
        tax_lines.sum { |line| line["basis_amount"].to_d }.to_i
      end

      private

      def per_night_rows
        tax_lines.sort_by { |line| line["stay_date"].to_s }.map do |line|
          ChargeRow.new(
            description: "Tourism tax - #{PdfTheme.format_date(stay_date(line))}",
            quantity: line["basis_amount"].to_d.to_i.to_s,
            rate: money(line["rate"]),
            amount: money(line["amount"])
          )
        end
      end

      # A booking posted before the snapshot existed knows its total and nothing else.
      # Quantity and rate are left blank rather than back-solved: dividing the total by the
      # rooms is what printed a per-night rate of thirty ringgit on a three-night stay.
      def fallback_row
        ChargeRow.new(description: "Tourism tax", quantity: nil, rate: nil, amount: money(total))
      end

      def uniform_rate? = tax_lines.map { |line| line["rate"].to_d }.uniq.one?

      def unit_rate = tax_lines.first["rate"].to_d

      def stay_date(line) = line["stay_date"].presence && Date.parse(line["stay_date"])

      def tax_lines
        @tax_lines ||= booking.tax_posting_snapshot.to_h.values.flatten
          .map(&:to_h)
          .select { |line| Booking.tourism_tax_line?(line) && line["rate"].present? && line["basis_amount"].present? }
      end

      def room_label
        return "Unassigned" if @booking_rooms.empty?

        @booking_rooms.map do |room|
          name = room.room_type_snapshot.to_h["name"].presence || room.room_type&.name
          [ name, room.room_number.presence || "Unassigned" ].compact_blank.join(" - ")
        end.join("\n")
      end

      def collected_on_label
        return "Not yet collected" unless collected?

        PdfTheme.format_date(collection_date) || "Date not recorded"
      end

      # The old voucher matched only the check-in posting source, so a tax taken at
      # checkout printed "pending collection" beside a badge that said collected.
      def collection_date
        folio = booking.booking_folio
        return if folio.blank?

        @collection_date ||= folio.folio_transactions.payment
          .where("metadata->>? = ? OR metadata->>? = ?",
            PAYMENT_METADATA_KEY, "true", "source", PAYMENT_SOURCE)
          .order(:posting_date)
          .first&.posting_date
      end
    end
  end
end
