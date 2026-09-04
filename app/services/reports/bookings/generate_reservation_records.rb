# frozen_string_literal: true

module Reports
  module Bookings
    # Normalizes a live reservation into the same display vocabulary an invoice uses.
    #
    # The pair to read this against is GenerateFolioRecords: folio records are what was
    # posted, these are what was booked. Reservation documents are produced before folio
    # charges necessarily exist, so the charge rows here come from the booking-time nightly
    # and tax snapshots rather than from current rates or subsequently posted transactions.
    # The two will disagree once a stay is under way, and that is the point of having both.
    #
    # Serves a single booking or a whole group. A group organiser settles one position, so
    # the group form aggregates its children rather than reporting each room separately.
    class GenerateReservationRecords
      ChargeRow = Data.define(:date, :code, :description, :secondary_description, :quantity, :net, :charges, :gross)
      PaymentRow = Data.define(:date, :code, :description, :secondary_description, :amount)
      SummaryRow = Data.define(:label, :amount, :variant)

      PdfTheme = HotelPortal::Reports::Exports::PdfTheme
      PAYMENT_REFERENCE_KEYS = Reports::Bookings::GenerateFolioRecords::PAYMENT_REFERENCE_KEYS
      PAYMENT_SOURCE_LABELS = Reports::Bookings::GenerateFolioRecords::PAYMENT_SOURCE_LABELS
      PAYMENT_FALLBACK_CODES = Reports::Bookings::GenerateFolioRecords::FALLBACK_CODES

      # What one booking contributes to a set of charges. A group's rooms may run different
      # dates from one another, so the nightly breakdown has to be decided per booking; a
      # group that fell back to stay totals because one child lacked a snapshot would lose
      # the breakdown for every other child too.
      class StayCharges
        # `label` names the room this set belongs to on a document covering more than one
        # of them. A group summary listing twenty rows of "Deluxe" tells the organiser
        # nothing about which room each line is for.
        def initialize(booking, label: nil)
          @booking = booking
          @label = label
          @booking_rooms = booking.booking_rooms.includes(:room_type).to_a
        end

        attr_reader :booking

        def charge_rows
          @charge_rows ||= complete_nightly_breakdown? ? nightly_charge_rows : aggregate_charge_rows
        end

        def accommodation_total = @booking_rooms.sum(0.to_d, &:subtotal)

        def non_tourism_tax_lines
          @non_tourism_tax_lines ||= Array(@booking.tax_lines).map { |line| line.to_h.stringify_keys }
            .reject { |line| tourism_tax_line?(line) }
        end

        def nights = stay_dates.size

        private

        def qualify(text) = @label.present? ? "#{@label} | #{text}" : text

        def stay_dates
          @stay_dates ||= (@booking.check_in.to_date...@booking.check_out.to_date).to_a
        end

        def nights_label = "#{nights} #{nights == 1 ? 'night' : 'nights'}"

        def complete_nightly_breakdown?
          return false if @booking_rooms.empty? || stay_dates.empty?
          return false unless @booking_rooms.all? { |room| stay_dates.all? { |date| nightly_price(room, date).present? } }
          return false unless nightly_room_total == accommodation_total
          return false unless dated_non_tourism_tax_total == non_tourism_tax_total

          nightly_room_total + dated_non_tourism_tax_total == @booking.total_amount.to_d
        end

        def nightly_charge_rows
          stay_dates.flat_map.with_index do |date, index|
            room_rows = @booking_rooms.map do |room|
              amount = nightly_price(room, date).to_d
              ChargeRow.new(
                date: PdfTheme.format_date(date),
                code: nightly_snapshot(room, date)["transaction_code_code"].presence || "RM-ROOM",
                description: room_name(room),
                secondary_description: qualify("Night #{index + 1} of #{nights}"),
                quantity: "1",
                net: amount,
                charges: nil,
                gross: amount
              )
            end
            room_rows + dated_tax_rows(date)
          end
        end

        def dated_tax_rows(date)
          dated_tax_postings(date).filter_map do |line|
            next if tourism_tax_line?(line) || line["amount"].to_d.zero?

            amount = line["amount"].to_d
            ChargeRow.new(
              date: PdfTheme.format_date(date),
              code: line["transaction_code_code"].presence || "TAX",
              description: line["name"].presence || "Tax / charge",
              secondary_description: qualify("On accommodation"),
              quantity: "-",
              net: nil,
              charges: amount,
              gross: amount
            )
          end
        end

        def aggregate_charge_rows
          room_rows = @booking_rooms.map do |room|
            amount = room.subtotal.to_d
            ChargeRow.new(
              date: PdfTheme.format_date(@booking.check_in.to_date),
              code: "RM-ROOM",
              description: room_name(room),
              secondary_description: qualify("#{nights_label} | Nightly breakdown unavailable"),
              quantity: "1",
              net: amount,
              charges: nil,
              gross: amount
            )
          end
          room_rows + non_tourism_tax_lines.filter_map do |line|
            next if line["amount"].to_d.zero?

            amount = line["amount"].to_d
            ChargeRow.new(
              date: PdfTheme.format_date(@booking.check_in.to_date),
              code: line["transaction_code_code"].presence || "TAX",
              description: line["name"].presence || "Tax / charge",
              secondary_description: qualify("Stay total"),
              quantity: "-",
              net: nil,
              charges: amount,
              gross: amount
            )
          end
        end

        def nightly_snapshot(room, date)
          value = room.nightly_rate_snapshot.to_h[date.iso8601]
          value.respond_to?(:to_h) ? value.to_h.stringify_keys : { "price" => value }
        end

        def nightly_price(room, date) = nightly_snapshot(room, date)["price"]

        def nightly_room_total
          @booking_rooms.sum(0.to_d) do |room|
            stay_dates.sum(0.to_d) { |date| nightly_price(room, date).to_d }
          end
        end

        def room_name(room) = room.room_type_snapshot.to_h["name"].presence || room.room_type.name

        def dated_tax_postings(date)
          Array(@booking.tax_posting_snapshot.to_h[date.iso8601]).map { |line| line.to_h.stringify_keys }
        end

        def dated_non_tourism_tax_total
          stay_dates.sum(0.to_d) do |date|
            dated_tax_postings(date).reject { |line| tourism_tax_line?(line) }.sum(0.to_d) { |line| line["amount"].to_d }
          end
        end

        def non_tourism_tax_total = non_tourism_tax_lines.sum(0.to_d) { |line| line["amount"].to_d }

        def tourism_tax_line?(line) = Booking.tourism_tax_line?(line)
      end

      attr_reader :booking, :group_booking, :hotel

      def initialize(booking: nil, group_booking: nil)
        unless booking.present? ^ group_booking.present?
          raise ArgumentError, "supply exactly one of booking: or group_booking:"
        end

        @group_booking = group_booking
        @bookings = group_booking ? group_booking.bookings.includes(booking_rooms: :room_type).to_a : [ booking ]
        # Policy, cancellation terms and check-in times are properties of the stay rather
        # than of the group, so the group borrows them from its first room.
        @booking = booking || @bookings.first
        @hotel = (booking || group_booking).hotel
        @policy = @booking&.hotel_snapshot.to_h["property_policy"].to_h
        @stays = @bookings.map { |record| StayCharges.new(record, label: group? ? record.confirmation_token : nil) }
      end

      def call = self

      def group? = @group_booking.present?

      def subject = @group_booking || @booking

      def reservation_number = subject.formatted_reservation_number

      def confirmation_token = subject.confirmation_token

      def currency = @booking&.currency

      def status_badge
        { label: status.to_s.humanize, variant: status_badge_variant }
      end

      def party_blocks
        group? ? group_party_blocks : booking_party_blocks
      end

      def charge_rows = @stays.flat_map(&:charge_rows)

      def payment_rows
        @payment_rows ||= folio_payment_rows + group_deposit_rows
      end

      def total_due = @bookings.sum(0.to_d) { |record| record.total_amount.to_d }

      def total_payments = payment_rows.sum(0.to_d, &:amount)

      def balance = total_due - total_payments

      def balance_label
        return "Balance due" if balance.positive?
        return "Credit balance" if balance.negative?

        "Booking balance settled"
      end

      def summary_rows
        rows = []
        rows << SummaryRow.new(label: "Accommodation", amount: accommodation_total, variant: nil) unless accommodation_total.zero?
        non_tourism_tax_lines.group_by { |line| line["name"].presence || "Tax / charge" }.each do |name, lines|
          rows << SummaryRow.new(label: name, amount: lines.sum(0.to_d) { |line| line["amount"].to_d }, variant: nil)
        end
        rows << SummaryRow.new(label: "", amount: nil, variant: :spacer)
        rows << SummaryRow.new(
          label: balance_label,
          amount: balance.abs,
          variant: balance.positive? ? :alert : :subtotal
        )
        rows
      end

      def tourism_tax_disclosure
        amount = tourism_tax_total
        return if amount.zero?

        if tourism_tax_collected?
          "Excluded from booking total: Tourism tax of #{currency} #{money(amount)} was collected separately. " \
            "See the official tourism tax voucher."
        else
          "Excluded from booking total: Tourism tax of #{currency} #{money(amount)} is payable at the property. " \
            "A separate tourism tax voucher will be provided."
        end
      end

      # A group's requests belong to the rooms that made them, and each room's own voucher
      # carries them, so the group form states none of its own.
      def special_requests = group? ? nil : booking.special_requests

      def cancellation
        return @cancellation if defined?(@cancellation)

        @cancellation = @booking && Cancellations::PolicySummary.for_record(
          @booking,
          legacy_text: @policy["cancellation_policy"]
        )
      end

      def money(value) = PdfTheme.money(value)

      private

      def status = group? ? group_booking.projected_status : booking.status

      def status_badge_variant
        case status.to_s
        when "confirmed", "checked_in", "completed", "active" then :positive
        when "cancelled", "voided", "no_show" then :danger
        when "pending", "draft", "no_show_detected", "due_out_detected", "checkout_required", "overbooked" then :warning
        else :neutral
        end
      end

      def accommodation_total = @stays.sum(0.to_d, &:accommodation_total)

      def non_tourism_tax_lines = @stays.flat_map(&:non_tourism_tax_lines)

      def tourism_tax_total = @bookings.sum(0.to_d) { |record| record.tourism_tax_total.to_d }

      def tourism_tax_collected? = @bookings.any?(&:tourism_tax_collected?)

      def booking_party_blocks
        address = PostalAddresses::Presenter.from_booking_guest(
          booking.booking_guests.find(&:primary?),
          fallback_booking: booking
        )

        [
          {
            heading: "Guest details",
            entries: [
              [ "Guest", booking.guest_name ],
              [ "Address", address.display.presence || "Not provided" ],
              [ "Nationality", booking.guest_country ]
            ]
          },
          {
            heading: "Contact details",
            entries: [
              [ "Email", booking.guest_email ],
              [ "Phone", booking.guest_phone ]
            ]
          },
          {
            heading: "Stay details",
            entries: [
              [ "Booked at", PdfTheme.format_time(booking.created_at, hotel.hotel_time_zone) ],
              [ "Arrival", stay_datetime(booking.check_in, @policy["check_in_time"]) ],
              [ "Departure", stay_datetime(booking.check_out, @policy["check_out_time"]) ],
              { columns: [ [ "Duration", nights_label ], [ "Guests", guests_label ] ] }
            ]
          }
        ]
      end

      # A group is booked by an organiser against a block of rooms, so the party it names is
      # the organiser and the stay it describes is the envelope its rooms sit inside.
      def group_party_blocks
        organizer = group_booking.organizer_guest
        [
          {
            heading: "Group details",
            entries: [
              [ "Group", group_booking.name ],
              [ "Organiser", organizer&.name.presence || @booking&.guest_name ],
              [ "Rooms", rooms_label ]
            ]
          },
          {
            heading: "Contact details",
            entries: [
              [ "Email", organizer&.email.presence || @booking&.guest_email ],
              [ "Phone", organizer&.phone.presence || @booking&.guest_phone ]
            ]
          },
          {
            heading: "Stay details",
            entries: [
              [ "Booked at", PdfTheme.format_time(group_booking.created_at, hotel.hotel_time_zone) ],
              [ "Arrival", stay_datetime(earliest_arrival, @policy["check_in_time"]) ],
              [ "Departure", stay_datetime(latest_departure, @policy["check_out_time"]) ],
              { columns: [ [ "Duration", nights_label ], [ "Guests", guests_label ] ] }
            ]
          }
        ]
      end

      def earliest_arrival = @bookings.filter_map(&:check_in).min

      def latest_departure = @bookings.filter_map(&:check_out).max

      def rooms_label
        count = @bookings.sum { |record| record.booking_rooms.size }
        "#{count} #{count == 1 ? 'room' : 'rooms'}"
      end

      def nights
        return @stays.first&.nights.to_i unless group?
        return 0 if earliest_arrival.blank? || latest_departure.blank?

        (latest_departure.to_date - earliest_arrival.to_date).to_i
      end

      def nights_label = "#{nights} #{nights == 1 ? 'night' : 'nights'}"

      def guests_label
        adults = @bookings.sum { |record| record.adults.to_i }
        children = @bookings.sum { |record| record.children.to_i }
        label = "#{adults} #{adults == 1 ? 'adult' : 'adults'}"
        return label unless children.positive?

        "#{label}, #{children} #{children == 1 ? 'child' : 'children'}"
      end

      def stay_datetime(value, policy_time)
        return if value.blank?

        timestamp = if policy_time.present?
          date = ::Bookings::ScheduledStay.local_date(hotel: hotel, value: value)
          hotel.hotel_time_zone.parse("#{date.iso8601} #{policy_time}")
        else
          value
        end
        PdfTheme.format_time(timestamp, hotel.hotel_time_zone)
      rescue ArgumentError
        PdfTheme.format_time(value, hotel.hotel_time_zone)
      end

      def folio_payment_rows
        active_payments.map do |payment|
          PaymentRow.new(
            date: PdfTheme.format_date(payment.posting_date),
            code: payment_code(payment),
            description: payment_description(payment),
            secondary_description: payment_reference(payment),
            amount: payment.amount.to_d
          )
        end
      end

      # A deposit taken against the group itself belongs to no child booking, so nothing in
      # the folio scope above can see it. Only the portion still held is reported here: once
      # a deposit is applied it posts to a child's folio and is already counted.
      def group_deposit_rows
        return [] unless group?

        Deposit.where(hotel_id: hotel.id, group_booking_id: group_booking.id)
          .includes(:deposit_movements)
          .order(:received_at, :id)
          .filter_map do |deposit|
            available = deposit.available_amount.to_d
            next unless available.positive?

            PaymentRow.new(
              date: PdfTheme.format_date(deposit.received_at),
              code: "DEP-GRP",
              description: "Deposit - #{deposit.payment_method.to_s.humanize}",
              secondary_description: "Held against the group",
              amount: available
            )
          end
      end

      def active_payments
        @active_payments ||= FolioTransaction.joins(:booking_folio)
          .where(booking_folios: { booking_id: @bookings.map(&:id) })
          .payments
          .includes(:transaction_code)
          .order(:posting_date, :created_at, :id)
          .to_a
          .reject { |payment| payment.voided_by_transaction_id.present? || payment.reversal_of_transaction_id.present? }
      end

      def payment_code(payment)
        return payment.posted_transaction_code if payment.posted_transaction_code.present?

        case payment.metadata.to_h["payment_source"].to_s
        when "cash" then "PAY-CASH"
        when "bank" then "PAY-BANK"
        when "card" then "PAY-CARD"
        when "gateway" then "PAY-GW"
        when "ota" then "PAY-OTA"
        else PAYMENT_FALLBACK_CODES.dig(payment.category, 0) || "PAY"
        end
      end

      # The payment scope carries refunds too, and a refund named as a payment reads as a
      # second payment against the same stay.
      def payment_description(payment)
        source = payment.metadata.to_h["payment_source"].to_s
        label = PAYMENT_SOURCE_LABELS[source] || payment.posted_transaction_code_name.presence ||
          PAYMENT_FALLBACK_CODES.dig(payment.category, 1) || payment.description.presence || "Payment"
        "#{payment.category == 'refund' ? 'Refund' : 'Payment'} - #{label}"
      end

      def payment_reference(payment)
        metadata = payment.metadata.to_h
        PAYMENT_REFERENCE_KEYS.each do |key, label|
          value = metadata[key].presence || metadata.dig("source_references", key).presence
          return "#{label}: #{value}" if value.present?
        end
        nil
      end
    end
  end
end
