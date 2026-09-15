# frozen_string_literal: true

module Ezee
  # Creates bookings from the rows an operator approved.
  #
  # It reads ReservationImportRow, not the spreadsheet: the file was resolved
  # once at upload, and what gets created has to be what the preview showed.
  #
  # Every row goes through Bookings::CreateManualBooking, which is already the
  # one-room creation path -- it builds the booking_room, the financial snapshot
  # and the folio. Multi-room blocks are then grouped exactly as
  # Bookings::CreateStaffBooking does.
  #
  # Rows are committed one at a time rather than in a single transaction. An
  # import that rolls back 69 good rows because the 70th hit an occupied room
  # helps nobody; re-running is safe because a row already imported is matched
  # on external_reference and skipped.
  class ImportReservations
    Result = Struct.new(:created, :failed, :skipped, :groups, keyword_init: true)

    # eZee's source names against the BookingSource registry. "OTA (KPR ONLINE)"
    # is the property's own booking engine despite the label, so it is direct.
    # TIKET.COM has no registry key yet and lands on the generic OTA one.
    SOURCE_KEYS = {
      "Travel Agent" => "internal", "Corporate" => "internal",
      "Phone Reservation" => "phone", "Walk In" => "walk_in",
      "Over-The-Counter" => "walk_in", "Internet Reservation" => "direct",
      "OTA (KPR ONLINE)" => "direct", "AGODA" => "agoda", "TIKET.COM" => "ota"
    }.freeze

    # No row in the export carries a phone, and bookings.guest_phone is NOT NULL.
    # A sentinel is deliberate: a plausible-looking fake number is worse, because
    # someone would eventually dial it.
    GUEST_PHONE_SENTINEL = "NOT CAPTURED"

    def self.call(...) = new(...).call

    def initialize(import:, progress: nil)
      @import = import
      @hotel = import.hotel
      @user = import.user
      @progress = progress
    end

    def call
      pending = @import.rows.importable.in_sheet_order.to_a
      created = []
      failed = []

      report(step: "Creating bookings", processed: 0, created: 0)

      pending.each_with_index do |row, index|
        booking = create_booking(row)
        booking ? created << [ row, booking ] : failed << row

        report(step: "Creating bookings (#{index + 1} of #{pending.size})",
               processed: index + 1, created: created.size,
               failure: booking ? nil : row)
      end

      report(step: "Grouping multi-room stays", processed: pending.size, created: created.size)
      groups = build_groups(created)
      report(step: "Finishing up", processed: pending.size, created: created.size,
             groups: groups.compact.size)

      Result.new(
        created: created.map(&:last),
        failed: failed,
        skipped: @import.rows.where(status: "imported").count,
        groups: groups
      )
    end

    private

    def report(**payload) = @progress&.call(**payload)

    def create_booking(row)
      result = Bookings::CreateManualBooking.new(
        hotel: @hotel, params: booking_params(row), user: @user
      ).call

      unless result.success?
        mark_failed(row, Array(result.errors).to_sentence)
        return nil
      end

      row.update_columns(status: "created", booking_id: result.booking.id, updated_at: Time.current)
      result.booking
    rescue StandardError => e
      Rails.logger.warn("eZee import failed for #{row.reservation_number}: #{e.message}")
      mark_failed(row, e.message)
      nil
    end

    # The reason is written onto the row itself, tagged to no single column,
    # so the preview table can show it next to the reservation it belongs to.
    def mark_failed(row, message)
      row.update_columns(
        status: "failed",
        issues: row.issues + [ { "field" => nil, "level" => "error", "message" => message } ],
        updated_at: Time.current
      )
    end

    def booking_params(row)
      {
        guest_name: guest_name_for(row),
        guest_phone: GUEST_PHONE_SENTINEL,
        check_in: row.arrival,
        check_out: row.departure,
        adults: [ row.adults, 1 ].max,
        children: row.children,
        room_type_id: row.room_type_id,
        room_number: row.room&.number,
        require_room_number: false,
        source: SOURCE_KEYS.fetch(row.source, "internal"),
        external_reference: row.reservation_number,
        hotel_corporate_account_id: corporate_account_id_for(row),
        manual_rate_override: room_total_for(row),
        special_requests: row.remark.presence,
        internal_notes: notes_for(row)
      }.compact
    end

    # The eZee figure is the total the guest was quoted, and it wins. But
    # manual_rate_override is tax-exclusive -- BuildFinancialSnapshot adds the
    # hotel's room-revenue taxes on top of it -- so passing the printed amount
    # straight through would inflate every booking. SolveRoomTotalForFinalAmount
    # back-solves the room total that lands on the printed figure instead.
    #
    # guest_country stays nil, which is what keeps tourism tax off these
    # bookings: the export carries no nationality, and tourism tax applies only
    # to foreigners. See docs section 2.2.
    def room_total_for(row)
      # A complimentary reservation is zero, and must stay zero. The solver
      # floors its iteration at a cent -- deliberately, so the tax rules it is
      # solving against stay in play -- which would turn a free room into a
      # one-cent charge.
      return BigDecimal(0) if row.total_amount.to_d.zero?

      snapshot = Bookings::SolveRoomTotalForFinalAmount.new(
        hotel: @hotel,
        room_type: row.room_type,
        rate_plan: row.room_type.standard_rate_plan,
        check_in: row.arrival,
        check_out: row.departure,
        guest_country: nil,
        target_total: row.total_amount,
        adults: [ row.adults, 1 ].max,
        children: row.children
      ).call
      snapshot.room_total
    end

    # A blank name is stored as an explicit statement that the export did not
    # carry one, never as the "- AGODA" placeholder eZee prints in its place.
    def guest_name_for(row)
      return row.guest_name if row.guest_name.present? && !row.guest_name.start_with?("-")

      "Name not in export (#{row.source})"
    end

    def notes_for(row)
      [
        "Imported from eZee reservation #{row.reservation_number}.",
        ("Booked #{row.booked_at.to_fs(:short)} by #{row.booked_by}." if row.booked_at),
        "Source: #{row.source}. Rate type: #{row.rate_type}.",
        ("Paid in eZee before migration: #{'%.2f' % row.amount_paid} — not posted here." if row.amount_paid.to_d.positive?)
      ].compact.join(" ")
    end

    def corporate_account_id_for(row)
      return nil if row.agency_name.blank?

      corporate_accounts[ImportPlan.normalize_agency(row.agency_name)]&.id
    end

    # Agencies are keyed on the normalised name, so the export's several
    # spellings of one agency resolve to a single account rather than one each.
    def corporate_accounts
      @corporate_accounts ||= begin
        existing = @hotel.hotel_corporate_accounts.includes(:corporate_account).index_by do |link|
          ImportPlan.normalize_agency(link.corporate_account&.name)
        end
        @import.rows.importable.where.not(agency_name: nil).distinct.pluck(:agency_name).each do |name|
          key = ImportPlan.normalize_agency(name)
          existing[key] ||= create_corporate_account(name, key)
        end
        existing
      end
    end

    def create_corporate_account(name, key)
      account = Account.find_or_initialize_by(slug: key.parameterize)
      account.name = name
      account.account_kind = "corporate"
      account.status = "active"
      account.save!

      @hotel.hotel_corporate_accounts.create!(
        corporate_account: account,
        account_type: "travel_agent",
        # No credit terms and no direct billing: inventing those for a property
        # is not the importer's business. An operator sets them deliberately.
        relationship_type: "standard",
        direct_bill_enabled: false,
        credit_currency: @hotel.default_currency.presence || "MYR",
        status: "active"
      )
    end

    def build_groups(created)
      created.group_by { |row, _booking| row.group_key }
             .except(nil)
             .filter_map do |_key, members|
        bookings = members.map(&:last)
        next if bookings.one?

        group_for(members.first.first, bookings)
      end
    end

    def group_for(row, bookings)
      result = GroupBookings::CreateFromBookings.call(
        hotel: @hotel,
        bookings: bookings,
        attributes: {
          name: row.guest_name.presence || "Imported group",
          status: "active",
          default_check_in: bookings.first.check_in,
          default_check_out: bookings.first.check_out
        },
        actor: @user
      )
      result.success? ? result.group_booking : nil
    rescue StandardError => e
      Rails.logger.warn("eZee import could not group #{row.reservation_number}: #{e.message}")
      nil
    end
  end
end
