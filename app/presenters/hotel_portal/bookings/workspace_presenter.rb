# frozen_string_literal: true

module HotelPortal
  module Bookings
    class WorkspacePresenter
      RoomRow = Data.define(:room_number, :room_type)
      Tab = Data.define(:key, :label)
      TreeRow = Data.define(:id, :label, :description, :kind, :active, :href)
    TreeGroup = Data.define(:label, :description, :rows, :booking_id)
    RoomRateRow = Data.define(:booking_reference, :date, :room_type, :room, :rate_plan, :nightly_rate, :rate_missing)
    RequestCard = Data.define(:id, :type, :title, :details, :room_label, :time_label, :status, :column, :record, :completed)
    RequestColumn = Data.define(:key, :label, :cards)
    BillingPartyRow = Data.define(:id, :kind, :label, :role, :description, :folio_count, :folio_labels, :record)
    FolioWindowBillingPartyOption = Data.define(:id, :group, :label, :description, :record)
    SummaryAction = Data.define(:key, :label, :tone, :offcanvas_variant, :icon, :target_booking)
    DocumentRow = Data.define(:booking, :room_type, :room_number, :guest_name, :invoice_available)

    TABS = [
      Tab.new("booking_details", "Overview"),
      Tab.new("folio_operations", "Folios"),
      Tab.new("security_deposits", "Deposits"),
      Tab.new("billing_preferences", "Billing"),
      Tab.new("guest_details", "Guests"),
      Tab.new("room_and_rate", "Room & Rate"),
      Tab.new("housekeeping_requests", "Requests"),
      Tab.new("audit_trails", "Audit Trail")
    ].freeze
    LEGACY_TABS = [ Tab.new("source_details", "Source Details") ].freeze
    ALERT_ACTIONS = %w[change_rate].freeze
    ENTITY_TABS = %w[folio_operations guest_details].freeze
    BADGE_VARIANTS = {
      "slate" => :neutral, "blue" => :info, "amber" => :warning,
      "emerald" => :success, "orange" => :warning, "rose" => :destructive
    }.freeze

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
    STATUS_BADGE_LABELS = STATUS_LABELS.merge(
      "checked_in" => "In house",
      "review_due_out" => "Due out",
      "checkout_required" => "Checkout due",
      "review_no_show" => "No-show review"
    ).freeze
    STATUS_BADGE_TONES = {
      "pending" => "slate",
      "confirmed" => "blue",
      "review_no_show" => "amber",
      "checked_in" => "emerald",
      "review_due_out" => "amber",
      "checkout_required" => "orange",
      "cancelled" => "rose",
      "completed" => "slate",
      "overbooked" => "rose",
      "no_show" => "rose"
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

    def header_title
      group_context_enabled? ? group_booking.name : primary_guest_name.presence || "Guest unavailable"
    end

    def header_reference_line
      group_context_enabled? ? "Group Booking #{group_booking_number}" : "Booking #{booking_number}"
    end

    def header_stay_line
      if group_context_enabled?
        [ pluralize_count(child_bookings.size, "booking"), pluralize_count(group_room_count, "room"), group_stay_summary ].join(" · ")
      else
        [ room_summary, short_stay_range, (pluralize_count(nights_count, "night") if nights_count) ].compact_blank.join(" · ")
      end
    end

    def stay_dates_vary?
      return false unless group_context_enabled?

      group_arrival_dates.size > 1 || group_departure_dates.size > 1
    end

    def group_dates_incomplete?
      group_context_enabled? && child_bookings.any? { |child| child.check_in.blank? || child.check_out.blank? }
    end

    def group_stay_summary
      return "Some stay dates unavailable" if group_dates_incomplete?

      stay_dates_vary? ? "Stay dates vary" : format_short_range(group_arrival, group_departure)
    end

    def group_earliest_arrival
      format_summary_time(group_arrival)
    end

    def group_latest_departure
      format_summary_time(group_departure)
    end

    def group_arrival_dates
      distinct_child_dates(:check_in)
    end

    def group_departure_dates
      distinct_child_dates(:check_out)
    end

    def group_stay_variation_notice
      return unless stay_dates_vary?

      arrivals = group_arrival_dates.map { |date| format_short_date(date) }
      departures = group_departure_dates.map { |date| format_short_date(date) }
      "Arrivals occur on #{arrivals.to_sentence}. Departures occur on #{departures.to_sentence}."
    end

    def header_status_badge
      badge = group_context_enabled? ? group_status_badge : status_badge(booking.status)
      return if badge.blank?

      { label: badge[:label], variant: BADGE_VARIANTS.fetch(badge[:tone], :neutral) }
    end

    def header_outstanding_balance
      money(group_context_enabled? ? group_total_balance : total_balance)
    end

    def group_overview_header_path
      return unless group_context_enabled?

      path_for(booking, tab: "booking_details", scope: "group")
    end

    def status_label
      STATUS_LABELS.fetch(booking.status, booking.status.to_s.humanize)
    end

    def status_badge_for_booking_id(booking_id)
      child = child_bookings.find { |candidate| candidate.id.to_s == booking_id.to_s }
      status_badge(child&.status)
    end

    def status_badge_for_tree_group(group)
      return if group.booking_id.blank?

      status_badge_for_booking_id(group.booking_id)
    end

    def badge_variant_for(tone)
      BADGE_VARIANTS.fetch(tone.to_s, :neutral)
    end

    def status_badge(status)
      value = status.to_s
      return if value.blank?

      {
        label: STATUS_BADGE_LABELS.fetch(value, value.humanize),
        tone: STATUS_BADGE_TONES.fetch(value, "slate")
      }
    end

    def summary_actions
      group_context_enabled? ? group_summary_actions : standalone_summary_actions
    end

    def group_summary_actions
      return [] unless group_context_enabled?

      [
        group_summary_action(:check_in, "Check-in", :primary, "right", "log-in", %w[confirmed]),
        group_summary_action(:check_out, "Check-out", :primary, "fullscreen-bottom", "log-out", %w[checked_in checkout_required]),
        group_summary_action(:late_checkout, "Review Late Checkout", :warning, "right", "clock", %w[review_due_out]),
        group_summary_action(:backdated_check_in, "Backdated Check-in", :primary, "right", "calendar-clock", %w[review_no_show]),
        group_summary_action(:mark_no_show, "Mark No-show", :danger, "right", "user-x", %w[review_no_show]),
        group_summary_action(:cancel, "Cancel", :danger, "right", "ban", %w[pending confirmed review_no_show overbooked]),
        group_summary_action(:reinstate, "Reinstate", :primary, "right", "rotate-ccw", %w[no_show]),
        group_summary_action(:edit_check_in, "Edit Check-In", :neutral, "right", "pencil", %w[checked_in]),
        group_summary_action(:undo_check_in, "Undo Check-in", :warning, "right", "rotate-ccw", %w[checked_in])
      ].compact
    end

    def standalone_summary_actions
      case booking.status
      when "pending", "overbooked"
        [ standalone_summary_action(:cancel, "Cancel", :danger, "right", "ban") ]
      when "confirmed"
        [
          standalone_summary_action(:check_in, "Check-in", :primary, "right", "log-in"),
          standalone_summary_action(:cancel, "Cancel", :danger, "right", "ban")
        ]
      when "review_no_show"
        [
          standalone_summary_action(:backdated_check_in, "Backdated Check-in", :primary, "right", "calendar-clock"),
          standalone_summary_action(:mark_no_show, "Mark No-show", :danger, "right", "user-x"),
          standalone_summary_action(:cancel, "Cancel", :danger, "right", "ban")
        ]
      when "checked_in"
        [
          standalone_summary_action(:check_out, "Check-out", :primary, "fullscreen-bottom", "log-out"),
          standalone_summary_action(:edit_check_in, "Edit Check-In", :neutral, "right", "pencil"),
          standalone_summary_action(:undo_check_in, "Undo Check-in", :warning, "right", "rotate-ccw")
        ]
      when "review_due_out"
        [ standalone_summary_action(:late_checkout, "Review Late Checkout", :warning, "right", "clock") ]
      when "checkout_required"
        [ standalone_summary_action(:check_out, "Complete Checkout", :primary, "fullscreen-bottom", "log-out") ]
      when "no_show"
        [ standalone_summary_action(:reinstate, "Reinstate", :primary, "right", "rotate-ccw") ]
      else
        []
      end
    end

    def check_in_date
      format_stay_date(booking.check_in)
    end

    def check_out_date
      format_stay_date(booking.check_out)
    end

    def primary_guest_name
      primary_booking_guest&.name_snapshot.presence || primary_booking_guest&.guest&.name.presence || booking.guest_name
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
      hotel.feature_enabled?("full_audit_trail") ? TABS : TABS.reject { |tab| tab.key == "audit_trails" }
    end

    def active_tab
      key = normalized_tab(@params[:tab])
      supported_tabs.any? { |tab| tab.key == key } ? key : "booking_details"
    end

    def active_tab_label
      supported_tabs.find { |tab| tab.key == active_tab }&.label || "Overview"
    end

    def navigation_active_tab
      active_tab if tabs.any? { |tab| tab.key == active_tab }
    end

    def active_tab_partial
      "hotel_portal/bookings/workspaces/#{active_tab}/panel"
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
      "hotel_portal/bookings/workspaces/alerts/#{alert_action}_alert"
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
      active_tab.in?(ENTITY_TABS) ? "entity" : "standard"
    end

    def show_left_rail?
      layout_mode == "entity"
    end

    def show_right_drawer?
      drawer_open? && active_tab != "guest_details"
    end

    def drawer
      @params[:drawer].to_s.presence
    end

    def drawer_open?
      drawer.in?(%w[deposit])
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
        .includes(
          :hotel, :deposits, :housekeeping_requests, :complaint_requests, :folio_operation_logs,
          booking_folios: [ :folio_transactions, :folio_forecasted_charges ],
          booking_rooms: [ :room_type, :rate_plan ],
          booking_guests: :guest
        )
        .to_a
    end

    def selected_child_booking
      child_bookings.find { |child| child.id.to_s == @params[:child_booking_id].to_s } || booking
    end

    def selected_booking_guest
      booking.booking_guests.find { |record| record.id.to_s == @params[:booking_guest_id].to_s } ||
        booking.booking_guests.find(&:primary?) || booking.booking_guests.first
    end

    def selected_guest
      selected_booking_guest&.guest
    end

    def guest_details_mode
      selected_booking_guest&.primary? ? "edit_primary" : "edit_additional"
    end

    def guest_details_return_to
      return nil unless selected_booking_guest

      path_for(booking, tab: "guest_details", booking_guest_id: selected_booking_guest.id)
    end

    def guest_details_snapshots
      bg = selected_booking_guest
      g = selected_guest
      return {} unless bg && g

      {
        name: bg.name_snapshot.presence || g.name,
        email: bg.email_snapshot.presence || g.email,
        phone: bg.phone_snapshot.presence || g.phone,
        country: bg.country_snapshot.presence || g.country.presence || hotel.country,
        gender: bg.gender_snapshot.presence || g.gender,
        document_type: bg.document_type_snapshot.presence || g.document_type.presence || "ic",
        government_id: bg.government_id_snapshot.presence || g.government_id,
        date_of_birth: bg.date_of_birth_snapshot.presence || g.date_of_birth
      }
    end

    def guest_details_boat_times
      bg = selected_booking_guest
      return { boat_in: nil, boat_out: nil } unless bg

      tz = hotel.hotel_time_zone.presence || Time.zone.name
      {
        boat_in: bg.boat_in_at&.in_time_zone(tz)&.strftime("%Y-%m-%dT%H:%M"),
        boat_out: bg.boat_out_at&.in_time_zone(tz)&.strftime("%Y-%m-%dT%H:%M")
      }
    end

    def guest_details_boat_in_date
      split_boat_time(:boat_in)&.first
    end

    def guest_details_boat_in_time
      split_boat_time(:boat_in)&.last
    end

    def guest_details_boat_in_time_options
      boat_time_options(hotel.boat_in_times)
    end

    def guest_details_boat_out_date
      split_boat_time(:boat_out)&.first
    end

    def guest_details_boat_out_time
      split_boat_time(:boat_out)&.last
    end

    def guest_details_boat_out_time_options
      boat_time_options(hotel.boat_out_times)
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

    def can_manage_bookings?(user)
      booking_presenter.can_manage_bookings?(user)
    end

    def can_add_guests?(user)
      booking_presenter.can_add_guests?(user)
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

    def document_rows
      child_bookings.map do |child|
        room = child.booking_rooms.first
        DocumentRow.new(
          child,
          room_type_label_for(room),
          room&.room_number.presence || "Unassigned",
          document_guest_name(child),
          child.status == "completed"
        )
      end
    end

    def document_row_groups
      document_rows.group_by(&:room_type).sort_by { |room_type, _| room_type }
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
      return if booking.check_in.blank? || booking.check_out.blank?

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

    def nightly_rate_label(child = booking)
      row = room_rate_rows(child).find { |candidate| candidate.date == child.check_in.to_date }
      row&.nightly_rate || "—"
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

    def room_tree_rows
      booking.booking_rooms.map do |room|
        room_tree_row(room)
      end
    end

    def room_tree_groups
      booking.booking_rooms.group_by { |room| room_type_label(room) }.map do |room_type, rooms|
        TreeGroup.new(room_type, pluralize_count(rooms.size, "room"), rooms.map { |room| room_tree_row(room) }, nil)
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
            href: Rails.application.routes.url_helpers.hotel_booking_workspace_path(hotel, child, tab: active_tab, folio_id: folio.id)
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
        TreeRow.new(
          booking_guest.id,
          booking_guest.name_snapshot.presence || booking_guest.guest&.name.presence || booking.guest_name,
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
            booking_guest.name_snapshot.presence || booking_guest.guest&.name.presence || child.guest_name,
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

      [ TreeGroup.new("Requests", "Booking-level requests", request_rows, nil) ] + room_tree_groups
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
        TreeGroup.new("All Activity", "Full booking timeline", [ TreeRow.new("all", "All Activity", booking_reference, "audit", audit_row_active?("all", nil), nil) ], nil),
        TreeGroup.new("Rooms", pluralize_count(audit_room_rows.size, "room"), audit_room_rows, nil),
        TreeGroup.new("Folios", pluralize_count(audit_folio_rows.size, "folio"), audit_folio_rows, nil),
        TreeGroup.new("Guests", pluralize_count(guest_rows.size, "guest"), guest_rows, nil)
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

    def split_boat_time(key)
      guest_details_boat_times[key]&.split("T")
    end

    def boat_time_options(times)
      (times || []).sort.map do |t|
        t_obj = Time.zone.parse("2000-01-01 #{t}") rescue nil
        label = t_obj ? t_obj.strftime("%I:%M %p") : t
        [ label, t ]
      end
    end

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

    def group_summary_action(key, label, tone, offcanvas_variant, icon, eligible_statuses)
      target = child_bookings.find { |child| child.status.in?(eligible_statuses) }
      return unless target

      SummaryAction.new(key, label, tone, offcanvas_variant, icon, target)
    end

    def standalone_summary_action(key, label, tone, offcanvas_variant, icon)
      SummaryAction.new(key, label, tone, offcanvas_variant, icon, booking)
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
      TreeGroup.new(child_booking_label(child), child_booking_menu_description(child), rows, child.id)
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
      guest_name = primary_guest&.name_snapshot.presence || primary_guest&.guest&.name.presence || child.guest_name
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

    def room_type_label_for(room)
      return "Unassigned" if room.blank?

      room_type_label(room)
    end

    def document_guest_name(child)
      record = child.booking_guests.find(&:primary?) || child.booking_guests.first
      record&.name_snapshot.presence || record&.guest&.name.presence || child.guest_name
    end

    def room_type_label(room)
      room.room_type&.name.presence || room.room_type_snapshot.to_h["name"].presence || "Room type unavailable"
    end

    def pluralize_count(count, singular)
      "#{count} #{singular.pluralize(count)}"
    end

    def format_stay_date(value)
      return "—" if value.blank?

      value.in_time_zone(booking.hotel.hotel_time_zone).strftime("%d %b %Y")
    end

    def short_stay_range
      format_short_range(booking.check_in, booking.check_out)
    end

    def format_short_range(start_at, finish_at)
      return "Dates unavailable" if start_at.blank? || finish_at.blank?

      tz = hotel.hotel_time_zone
      start_local = start_at.in_time_zone(tz)
      finish_local = finish_at.in_time_zone(tz)

      if start_local.year == finish_local.year && start_local.month == finish_local.month
        "#{start_local.strftime('%-d')}–#{finish_local.strftime('%-d %b')}"
      else
        "#{start_local.strftime('%-d %b')} – #{finish_local.strftime('%-d %b')}"
      end
    end

    def group_room_count
      child_bookings.sum { |child| child.booking_rooms.sum { |room| room.quantity.to_i } }
    end

    def group_status_badge
      statuses = child_bookings.filter_map { |child| child.status.to_s.presence }
      return if statuses.empty?
      return status_badge(statuses.first) if statuses.uniq.one?
      return { label: "Cancelled", tone: "rose" } if statuses.all? { |status| status == "cancelled" }
      return { label: "Checked out", tone: "slate" } if statuses.all? { |status| status.in?(%w[completed cancelled]) }

      in_house_statuses = %w[checked_in review_due_out checkout_required]
      in_house_count = statuses.count { |status| status.in?(in_house_statuses) }
      return { label: "Partially in house", tone: "amber" } if in_house_count.positive? && in_house_count < statuses.size
      return { label: "Checkout due", tone: "orange" } if statuses.include?("checkout_required") && in_house_count == statuses.size
      return { label: "Due out", tone: "amber" } if statuses.include?("review_due_out") && in_house_count == statuses.size
      return { label: "In house", tone: "emerald" } if in_house_count == statuses.size

      { label: "Mixed statuses", tone: "amber" }
    end

    def format_summary_time(value)
      return "—" if value.blank?

      value.in_time_zone(hotel.hotel_time_zone).strftime("%Y/%m/%d %H:%M")
    end

    def distinct_child_dates(field)
      tz = hotel.hotel_time_zone
      child_bookings.filter_map { |child| child.public_send(field)&.in_time_zone(tz)&.to_date }.uniq.sort
    end

    def format_short_date(date)
      date.strftime("%-d %b")
    end

    def path_for(target_booking, **query)
      Rails.application.routes.url_helpers.hotel_booking_workspace_path(hotel, target_booking, query.compact)
    end

    def supported_tabs
      @supported_tabs ||= TABS + LEGACY_TABS
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
end
