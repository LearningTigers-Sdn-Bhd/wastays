# frozen_string_literal: true

require "csv"

module Ezee
  # Reads the eZee reservation CSV: one header row, one row per reservation,
  # then a "Total Reservation" footer.
  #
  # Unlike the Reservation List this report is read by column *name*, and it
  # carries a real guest name, a separate Business Source (the agency or
  # channel), a per-row status, and the staff's remarks on the same row. Money
  # is per room per night -- eZee has no per-person model -- so the stay total is
  # rate x nights. See docs/integrations/ezee-reservation-import.md, "Reservation CSV".
  class ReservationCsvParser
    REQUIRED_HEADERS = [
      "Res. No", "Guest", "Room", "Rate(RM)", "Arrival", "Departure", "Nights",
      "Pax", "Res.Type", "Rate Type", "Deposit(RM)"
    ].freeze
    SIGNATURE_HEADERS = [ "Res. No", "Business Source" ].freeze

    RESERVATION_NUMBER = /\ARES\d+(-\d+)?\z/
    DATE_FORMAT = "%d/%m/%Y"
    # eZee's "Res.Type". Released rooms are kept as cancelled records so the
    # guest and their history survive; Hold is an unpaid, not yet confirmed one.
    STATUSES = {
      "confirm booking" => "confirmed",
      "hold confirm booking" => "pending",
      "released" => "cancelled"
    }.freeze
    HONORIFIC = /\A(?:mr|mrs|ms|miss|mdm|madam|dr)\.?\s+/i
    TRIP_COM = /\A(?:ctrip|trip\.com)\z/i
    DIRECT = /\Adirect booking\z/i
    UNLABELED_NOTE = "Unlabeled agent booking (no Business Source in eZee)."
    # eZee's own balance runs RM10 a head above the room total on most agent and
    # direct bookings. That is the jetty fee: RM10 per person per entrance, all
    # nationalities, charged to the agent (so a two-night stay is one entrance).
    # It is not tourism tax -- that is RM10 per room per night, international
    # guests only, collected at check-in. wastays does not charge the jetty fee
    # here, so it is noted for the desk instead.
    JETTY_FEE_PER_HEAD = 10

    Result = ParseResult

    def self.call(...) = new(...).call

    def self.recognises?(path)
      headers = File.open(path, "r:bom|utf-8", &:readline).to_s.parse_csv.to_a.map { |h| h.to_s.strip }
      SIGNATURE_HEADERS.all? { |header| headers.include?(header) }
    rescue EOFError, CSV::MalformedCSVError, ArgumentError, SystemCallError
      false
    end

    def initialize(path:, filename: nil)
      @path = path.to_s
      @filename = (filename.presence || File.basename(@path)).to_s
    end

    def call
      table = CSV.parse(File.read(@path, encoding: "bom|utf-8"), headers: true, skip_blanks: false, liberal_parsing: true)
      missing = REQUIRED_HEADERS - table.headers.compact.map(&:strip)
      return failure("This CSV is missing the column#{'s' if missing.size > 1} #{missing.map { |h| "\"#{h}\"" }.to_sentence}.") if missing.any?

      rows = []
      declared = nil
      table.each.with_index(2) do |record, line|
        number = cell(record, "Res. No")
        declared ||= declared_total(record)
        next unless number.match?(RESERVATION_NUMBER) && cell(record, "Arrival").present?

        rows << build_row(record, line)
      end

      return failure("No reservations found. Is this an eZee reservation CSV?") if rows.empty?

      AgencyFromGuest.call(rows)
      Result.new(rows: rows, declared_total: declared, warnings: count_warning(rows, declared), layout: :reservation_csv)
    rescue CSV::MalformedCSVError, ArgumentError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError => e
      failure("Could not read the file: #{e.message}")
    end

    private

    def build_row(record, line)
      adults, children = pax(record)
      nights = cell(record, "Nights").to_i
      arrival = parse_date(cell(record, "Arrival"))
      departure = parse_date(cell(record, "Departure"))
      nights = (departure - arrival).to_i if nights.zero? && arrival && departure
      rate = money(cell(record, "Rate(RM)"))
      deposit = money(cell(record, "Deposit(RM)"))
      balance = money(cell(record, "Balance Due(RM)"))
      source = source_for(cell(record, "Business Source"))
      guest_name, title = split_title(cell(record, "Guest"))
      remarks = remarks_for(record)
      boats = BoatRemark.call(cell(record, "Reservation Remarks"))

      ReservationRow.new(
        sheet_row: line,
        reservation_number: cell(record, "Res. No"),
        source: source[:label],
        guest_name: guest_name,
        arrival: arrival,
        departure: departure,
        adults: adults,
        children: children,
        nights: nights,
        room_number: room_number(cell(record, "Room")),
        room_type: room_type(cell(record, "Room")),
        rate_type: cell(record, "Rate Type"),
        total_amount: rate * nights,
        amount_paid: deposit,
        user: cell(record, "User"),
        remark: remarks,
        layout: :reservation_csv,
        booking_status: STATUSES.fetch(cell(record, "Res.Type").downcase, "confirmed"),
        group_ref: group_ref(cell(record, "Res. No")),
        agency_name: source[:agency],
        source_key: source[:key],
        internal_note: internal_note(title: title, source: source, deposit: deposit, balance: balance,
                                     total: rate * nights, adults: adults, children: children),
        boat_in: boats[:boat_in]&.to_h,
        boat_out: boats[:boat_out]&.to_h
      )
    end

    # Business Source is the agency, the channel, or nothing.
    def source_for(value)
      return { label: "Unlabeled", key: "internal", agency: nil, unlabeled: true } if value.blank?
      return { label: "Trip.com", key: "ota", agency: nil } if value.match?(TRIP_COM)
      return { label: "Direct Booking", key: "direct", agency: nil } if value.match?(DIRECT)

      { label: "Travel Agent", key: "travel_agent", agency: value }
    end

    # Staff-only context. The remarks stay where the guest-facing requests go;
    # this is what the importer itself has to say.
    def internal_note(title:, source:, deposit:, balance:, total:, adults:, children:)
      [
        (UNLABELED_NOTE if source[:unlabeled]),
        ("Title in eZee: #{title.delete_suffix('.')}." if title.present?),
        gap_note(deposit + balance - total, adults, children)
      ].compact.join(" ").presence
    end

    def gap_note(gap, adults, children)
      return nil if gap.abs < 0.01

      amount = format("%.2f", gap)
      if gap.positive? && [ JETTY_FEE_PER_HEAD * adults, JETTY_FEE_PER_HEAD * (adults + children) ].include?(gap)
        "eZee balance included RM#{amount} above the room total (jetty fee, RM10 a person); not charged here."
      else
        "eZee deposit + balance differs from the room total by RM#{amount}."
      end
    end

    def split_title(name)
      match = name.match(HONORIFIC)
      return [ name, nil ] unless match

      stripped = name.sub(HONORIFIC, "").strip
      return [ name, nil ] if stripped.blank?

      [ stripped, match[0].strip ]
    end

    # Guest-facing remarks: the reservation remarks, then the check-in remarks,
    # with the same sentence in both columns kept once.
    def remarks_for(record)
      [ cell(record, "Reservation Remarks"), cell(record, "Check In Remarks") ]
        .reject(&:blank?).uniq.join("\n").presence
    end

    # "RES4433-2" is the second room of booking RES4433; a bare number is a single.
    def group_ref(number) = number[/\A(RES\d+)-\d+\z/, 1]

    def room_number(value) = value.match(/\A(\S+)\s+-\s+/)&.captures&.first.to_s
    def room_type(value) = value.sub(/\A\S+\s+-\s+/, "").strip

    def pax(record)
      adults, children = cell(record, "Pax").split("/").map { |part| part.to_i }
      [ adults.to_i, children.to_i ]
    end

    # The footer reads "Total Reservation,#(258)".
    def declared_total(record)
      return nil unless cell(record, "Res. No").downcase.start_with?("total reservation")

      record.fields.compact.filter_map { |field| field[/\A#\((\d+)\)\z/, 1] }.first&.to_i
    end

    def count_warning(rows, declared)
      return [] if declared.nil? || declared == rows.size

      [ "The file states #{declared} reservations but #{rows.size} parsed. The layout may have changed -- check before importing." ]
    end

    def cell(record, header) = record[header].to_s.strip

    def parse_date(value)
      Date.strptime(value[0, 10], DATE_FORMAT)
    rescue Date::Error
      nil
    end

    def money(value)
      BigDecimal(value.to_s.delete(",").presence || "0")
    rescue ArgumentError
      BigDecimal(0)
    end

    def failure(message) = Result.new(rows: [], warnings: [], error: message, layout: :reservation_csv)
  end
end
