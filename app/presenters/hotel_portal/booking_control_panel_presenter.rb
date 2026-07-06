# frozen_string_literal: true

module HotelPortal
  class BookingControlPanelPresenter
    RoomRow = Data.define(:room_number, :room_type)
    Tab = Data.define(:key, :label)
    TreeRow = Data.define(:id, :label, :description, :kind, :active, :href)
    TreeGroup = Data.define(:label, :description, :rows)
    RoomRateRow = Data.define(:booking_reference, :date, :room_type, :room, :rate_plan, :nightly_rate, :rate_missing)
    RequestCard = Data.define(:id, :type, :title, :details, :room_label, :time_label, :status, :column, :record, :completed)
    RequestColumn = Data.define(:key, :label, :cards)
    BillingPartyRow = Data.define(:id, :kind, :label, :role, :description, :folio_count, :folio_labels, :record)
    FolioWindowBillingPartyOption = Data.define(:id, :group, :label, :description, :record)

    TABS = [
      Tab.new("booking_details", "Booking Details"),
      Tab.new("folio_operations", "Folio Operations"),
      Tab.new("security_deposits", "Security Deposits"),
      Tab.new("billing_preferences", "Billing Preferences"),
      Tab.new("guest_details", "Guest Details"),
      Tab.new("room_and_rate", "Room & Rate"),
      Tab.new("source_details", "Source Details"),
      Tab.new("housekeeping_requests", "Requests"),
      Tab.new("audit_trails", "Audit Trails")
    ].freeze
    ALERT_ACTIONS = %w[change_rate].freeze

    STATUS_LABELS = {
      "pending" => "Pending",
      "confirmed" => "Confirmed",
      "review_no_show" => "Pending no-show review",
      "checked_in" => "Checked in",
      "review_due_out" => "Pending late-checkout review",
      "checkout_required" => "Checkout required",
      "cancelled" => "Cancelled",
      "completed" => "Checked out",
      "overbooked" => "Overbooked",
      "no_show" => "No-show"
    }.freeze

    attr_reader :booking

    attr_reader :hotel, :booking_presenter, :folio_show

    def initialize(booking, params: {}, hotel: booking.hotel, booking_presenter: nil, folio_show: nil)
      @booking = booking
      @params = params
      @hotel = hotel
      @booking_presenter = booking_presenter || BookingPresenter.new(booking, hotel)
      @folio_show = folio_show
    end

    def booking_id
      booking.id
    end

    def booking_reference
      booking_number
    end

    def booking_number
      booking.formatted_reservation_number.presence || "—"
    end

    def group_booking_number
      group_booking&.formatted_reservation_number.presence || "—"
    end

    def summary_booking_number
      group_context_enabled? ? group_booking_number : booking_number
    end

    def summary_heading
      group_overview? ? group_booking.name : primary_guest_name
    end

    def summary_subtitle
      "Booking No. #{summary_booking_number}"
    end

    def mobile_context_label
      group_overview? ? group_booking.name : booking_number
    end

    def status_label
      STATUS_LABELS.fetch(booking.status, booking.status.to_s.humanize)
    end

    def check_in_date
      format_stay_date(booking.check_in)
    end

    def check_out_date
      format_stay_date(booking.check_out)
    end

    def primary_guest_name
      primary_booking_guest&.guest&.name.presence || booking.guest_name
    end

    def room_count
      booking.booking_rooms.sum { |room| room.quantity.to_i }
    end

    def rooms
      booking.booking_rooms.map do |room|
        RoomRow.new(
          room_number: room.room_number.presence || "Unassigned",
          room_type: room.room_type&.name.presence || room.room_type_snapshot.to_h["name"].presence || "Room type unavailable"
        )
      end
    end

    def source_label
      booking.source.to_s.presence&.tr("_", " ")&.titleize || "Not available"
    end

    def tabs
      TABS
    end

    def active_tab
      key = normalized_tab(@params[:tab])
      tabs.any? { |tab| tab.key == key } ? key : "booking_details"
    end

    def active_tab_label
      tabs.find { |tab| tab.key == active_tab }&.label || "Booking Details"
    end

    def active_tab_partial
      "hotel_portal/booking_control_panels/#{active_tab}/panel"
    end

    def tab_path(tab_key)
      entity_tab = tab_key.to_s.in?(%w[folio_operations guest_details])
      path_for(booking, tab: tab_key, scope: ("group" if group_overview? && !entity_tab))
    end

    def close_drawer_path
      path_for(
        booking,
        tab: active_tab,
        scope: group_overview? ? "group" : nil,
        folio_id: @params[:folio_id].presence,
        booking_guest_id: @params[:booking_guest_id].presence,
        billing_scope: @params[:billing_scope].presence
      )
    end

    def alert_action
      value = @params[:alert_action].to_s
      value if value.in?(ALERT_ACTIONS)
    end

    def alert_open?
      alert_action.present?
    end

    def alert_partial
      "hotel_portal/booking_control_panels/alerts/#{alert_action}_alert"
    end

    def close_alert_path
      path_for(
        booking,
        tab: active_tab,
        scope: group_overview? ? "group" : nil,
        folio_id: @params[:folio_id].presence,
        booking_guest_id: @params[:booking_guest_id].presence,
        billing_scope: @params[:billing_scope].presence,
        folio_routing_rule_id: @params[:folio_routing_rule_id].presence
      )
    end

    def left_rail_mode
      case active_tab
      when "folio_operations" then group_context_enabled? ? "grouped_folio_tree" : "folio_tree"
      when "guest_details" then group_context_enabled? ? "grouped_guest_tree" : "guest_tree"
      else group_context_enabled? ? "child_booking_tree" : "booking_context"
      end
    end

    def left_rail_title
      case left_rail_mode
      when "folio_tree" then "Booking / Folios"
      when "grouped_folio_tree" then "Bookings / Folios"
      when "guest_tree" then "Booking / Guests"
      when "grouped_guest_tree" then "Bookings / Guests"
      when "child_booking_tree" then grouped_booking_rail_title
      when "booking_context" then standalone_booking_rail_title
      else "Booking"
      end
    end

    def layout_mode
      drawer_open? ? "left_center_right" : "left_and_center"
    end

    def show_left_rail?
      layout_mode.in?(%w[left_and_center left_center_right])
    end

    def show_right_drawer?
      layout_mode.in?(%w[center_and_right left_center_right])
    end

    def drawer
      @params[:drawer].to_s.presence
    end

    def drawer_open?
      drawer.in?(%w[billing deposit])
    end

    def group_booking?
      booking.group_booking?
    end

    def group_context_enabled?
      booking.group_booking_id.present?
    end

    def group_overview?
      group_context_enabled? && @params[:scope].to_s == "group"
    end

    def group_booking
      booking.group_booking
    end

    def child_bookings
      return [ booking ] unless group_context_enabled?

      @child_bookings ||= booking.group_booking.bookings
        .includes(:deposits, :housekeeping_requests, :complaint_requests, :booking_folios, :folio_operation_logs, :booking_rooms, booking_guests: :guest)
        .to_a
    end

    def selected_child_booking
      child_bookings.find { |child| child.id.to_s == @params[:child_booking_id].to_s } || booking
    end

    def selected_booking_guest
      booking.booking_guests.find { |record| record.id.to_s == @params[:booking_guest_id].to_s } ||
        booking.booking_guests.find(&:primary?) || booking.booking_guests.first
    end

    def guest_display(booking_guest = selected_booking_guest)
      record = booking_guest
      {
        name: safe_text(record&.name_snapshot.presence || record&.guest&.name.presence || booking.guest_name, fallback: "Guest details"),
        role: record&.primary? ? "★ Primary guest for this room" : "Additional guest",
        email: mask_email(safe_sensitive_snapshot(record, :email_snapshot)),
        phone: mask_phone(safe_sensitive_snapshot(record, :phone_snapshot)),
        country: safe_text(record&.country_snapshot.presence || record&.guest&.country, fallback: "—"),
        document_type: safe_text(record&.document_type_snapshot.presence || record&.guest&.document_type, fallback: "Document").to_s.upcase,
        government_id: mask_identity(safe_sensitive_snapshot(record, :government_id_snapshot)),
        profile_name: safe_text(record&.guest&.name, fallback: "Unlinked profile"),
        profile_updated_at: record&.guest&.updated_at ? record.guest.updated_at.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y %H:%M") : "—",
        linked_profile: record&.guest.present?
      }
    end

    def selected_routing_rule
      booking.folio_routing_rules.find { |rule| rule.id.to_s == @params[:folio_routing_rule_id].to_s }
    end

    def routing_preview
      return unless selected_routing_rule

      @routing_preview ||= FolioRouting::PreviewExistingCharges.call(rule: selected_routing_rule)
    end

    def billing_scope
      return "booking" unless group_context_enabled?
      return "group" if group_overview?

      @params[:billing_scope].to_s.in?(%w[group booking]) ? @params[:billing_scope].to_s : "group"
    end

    def billing_editor
      @params[:billing_editor].to_s.presence
    end

    def billing_editor_id
      @params[:billing_party_id].presence || @params[:arrangement_id].presence
    end

    def billing_editor_open?(kind, record = nil)
      billing_editor == kind.to_s && (record.nil? || billing_editor_id.to_s == record.id.to_s)
    end

    def active_corporate_accounts
      @active_corporate_accounts ||= hotel.hotel_corporate_accounts.active
        .joins(:corporate_account)
        .includes(:corporate_account)
        .order("accounts.name")
    end

    def billing_preferences_path(**options)
      path_for(booking, **{ tab: "billing_preferences", scope: ("group" if group_overview?), billing_scope: billing_scope }.merge(options).compact)
    end

    def child_booking_rows
      child_bookings.map { |child| booking_navigation_row(child, active: child.id == booking.id && !group_overview?) }
    end

    def standalone_booking_rows
      [ booking_navigation_row(booking, active: true) ]
    end

    def grouped_booking_rail_title
      "Bookings / #{booking_rail_suffix}"
    end

    def standalone_booking_rail_title
      "Booking / #{booking_rail_suffix}"
    end

    def booking_rail_suffix
      {
        "booking_details" => "Details",
        "security_deposits" => "Deposits",
        "billing_preferences" => "Billing",
        "room_and_rate" => "Room Rate",
        "source_details" => "Sources",
        "housekeeping_requests" => "Requests",
        "audit_trails" => "Audit Trails"
      }.fetch(active_tab, active_tab_label)
    end

    def group_overview_path
      path_for(booking, tab: active_tab, scope: "group")
    end

    def booking_context_description
      booking_tree_description(booking)
    end

    def security_deposit_booking
      selected_child_booking
    end

    def security_deposits
      security_deposit_booking.deposits.select { |deposit| deposit.hold_type == "security" }.sort_by { |deposit| [ deposit.collected_at || deposit.created_at, deposit.id ] }.reverse
    end

    def held_security_deposit_total
      security_deposits.select { |deposit| deposit.status == "held" }.sum { |deposit| deposit.amount.to_d }
    end

    def security_deposit_status_label
      return "No deposits" if security_deposits.empty?
      return "Held" if held_security_deposit_total.positive?
      return "Released" if security_deposits.all? { |deposit| deposit.status == "released" }

      security_deposits.map { |deposit| deposit.status.to_s.humanize }.uniq.to_sentence
    end

    def security_deposit_rows
      security_deposits.map do |deposit|
        {
          id: deposit.id,
          amount: money_for(security_deposit_booking, deposit.amount),
          status: deposit.status.to_s.humanize,
          method: deposit.payment_method.to_s.presence&.humanize || "—",
          reference: deposit.external_reference.presence || deposit.metadata.to_h["release_reference"].presence || "—",
          collected_at: time_label(deposit.collected_at),
          released_at: time_label(deposit.released_at),
          staff: deposit.user&.name.presence || "—",
          read_only: deposit.status.in?(%w[released forfeited failed])
        }
      end
    end

    def requests_booking
      selected_child_booking
    end

    def requests_kanban_columns
      cards = request_cards
      [
        RequestColumn.new("new", "New", cards.select { |card| card.column == "new" }),
        RequestColumn.new("in_progress", "In Progress", cards.select { |card| card.column == "in_progress" }),
        RequestColumn.new("completed", "Completed", cards.select { |card| card.column == "completed" })
      ]
    end

    def request_cards
      bookings = group_overview? ? child_bookings : [ requests_booking ]
      bookings.flat_map { |child| request_cards_for(child) }
        .select { |card| card.column.present? }
        .sort_by { |card| [ card.completed ? 1 : 0, card.record.display_requested_at || card.record.created_at ] }
    end

    def group_total_balance
      child_bookings.sum { |child| child.booking_folios.sum { |folio| folio.projected_outstanding_balance.to_d } }
    end

    def group_security_deposit_rows
      child_bookings.map do |child|
        deposits = child.deposits.select { |deposit| deposit.hold_type == "security" }
        held = deposits.select { |deposit| deposit.status == "held" }.sum { |deposit| deposit.amount.to_d }
        {
          booking: child,
          booking_number: child_booking_number(child),
          room: child.booking_rooms.first&.room_number.presence || "Unassigned",
          guest: child.booking_guests.find(&:primary?)&.guest&.name.presence || child.guest_name,
          status: deposits.empty? ? "No deposit" : deposits.map { |deposit| deposit.status.humanize }.uniq.to_sentence,
          held: money_for(child, held),
          count: deposits.size
        }
      end
    end

    def group_guest_rows
      child_bookings.flat_map do |child|
        child.booking_guests.map do |record|
          {
            booking: child,
            booking_number: child_booking_number(child),
            booking_guest: record,
            name: record.guest&.name.presence || record.name_snapshot.presence || child.guest_name,
            role: record.primary? ? "Primary" : "Additional",
            room: child.booking_rooms.first&.room_number.presence || "Unassigned",
            country: record.country_snapshot.presence || record.guest&.country.presence || "—"
          }
        end
      end
    end

    def group_room_rate_rows
      child_bookings.flat_map { |child| room_rate_rows(child) }
    end

    def group_room_rate_issues
      child_bookings.filter_map do |child|
        message = room_rate_empty_message(child)
        { booking_reference: child_booking_number(child), message: message } if message.present?
      end
    end

    def group_room_rows
      child_bookings.map do |child|
        room = child.booking_rooms.first
        {
          booking: child,
          booking_number: child_booking_number(child),
          guest: child.booking_guests.find(&:primary?)&.guest&.name.presence || child.guest_name,
          room_type: room ? room_type_label(room) : "Room type unavailable",
          room: room&.room_number.presence || "Unassigned",
          stay: "#{format_stay_date(child.check_in)} – #{format_stay_date(child.check_out)}",
          rate_plan: room&.rate_plan&.name.presence || "Standard",
          value: money_for(child, room&.subtotal || 0),
          status: STATUS_LABELS.fetch(child.status, child.status.to_s.humanize)
        }
      end
    end

    def group_source_rows
      child_bookings.map do |child|
        {
          booking: child,
          booking_number: child_booking_number(child),
          guest: child.booking_guests.find(&:primary?)&.guest&.name.presence || child.guest_name,
          source: child.source.to_s.presence&.tr("_", " ")&.titleize || "Not available",
          external_reference: child.external_reference.presence || "—",
          channel_reference: child.channel_manager_reference.presence || "—"
        }
      end
    end

    def group_status_counts
      child_bookings.group_by(&:status).transform_values(&:size)
    end

    def group_arrival
      child_bookings.map(&:check_in).compact.min
    end

    def group_departure
      child_bookings.map(&:check_out).compact.max
    end

    def request_cards_for(child)
      housekeeping_cards = child.housekeeping_requests.reject(&:archived?).map do |request|
        RequestCard.new(
          request.id,
          "housekeeping",
          "Housekeeping",
          safe_text(request.request_details, fallback: "Housekeeping request"),
          request_room_label(child),
          time_label(request.display_requested_at),
          request.status,
          housekeeping_request_column(request.status),
          request,
          request.completed?
        )
      end

      complaint_cards = child.complaint_requests.reject(&:archived?).map do |request|
        RequestCard.new(
          request.id,
          "complaint",
          "Complaint",
          safe_text(request.complaint_details, fallback: "Complaint request"),
          request_room_label(child),
          time_label(request.display_requested_at),
          request.status,
          complaint_request_column(request.status),
          request,
          request.resolved?
        )
      end

      housekeeping_cards + complaint_cards
    end

    def billing_scope_rows
      [
        TreeRow.new("group", "Group arrangements", booking.group_booking&.name || "Group defaults", "billing", billing_scope == "group", nil),
        TreeRow.new("booking", "This booking", booking_number, "billing", billing_scope == "booking", nil)
      ]
    end

    def billing_party_rows
      booking_billing_parties.map do |party|
        party_folios = billing_party_folios(party)
        BillingPartyRow.new(
          party.id,
          billing_party_kind_label(party),
          safe_text(party.display_name, fallback: "Billing party"),
          billing_party_role_label(party),
          billing_party_description(party),
          party_folios.size,
          party_folios.map(&:display_name),
          party
        )
      end
    end

    def billing_party_empty_message
      "No billing parties are available for this booking. Add a guest to make that guest available for folio windows."
    end

    def folio_window_billing_party_options
      billing_party_rows.map do |row|
        FolioWindowBillingPartyOption.new(
          row.id,
          row.record.company? ? "Companies / Government" : "Guests",
          row.label,
          [ row.role, row.description ].compact_blank.join(" · "),
          row.record
        )
      end
    end

    def folio_window_billing_party_option_groups
      folio_window_billing_party_options.group_by(&:group)
    end

    def can_manage_folio_windows?
      folio_show&.can_manage_folio_windows? || false
    end

    def nights_count
      (booking.check_out.to_date - booking.check_in.to_date).to_i
    end

    def room_rate_rows(child = booking)
      return [] if child.booking_rooms.empty?

      child.booking_rooms.flat_map do |room|
        room_rate_dates(child, room).map do |date|
          snapshot = room.nightly_rate_snapshot.to_h[date.iso8601]
          snapshot_amount = snapshot.respond_to?(:to_h) ? snapshot.to_h["price"] : snapshot
          rate_missing = snapshot_amount.blank?

          RoomRateRow.new(
            child_booking_number(child),
            date,
            room_type_label(room),
            room.room_number.presence || "Not assigned",
            room.rate_plan&.name.presence || "Standard",
            rate_missing ? "Rate unavailable" : money_for(child, snapshot_amount),
            rate_missing
          )
        end
      end.sort_by { |row| [ row.date, row.room_type, row.room ] }
    end

    def room_rate_empty_message(child = booking)
      return "No room is attached to this booking." if child.booking_rooms.empty?
      return if room_rate_rows(child).any?

      "No recorded room rates are available for this booking."
    end

    def source_value(value)
      value.to_s.strip.presence || "Not provided"
    end

    def room_summary
      booking_presenter.room_summary
    end

    def total_balance
      folios.sum { |folio| folio.projected_outstanding_balance.to_d }
    end

    def currency
      booking.currency.presence || hotel.default_currency.presence || "MYR"
    end

    def summary_items
      if group_overview?
        return [
          [ "Arrival", format_summary_time(group_arrival) ],
          [ "Departure", format_summary_time(group_departure) ],
          [ "Rooms", child_bookings.size ],
          [ "Status", group_booking.projected_status.humanize ],
          [ "Booking No.", group_booking_number ],
          [ "Balance", money(group_total_balance) ]
        ]
      end

      [
        [ "Arrival", booking.check_in.in_time_zone(hotel.hotel_time_zone).strftime("%Y/%m/%d %H:%M") ],
        [ "Departure", booking.check_out.in_time_zone(hotel.hotel_time_zone).strftime("%Y/%m/%d %H:%M") ],
        [ "Nights", nights_count ],
        [ "Room / Room Type", room_summary ],
        [ "Booking No.", summary_booking_number ],
        [ "Balance", money(total_balance) ]
      ]
    end

    def room_tree_rows
      booking.booking_rooms.map do |room|
        room_tree_row(room)
      end
    end

    def room_tree_groups
      booking.booking_rooms.group_by { |room| room_type_label(room) }.map do |room_type, rooms|
        TreeGroup.new(room_type, pluralize_count(rooms.size, "room"), rooms.map { |room| room_tree_row(room) })
      end
    end

    def folio_tree_rows
      folios.map do |folio|
        folio_tree_row(folio, active: folio_operations_folio_active?(folio)).with(
          href: path_for(booking, tab: active_tab, folio_id: folio.id)
        )
      end
    end

    def booking_folio_tree_groups
      [ booking_entity_tree_group(booking, folio_tree_rows) ]
    end

    def grouped_folio_tree_groups
      @grouped_folio_tree_groups ||= child_bookings.map do |child|
        rows = child.booking_folios.to_a.sort_by { |folio| [ folio.is_primary? ? 0 : 1, folio.folio_sequence.to_i, folio.id ] }.map do |folio|
          folio_tree_row(
            folio,
            active: !group_overview? && child.id == booking.id && folio_operations_folio_active?(folio)
          ).with(
            href: Rails.application.routes.url_helpers.hotel_booking_control_panel_path(hotel, child, tab: active_tab, folio_id: folio.id)
          )
        end

        booking_entity_tree_group(child, rows)
      end
    end

    def group_folio_tree_rows
      folios.select { |folio| folio.booking_room_id.blank? }.map { |folio| folio_tree_row(folio, active: folio_operations_folio_active?(folio)) }
    end

    def folio_room_type_groups
      booking.booking_rooms.group_by { |room| room_type_label(room) }.map do |room_type, rooms|
        {
          label: room_type,
          description: pluralize_count(rooms.size, "room"),
          room_groups: rooms.map do |room|
            {
              id: room.id,
              label: room_label(room),
              description: room_type_label(room),
              active: selected_room_id == room.id.to_s,
              rows: folios.select { |folio| folio.booking_room_id == room.id }.map { |folio| folio_tree_row(folio, active: folio_operations_folio_active?(folio)) }
            }
          end
        }
      end
    end

    def guest_tree_groups
      guest_rows = booking.booking_guests.sort_by { |booking_guest| booking_guest.primary? ? 0 : 1 }.map do |booking_guest|
        guest = booking_guest.guest
        TreeRow.new(
          booking_guest.id,
          guest&.name.presence || booking.guest_name,
          booking_guest.primary? ? "Primary guest" : "Additional guest",
          "guest",
          guest_row_active?(booking_guest),
          path_for(booking, tab: active_tab, booking_guest_id: booking_guest.id)
        )
      end

      [ booking_entity_tree_group(booking, guest_rows) ]
    end

    def grouped_guest_tree_groups
      @grouped_guest_tree_groups ||= child_bookings.map do |child|
        rows = child.booking_guests.sort_by { |record| record.primary? ? 0 : 1 }.map do |booking_guest|
          TreeRow.new(
            booking_guest.id,
            booking_guest.guest&.name.presence || booking_guest.name_snapshot.presence || child.guest_name,
            booking_guest.primary? ? "Primary guest" : "Additional guest",
            "guest",
            child.id == booking.id && selected_booking_guest&.id == booking_guest.id && !group_overview?,
            path_for(child, tab: active_tab, booking_guest_id: booking_guest.id)
          )
        end

        booking_entity_tree_group(child, rows)
      end
    end

    def booking_tree_group_open?(group)
      return false if group_overview?

      group.rows.any?(&:active) || group.equal?(current_booking_tree_group)
    end

    def request_tree_groups
      request_rows = [
        TreeRow.new("housekeeping", "Housekeeping", pluralize_count(booking.housekeeping_requests.size, "request"), "request", request_row_active?("housekeeping"), nil),
        TreeRow.new("complaints", "Complaints", pluralize_count(booking.complaint_requests.size, "request"), "request", request_row_active?("complaints"), nil)
      ]

      [ TreeGroup.new("Requests", "Booking-level requests", request_rows) ] + room_tree_groups
    end

    def audit_tree_groups
      guest_rows = booking.booking_guests.map do |booking_guest|
        TreeRow.new(booking_guest.id, booking_guest.guest&.name.presence || booking.guest_name, booking_guest.is_primary? ? "Primary guest" : "Additional guest", "guest", audit_row_active?("guest", booking_guest.id), nil)
      end
      audit_room_rows = booking.booking_rooms.map do |room|
        TreeRow.new(room.id, room_label(room), room_type_label(room), "room", audit_row_active?("room", room.id), nil)
      end
      audit_folio_rows = folios.map do |folio|
        folio_tree_row(folio, active: audit_row_active?("folio", folio.id))
      end

      [
        TreeGroup.new("All Activity", "Full booking timeline", [ TreeRow.new("all", "All Activity", booking_reference, "audit", audit_row_active?("all", nil), nil) ]),
        TreeGroup.new("Rooms", pluralize_count(audit_room_rows.size, "room"), audit_room_rows),
        TreeGroup.new("Folios", pluralize_count(audit_folio_rows.size, "folio"), audit_folio_rows),
        TreeGroup.new("Guests", pluralize_count(guest_rows.size, "guest"), guest_rows)
      ]
    end

    def selected_folio
      return unless active_tab == "folio_operations"
      return folio_show&.folio if folio_show.present?

      folios.find { |folio| folio.id.to_s == (@params[:folio_id].presence || @params[:active_folio_id]).to_s } || booking.booking_folio || folios.first
    end

    def group_deposit_provenance_for(transaction)
      allocation = selected_folio&.group_deposit_allocations&.find { |candidate| candidate.folio_transaction_id == transaction.id }
      return unless allocation

      "Group deposit allocation ##{allocation.group_deposit_id}"
    end

    def selected_room_id
      @params[:room_id].to_s.presence
    end

    def folios
      @folios ||= booking.booking_folios.to_a.sort_by { |folio| [ folio.booking_room_id.present? ? 0 : 1, folio.is_primary? ? 0 : 1, folio.folio_sequence.to_i, folio.id ] }
    end

    def money(amount)
      format("%<currency>s %<amount>.2f", currency: currency, amount: amount.to_d)
    end

    def money_for(child, amount)
      format("%<currency>s %<amount>.2f", currency: child.currency.presence || currency, amount: amount.to_d)
    end

    def time_label(value)
      return "—" if value.blank?

      value.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y %H:%M")
    end

    private

    def valid_room_rate_dates?(child)
      child.check_in.present? && child.check_out.present? && child.check_out.to_date > child.check_in.to_date
    end

    def room_rate_dates(child, room)
      snapshot_dates = room.nightly_rate_snapshot.to_h.keys.filter_map do |value|
        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end
      expected_dates = valid_room_rate_dates?(child) ? (child.check_in.to_date...child.check_out.to_date).to_a : []

      (snapshot_dates + expected_dates).uniq.sort
    end

    def normalized_tab(value)
      { "room_charges" => "room_and_rate", "billing_details" => "billing_preferences" }.fetch(value.to_s, value.to_s)
    end

    def safe_sensitive_snapshot(record, attribute)
      return "" if record.blank?

      safe_text(record.public_send(attribute), fallback: "")
    rescue ActiveRecord::Encryption::Errors::Decryption, JSON::ParserError, ArgumentError
      ""
    end

    def safe_text(value, fallback: "—")
      text = value.to_s.strip
      return fallback if text.blank?
      return fallback if encryption_envelope_like?(text)

      text
    end

    def encryption_envelope_like?(text)
      text.start_with?("{\"p\":", "{\"p\"=>", "{\"ct\":", "{\"iv\":") || text.include?("\"_rails\"") || text.include?("\"ciphertext\"")
    end

    def mask_email(value)
      text = safe_text(value, fallback: "")
      return "—" if text.blank? || !text.include?("@")

      local, domain = text.split("@", 2)
      "#{local.first}***@#{domain}"
    end

    def mask_phone(value)
      text = safe_text(value, fallback: "").gsub(/\s+/, "")
      return "—" if text.blank?

      suffix = text.last(4)
      prefix = text.start_with?("+") ? text[/\A\+\d{1,3}/].to_s : ""
      "#{prefix}••••#{suffix}"
    end

    def mask_identity(value)
      text = safe_text(value, fallback: "")
      return "—" if text.blank?

      "••••#{text.last(4)}"
    end

    def primary_booking_guest
      booking.booking_guests.find(&:is_primary?)
    end

    def room_tree_row(room)
      TreeRow.new(
        room.id,
        room_label(room),
        room_type_label(room),
        "room",
        room_row_active?(room),
        nil
      )
    end

    def folio_tree_row(folio, active: false)
      TreeRow.new(
        folio.id,
        folio.display_name,
        [ folio.folio_reference_display, folio.payer_display_label ].compact_blank.join(" · "),
        "folio",
        active,
        nil
      )
    end

    def child_booking_label(child)
      room = child.booking_rooms.first
      room&.room_number.present? ? "Room #{room.room_number}" : "Unassigned room"
    end

    def booking_entity_tree_group(child, rows)
      TreeGroup.new(child_booking_label(child), child_booking_menu_description(child), rows)
    end

    def child_booking_number(child)
      child.formatted_reservation_number.presence || "—"
    end

    def child_booking_number_label(child)
      number = child_booking_number(child)
      "Booking No. #{number}" if number != "—"
    end

    def child_booking_description(child)
      booking_tree_description(child)
    end

    def child_booking_menu_description(child)
      room = child.booking_rooms.first
      room_type = room ? room_type_label(room) : "Room type unavailable"
      primary_guest = child.booking_guests.find(&:primary?)
      guest_name = primary_guest&.guest&.name.presence || primary_guest&.name_snapshot.presence || child.guest_name
      "#{room_type} - #{guest_name}"
    end

    def booking_navigation_row(child, active:)
      TreeRow.new(
        child.id,
        child_booking_label(child),
        child_booking_menu_description(child),
        "booking",
        active,
        path_for(child, tab: active_tab)
      )
    end

    def current_booking_tree_group
      index = child_bookings.index { |child| child.id == booking.id }
      return unless index

      case left_rail_mode
      when "grouped_folio_tree" then grouped_folio_tree_groups[index]
      when "grouped_guest_tree" then grouped_guest_tree_groups[index]
      end
    end

    def booking_tree_description(child)
      room = child.booking_rooms.first
      room_type = room ? room_type_label(room) : "Room type unavailable"
      room_number = room&.room_number.present? ? "Room #{room.room_number}" : "Unassigned room"
      "#{room_type} · #{room_number}"
    end

    def request_room_label(child)
      room = child.booking_rooms.first
      room&.room_number.present? ? "Room #{room.room_number}" : "Unassigned room"
    end

    def housekeeping_request_column(status)
      case status.to_s
      when "pending" then "new"
      when "in_progress" then "in_progress"
      when "completed" then "completed"
      end
    end

    def complaint_request_column(status)
      case status.to_s
      when "pending" then "new"
      when "in_progress" then "in_progress"
      when "resolved" then "completed"
      end
    end

    def folio_operations_folio_active?(folio)
      active_tab == "folio_operations" && folio.id.to_s == selected_folio_id.to_s
    end

    def selected_folio_id
      explicit_id = @params[:folio_id].presence || @params[:active_folio_id].presence
      return explicit_id if explicit_id.present?
      return unless active_tab == "folio_operations"

      folio_show&.folio&.id || booking.booking_folio&.id || folios.first&.id
    end

    def room_row_active?(room)
      left_rail_mode == "room_tree" && selected_room_id == room.id.to_s
    end

    def guest_row_active?(booking_guest)
      left_rail_mode == "guest_tree" && selected_booking_guest&.id == booking_guest.id
    end

    def request_row_active?(scope)
      left_rail_mode == "request_tree" && @params[:request_scope].to_s == scope.to_s
    end

    def audit_row_active?(kind, id)
      return false unless left_rail_mode == "audit_tree"
      return @params[:audit_scope].blank? || @params[:audit_scope].to_s == "all" if kind == "all"

      @params[:audit_scope].to_s == kind.to_s && audit_scope_param_for(kind).to_s == id.to_s
    end

    def audit_scope_param_for(kind)
      case kind.to_s
      when "room" then @params[:room_id]
      when "folio" then @params[:folio_id]
      when "guest" then @params[:booking_guest_id]
      end
    end

    def room_label(room)
      room.room_number.presence || "Unassigned room"
    end

    def room_type_label(room)
      room.room_type&.name.presence || room.room_type_snapshot.to_h["name"].presence || "Room type unavailable"
    end

    def pluralize_count(count, singular)
      "#{count} #{singular.pluralize(count)}"
    end

    def format_stay_date(value)
      value.in_time_zone(booking.hotel.hotel_time_zone).strftime("%d %b %Y")
    end

    def format_summary_time(value)
      return "—" if value.blank?

      value.in_time_zone(hotel.hotel_time_zone).strftime("%Y/%m/%d %H:%M")
    end

    def path_for(target_booking, **query)
      Rails.application.routes.url_helpers.hotel_booking_control_panel_path(hotel, target_booking, query.compact)
    end

    def booking_billing_parties
      @booking_billing_parties ||= booking.booking_billing_parties.active
        .includes(:billing_terms, :booking_guest, hotel_corporate_account: :corporate_account)
        .to_a
        .sort_by { |party| billing_party_sort_key(party) }
    end

    def billing_party_sort_key(party)
      case party.party_kind
      when "guest"
        guest = party.booking_guest
        [ 0, guest&.primary? ? 0 : 1, safe_text(party.display_name, fallback: "").downcase ]
      when "company"
        [ 1, 0, safe_text(party.display_name, fallback: "").downcase ]
      else
        [ 2, 0, safe_text(party.display_name, fallback: "").downcase ]
      end
    end

    def billing_party_kind_label(party)
      party.company? ? "Company" : "Guest"
    end

    def billing_party_role_label(party)
      case party.party_kind
      when "guest"
        party.booking_guest&.primary? ? "Primary guest" : "Additional guest"
      when "company"
        "Company / Government account"
      else
        party.party_kind.to_s.humanize
      end
    end

    def billing_party_description(party)
      case party.party_kind
      when "guest"
        "Cash / card"
      when "company"
        account = party.hotel_corporate_account
        account&.direct_bill_enabled? ? "City Ledger · Direct bill enabled" : "Company settlement"
      else
        "Billing party"
      end
    end

    def billing_party_folios(party)
      folios.select { |folio| folio.booking_billing_party_id == party.id }
    end
  end
end
