# frozen_string_literal: true

module Ezee
  # Resolves parsed eZee rows against a hotel and reports what would happen,
  # without writing anything.
  #
  # This runs before every commit, not only when an operator asks to preview.
  # Bookings are created through Bookings::CreateManualBooking, which validates
  # availability -- so a row can fail on inventory the property has not set up,
  # and finding that out 900 bookings into a commit is useless.
  class ImportPlan
    # One row's verdict. `status` drives everything the preview shows:
    #   importable  -- will be created
    #   imported    -- already present, matched on external_reference
    #   past        -- arrival is before the business date (production rule)
    #   blocked     -- something is missing; `errors` says what
    Entry = Struct.new(
      :row, :status, :issues, :room_type, :room, :group_key,
      :agency_name, :existing_booking_id, keyword_init: true
    ) do
      def importable? = status == :importable

      # Each issue names the column it belongs to, so the preview can mark the
      # offending cell rather than print a sentence underneath the row and
      # leave the reader to work out which value it meant.
      def fault(field, message) = issues << { "field" => field.to_s, "level" => "error", "message" => message }
      def caution(field, message) = issues << { "field" => field.to_s, "level" => "warning", "message" => message }

      def errors = issues.select { |issue| issue["level"] == "error" }.map { |issue| issue["message"] }
      def warnings = issues.select { |issue| issue["level"] == "warning" }.map { |issue| issue["message"] }
    end

    # Several spellings in the export that resolve to one agency account.
    AgencyCollision = Struct.new(:spellings, :canonical, keyword_init: true) do
      # Two spellings differing only in whitespace render identically in HTML,
      # because the browser collapses runs of spaces. Saying so is the whole
      # point of the warning -- without it the operator reads the same name
      # twice and concludes the report is broken.
      def whitespace_only?(spelling)
        spellings.count { |other| other.squish == spelling.squish } > 1
      end
    end

    Result = Struct.new(
      :entries, :business_date, :groups, :agencies, :agency_collisions, :warnings,
      keyword_init: true
    ) do
      def importable = entries.select(&:importable?)
      def counts = entries.group_by(&:status).transform_values(&:size)

      def total_amount = importable.sum { |entry| entry.row.total_amount }
      def new_agencies = agencies.reject { |_name, account| account }.keys
      def matched_agencies = agencies.select { |_name, account| account }
    end

    # The sources whose "guest name" is an agency rather than a person. Every
    # other source either names a real guest or leaves the field blank.
    AGENCY_SOURCES = [ "Travel Agent", "Corporate" ].freeze

    # eZee prints the source in place of an empty guest name, so these are not
    # names -- they are the absence of one. See docs section 2.1.
    BLANK_NAME = /\A-\s*/

    # Staff mark a reservation's state by editing the agency name itself. The
    # prefix is not part of the name and is never the spelling an account is
    # named after.
    STATUS_PREFIX = /\A\s*POSTPONED?\s*[-:\s]\s*/

    def self.call(...) = new(...).call

    def initialize(hotel:, rows:)
      @hotel = hotel
      @rows = rows
    end

    def call
      business_date = @hotel.current_business_date || @hotel.business_date_for
      group_keys = group_keys_for(@rows)
      entries = @rows.map { |row| resolve(row, business_date, group_keys) }

      Result.new(
        entries: entries,
        business_date: business_date,
        groups: group_summary(entries),
        agencies: agency_summary(entries),
        agency_collisions: agency_collisions(entries),
        warnings: []
      )
    end

    # Normalises an agency name for matching. The client's file shows why each
    # step is needed: a double space, a trailing "SDN.BHD.", a name typed twice,
    # and staff marking state by prefixing "POSTPONE" onto the name itself --
    # which, unstripped, creates a second account for one agency and detaches
    # its postponed bookings from the first one's ledger.
    def self.normalize_agency(name)
      value = name.to_s.upcase
                  .sub(STATUS_PREFIX, "")
                  .gsub(/\bSDN\.?\s*BHD\.?/, "SDN BHD")
                  .gsub(/[[:punct:]]/, " ")
                  .squish
      halves = value.split(" ")
      if halves.size.even? && halves.size > 2
        first = halves.first(halves.size / 2)
        value = first.join(" ") if first == halves.last(halves.size / 2)
      end
      value
    end

    # Which spelling becomes the account's name.
    #
    # One agency is written several ways, the account has to be called
    # something, and it must not be whichever row the database happened to
    # return first -- that answer moves between runs. A status prefix is not
    # part of a name, so those spellings are never chosen. Otherwise the
    # spelling the property uses most often wins, with ties broken on the
    # shortest and then alphabetically, so the choice is stable.
    def self.canonical_agency_name(counts_by_spelling)
      candidates = counts_by_spelling.reject { |spelling, _| spelling.to_s.match?(STATUS_PREFIX) }
      candidates = counts_by_spelling if candidates.empty?

      candidates.min_by { |spelling, count| [ -count, spelling.to_s.length, spelling.to_s ] }&.first
    end

    private

    def resolve(row, business_date, group_keys)
      entry = Entry.new(row: row, issues: [], status: :importable)

      existing_id = already_imported[row.reservation_number]
      if existing_id
        entry.existing_booking_id = existing_id
        entry.status = :imported
        return entry
      end

      entry.agency_name = agency_name_for(row)
      entry.group_key = group_keys[group_signature(row)]

      if row.arrival.blank? || row.departure.blank?
        entry.fault(:arrival, "Arrival or departure date could not be read.")
      elsif row.departure <= row.arrival
        entry.fault(:departure, "Departure #{row.departure} is not after arrival #{row.arrival}.")
      elsif row.arrival < business_date
        entry.status = :past
        return entry
      end

      resolve_inventory(row, entry)

      entry.caution(:guest_name, "Blank in the export; the source was printed instead.") if blank_name?(row)
      entry.caution(:total_amount, "No amount on this reservation.") if row.total_amount.zero?

      entry.status = :blocked if entry.errors.any?
      entry
    end

    def resolve_inventory(row, entry)
      entry.room_type = room_types_by_name[row.room_type.to_s.upcase]
      if entry.room_type.nil?
        entry.fault(:room_type_name, "No room category named #{row.room_type.inspect} at this property.")
        return
      end

      entry.room = rooms_by_number[row.room_number.to_s.upcase]
      if entry.room.nil?
        entry.caution(:room_number, "Not set up here; the booking will be left unassigned.")
      elsif entry.room.room_type_id != entry.room_type.id
        entry.caution(:room_number, "Belongs to #{entry.room.room_type.name}, not #{row.room_type}; " \
                                    "the booking will be left unassigned.")
        entry.room = nil
      end
    end

    # One query for the whole file. Asking per row cost 1193 queries on the
    # client's real export -- the N+1 this import would otherwise have shipped.
    def already_imported
      @already_imported ||= @hotel.bookings
                                  .where(external_reference: @rows.map(&:reservation_number))
                                  .pluck(:external_reference, :id)
                                  .to_h
    end

    def room_types_by_name
      @room_types_by_name ||= @hotel.room_types.index_by { |type| type.name.to_s.upcase }
    end

    def rooms_by_number
      @rooms_by_number ||= @hotel.rooms.where(archived_at: nil)
                                .includes(:room_type).index_by { |room| room.number.to_s.upcase }
    end

    # A stay is one block when the same booker holds the same dates. Reservation
    # numbers are deliberately not used: the client's file has blocks whose
    # numbers skip, because the missing ones were cancelled, so contiguity would
    # split stays that belong together.
    def group_signature(row)
      [ row.guest_name.to_s.upcase, row.arrival, row.departure ]
    end

    def group_keys_for(rows)
      counts = rows.group_by { |row| group_signature(row) }
      counts.filter_map { |signature, members| [ signature, signature ] if members.size > 1 }.to_h
    end

    def group_summary(entries)
      entries.select { |entry| entry.group_key && entry.importable? }
             .group_by(&:group_key)
             .map { |key, members| { name: key.first, arrival: key.second, rooms: members.size } }
             .sort_by { |group| [ group[:arrival], group[:name] ] }
    end

    def agency_name_for(row)
      return nil unless AGENCY_SOURCES.include?(row.source)
      return nil if blank_name?(row)

      row.guest_name.presence
    end

    # Matches on the normalised name so two spellings of one agency resolve to
    # the same account. Unmatched names are reported, not created here -- this
    # service writes nothing.
    def agency_summary(entries)
      names = entries.filter_map(&:agency_name).uniq
      existing = @hotel.hotel_corporate_accounts.includes(:corporate_account).index_by do |account|
        self.class.normalize_agency(account.corporate_account&.name)
      end
      names.index_with { |name| existing[self.class.normalize_agency(name)] }
    end

    def blank_name?(row) = row.guest_name.to_s.match?(BLANK_NAME) || row.guest_name.blank?

    def agency_collisions(entries)
      entries.select(&:importable?)
             .group_by { |entry| self.class.normalize_agency(entry.agency_name) }
             .except(nil, "")
             .filter_map do |_key, members|
        spellings = members.filter_map(&:agency_name).uniq
        AgencyCollision.new(spellings: spellings.sort) if spellings.size > 1
      end
    end
  end
end
