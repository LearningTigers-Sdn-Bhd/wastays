# frozen_string_literal: true

module HotelPortal
  module Bookings
    class WorkspacePresenter
      RoomRow = Data.define(:room_number, :room_type)
      Tab = Data.define(:key, :label)
      TreeRow = Data.define(:id, :label, :description, :kind, :active, :href)
    FolioRailRow = Data.define(:id, :number, :payer_line, :status_badge, :outstanding, :active, :href)
    TreeGroup = Data.define(:label, :description, :rows, :booking_id, :add_href)
    RoomRateRow = Data.define(:booking_reference, :date, :room_type, :room, :rate_plan, :nightly_rate, :rate_missing)
    RoomRateRailRow = Data.define(:id, :rate_plan, :total_rate, :active, :href)
    RequestCard = Data.define(:id, :type, :title, :details, :room_label, :time_label, :status, :column, :record, :completed)
    RequestColumn = Data.define(:key, :label, :cards)
    BillingPartyRow = Data.define(:id, :kind, :label, :role, :description, :settlement, :folio_count, :folio_labels, :outstanding, :record)
    BillingRailRow = Data.define(:id, :label, :description, :active, :href)
    DocumentRow = Data.define(
      :key, :type, :number, :booking, :room, :payer, :currency, :amount,
      :status, :issued_at, :href, :context_type, :revision_actions
    ) do
      def available? = href.present?
      def history? = revision_actions.present?
    end
    DocumentSection = Data.define(:key, :title, :caption, :primary_heading, :type_heading, :party_heading, :amount_heading, :rows, :empty_message) do
      def single_currency?
        rows.filter_map { |row| row.currency.presence }.uniq.one?
      end
    end
    FolioWindowBillingPartyOption = Data.define(:id, :group, :label, :description, :record)
    SummaryAction = Data.define(:key, :label, :tone, :offcanvas_variant, :icon, :target_booking)
    TABS = [
      Tab.new("booking_details", "Overview"),
      Tab.new("folio_operations", "Folios"),
      Tab.new("security_deposits", "Deposits"),
      Tab.new("billing_preferences", "Billing"),
      Tab.new("documents", "Documents"),
      Tab.new("guest_details", "Guests"),
      Tab.new("room_and_rate", "Room & Rate"),
      Tab.new("housekeeping_requests", "Requests"),
      Tab.new("audit_trails", "Audit Trail")
    ].freeze
    LEGACY_TABS = [ Tab.new("source_details", "Source Details") ].freeze
    ALERT_ACTIONS = %w[change_rate].freeze
    ENTITY_TABS = %w[folio_operations billing_preferences guest_details room_and_rate].freeze
    DOCUMENT_SECTION_BY_TYPE = {
      "Folio invoice" => :invoices,
      "AR invoice" => :invoices,
      "Folio ledger" => :ledgers,
      "Payment receipt" => :receipts,
      "Deposit receipt" => :receipts,
      "Group deposit receipt" => :receipts,
      "AR payment receipt" => :receipts,
      "Registration card" => :utility,
      "Group statement" => :statements
    }.freeze
    DOCUMENT_TYPE_ORDER = DOCUMENT_SECTION_BY_TYPE.keys.each_with_index.to_h.freeze
    GUEST_FORM_ATTRIBUTES = %i[name email phone country gender document_type government_id date_of_birth].freeze
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
      "no_show" => "No-show",
      "voided" => "Voided"
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
      "no_show" => "rose",
      "voided" => "rose"
    }.freeze

    attr_reader :booking

    attr_reader :hotel, :booking_presenter, :folio_show

    def initialize(booking, params: {}, hotel: booking.hotel, user: nil, booking_presenter: nil, folio_show: nil, guest_form: nil, booking_guest_form: nil)
      @booking = booking
      @params = params
      @hotel = hotel
      @user = user
      @booking_presenter = booking_presenter || BookingPresenter.new(booking, hotel)
      @folio_show = folio_show
      @guest_form = guest_form
      @booking_guest_form = booking_guest_form
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
      group_context_enabled? ? group_booking_number : booking_number
    end

    # The action sheet leads with the human name and demotes the number, the inverse of
    # the workspace header. Kept separate so the two can diverge deliberately.
    def summary_title
      group_context_enabled? ? group_booking.name : primary_guest_name.presence || "Guest unavailable"
    end

    # Group names default to the organizer's own name, so the group name is dropped when it
    # only repeats the organizer. A group named independently keeps both.
    def header_party_line
      return primary_guest_name.presence || "Guest unavailable" unless group_context_enabled?

      name = group_booking.name.presence
      organizer = group_booking.organizer_guest&.name.presence
      return name || "Group booking" if organizer.blank?

      organizer_line = "Organizer — #{organizer}"
      return organizer_line if name.blank? || name.downcase.include?(organizer.downcase)

      "#{name} · #{organizer_line}"
    end

    # Per-room status breakdown behind the aggregated group badge. Ordered by
    # group_position through child_bookings.
    def header_status_rows
      return [] unless group_context_enabled?

      child_bookings.map do |child|
        room = child.booking_rooms.first
        {
          room: room&.room_number.presence ? "Room #{room.room_number}" : "Unassigned",
          room_type: room_type_label_for(room),
          badge: presentable_badge(status_badge(child.status))
        }
      end
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
      return unless stay_dates_vary? || group_dates_incomplete?

      arrivals = group_arrival_dates.map { |date| format_short_date(date) }
      departures = group_departure_dates.map { |date| format_short_date(date) }
      clauses = []
      clauses << "Arrivals occur on #{arrivals.to_sentence}." if arrivals.any?
      clauses << "Departures occur on #{departures.to_sentence}." if departures.any?
      clauses << "Some stay dates are unavailable." if group_dates_incomplete?
      clauses.join(" ")
    end

    def header_status_badge
      presentable_badge(group_context_enabled? ? group_status_badge : status_badge(booking.status))
    end

    def presentable_badge(badge)
      return if badge.blank?

      { label: badge[:label], variant: BADGE_VARIANTS.fetch(badge[:tone], :neutral) }
    end

    def header_outstanding_balance
      money(group_context_enabled? ? group_total_balance : total_balance)
    end

    def documents = @documents ||= build_documents

    def document_context_bookings
      @document_context_bookings ||= if booking.group_booking_id?
        hotel.bookings.where(group_booking_id: booking.group_booking_id).order(:group_position, :id).to_a
      else
        [ booking ]
      end
    end

    def quick_documents
      @quick_documents ||= build_quick_documents
    end

    def document_sections
      grouped = documents.group_by { |document| DOCUMENT_SECTION_BY_TYPE.fetch(document.type) }
      invoices = grouped.fetch(:invoices, [])
      ledgers = grouped.fetch(:ledgers, [])
      receipts = grouped.fetch(:receipts, [])
      [
        DocumentSection.new(:invoices, "Invoices", "Booking invoices", "Invoice", "Folio type", "Payer", document_amount_heading("Amount", invoices), invoices, "No invoices are available."),
        DocumentSection.new(:ledgers, "Folio ledgers", "Folio ledgers", "Folio", "Folio type", "Payer", document_amount_heading("Balance", ledgers), ledgers, "No folio ledgers are available."),
        DocumentSection.new(:receipts, "Receipts", "Payment and deposit receipts", "Receipt", "Receipt type", "Payer", document_amount_heading("Amount", receipts), receipts, "No receipts have been issued."),
        DocumentSection.new(:utility, "Utility", "Registration cards", "Document", "Document type", "Subject", nil, grouped.fetch(:utility, []), "No utility documents are available."),
        DocumentSection.new(:statements, "Statements", "Consolidated group accounts receivable statements", "Statement", "Statement type", "Payer", nil, grouped.fetch(:statements, []), "No consolidated statements are available.")
      ]
    end

    def document_amount_heading(label, rows)
      currencies = rows.filter_map { |row| row.currency.presence }.uniq
      currencies.one? ? "#{label} (#{currencies.first})" : label
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

    def summary_actions(include_void: false)
      actions = group_context_enabled? ? group_summary_actions : standalone_summary_actions
      return actions unless include_void

      target = group_context_enabled? ? child_bookings.find { |child| child.status != "voided" } : booking
      return actions if target.nil? || target.status == "voided"

      actions + [ SummaryAction.new(:void, "Void booking", :danger, "right", "circle-slash", target) ]
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
      return path_for(booking, tab: tab_key) if tab_key.to_s == "documents"

      entity_tab = tab_key.to_s.in?(ENTITY_TABS)
      scope = if !entity_tab && @params[:scope].to_s == "booking"
        "booking"
      elsif !entity_tab && group_overview?
        "group"
      end
      path_for(booking, tab: tab_key, scope: scope)
    end

    def close_drawer_path
      path_for(
        booking,
        tab: active_tab,
        scope: group_overview? ? "group" : nil,
        child_booking_id: (selected_child_booking.id if active_tab.in?(%w[billing_preferences room_and_rate])),
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
        active_tab == "room_and_rate" ? selected_child_booking : booking,
        tab: active_tab,
        scope: group_overview? ? "group" : nil,
        child_booking_id: (selected_child_booking.id if active_tab == "room_and_rate"),
        folio_id: @params[:folio_id].presence,
        booking_guest_id: @params[:booking_guest_id].presence,
        billing_scope: @params[:billing_scope].presence,
        folio_routing_rule_id: @params[:folio_routing_rule_id].presence
      )
    end

    def left_rail_mode
      case active_tab
      when "folio_operations" then "folio_tree"
      when "guest_details" then "guest_tree"
      when "billing_preferences" then "billing_tree"
      when "room_and_rate" then "room_rate_tree"
      end
    end

    # Labels the mobile entity bar, which stands in for the rail below `xl`.
    def selected_entity_label
      child = selected_child_booking

      case active_tab
      when "folio_operations"
        [ selected_folio&.display_name, child_booking_label(child) ].compact_blank.join(" · ")
      when "guest_details"
        [ booking_guest_name(selected_booking_guest, child), child_booking_label(child) ].compact_blank.join(" · ")
      when "billing_preferences"
        [ child_booking_label(child), child_booking_room_type(child) ].compact_blank.join(" · ")
      when "room_and_rate"
        [ child_booking_label(child), child_booking_room_type(child) ].compact_blank.join(" · ")
      end
    end

    def entity_selector_label
      case active_tab
      when "folio_operations" then "Choose Folio"
      when "guest_details" then "Choose Guest"
      when "billing_preferences" then "Choose Room"
      when "room_and_rate" then "Choose Room"
      end
    end

    def layout_mode
      active_tab.in?(ENTITY_TABS) ? "entity" : "standard"
    end

    def show_left_rail?
      left_rail_mode.present?
    end

    def show_right_drawer?
      drawer_open? && active_tab != "guest_details"
    end

    def drawer
      @params[:drawer].to_s.presence
    end

    def drawer_open?
      false
    end

    def group_booking?
      booking.group_booking?
    end

    def group_context_enabled?
      booking.group_booking_id.present?
    end

    def group_overview?
      return false unless group_context_enabled?
      return false if active_tab.in?(ENTITY_TABS)

      scope = @params[:scope].to_s
      scope == "group" || (active_tab == "booking_details" && scope.blank?)
    end

    def audit_selected_booking
      return booking unless group_context_enabled?

      child_bookings.find { |child| child.id.to_s == @params[:child_booking_id].to_s } ||
        (booking if @params[:scope].to_s == "booking")
    end

    def audit_group_scope?
      group_context_enabled? && audit_selected_booking.nil?
    end

    def audit_booking_options
      options = child_bookings.map { |child| [ audit_booking_option_label(child), child.id.to_s ] }
      group_context_enabled? ? [ [ "All bookings", "" ], *options ] : options
    end

    def group_booking
      booking.group_booking
    end

    def child_bookings
      return [ booking ] unless group_context_enabled?

      @child_bookings ||= begin
        bookings = booking.group_booking.bookings
        records = if bookings.loaded?
          bookings.to_a
        else
          bookings
            .where(hotel_id: hotel.id)
            .includes(
              :hotel, :housekeeping_requests, :complaint_requests, :folio_operation_logs,
              { deposits: { deposit_movements: [ :booking_folio, :folio_transaction ] } },
              booking_folios: [ :folio_transactions, :folio_forecasted_charges, { booking_billing_party: :booking_guest, hotel_corporate_account: :corporate_account } ],
              booking_rooms: [ :room_type, :rate_plan ],
              booking_guests: :guest,
              booking_billing_parties: [ :billing_terms, :booking_folios, { booking_guest: :guest }, { hotel_corporate_account: :corporate_account } ]
            )
            .to_a
        end
        records.select { |child| child.hotel_id == hotel.id }
      end
    end

    def selected_child_booking
      explicit_child = child_bookings.find { |child| child.id.to_s == @params[:child_booking_id].to_s }
      return explicit_child if explicit_child
      return booking unless active_tab.in?(ENTITY_TABS)

      explicit_entity_child_booking || child_bookings.first || booking
    end

    def selected_booking_guest
      guests = ordered_booking_guests(selected_child_booking)
      guests.find { |record| record.id.to_s == @params[:booking_guest_id].to_s } ||
        guests.find(&:primary?) || guests.first
    end

    def selected_guest
      @guest_form || selected_booking_guest&.guest
    end

    def guest_details_return_to
      return nil unless selected_booking_guest

      path_for(selected_child_booking, tab: "guest_details", booking_guest_id: selected_booking_guest.id)
    end

    def guest_details_snapshots
      bg = selected_booking_guest
      g = selected_guest
      return {} unless bg && g

      return GUEST_FORM_ATTRIBUTES.to_h { |attribute| [ attribute, g.public_send(attribute) ] } if @guest_form

      # The three encrypted columns exist on both the stay snapshot and the
      # reusable profile, so an unreadable value on either side falls through
      # rather than raising on the way into the form.
      {
        name: bg.name_snapshot.presence || g.name,
        email: safe_encrypted_value(bg, :email_snapshot) || safe_encrypted_value(g, :email),
        phone: safe_encrypted_value(bg, :phone_snapshot) || safe_encrypted_value(g, :phone),
        country: bg.country_snapshot.presence || g.country.presence || hotel.country,
        gender: bg.gender_snapshot.presence || g.gender,
        document_type: bg.document_type_snapshot.presence || g.document_type.presence || "ic",
        government_id: safe_encrypted_value(bg, :government_id_snapshot) || safe_encrypted_value(g, :government_id),
        date_of_birth: bg.date_of_birth_snapshot.presence || g.date_of_birth
      }
    end

    # The range picker carries both boat times in one "start/end" field, while the
    # record keeps two columns. Returns "" rather than "/" when neither is set, so
    # the picker shows its placeholder instead of an empty range.
    def guest_details_boat_range
      bg = @booking_guest_form || selected_booking_guest
      return "" unless bg

      tz = hotel.hotel_time_zone.presence || Time.zone.name
      bounds = [ bg.boat_in_at, bg.boat_out_at ].map { |time| time&.in_time_zone(tz)&.strftime("%Y-%m-%dT%H:%M") }
      return "" if bounds.none?

      bounds.join("/")
    end

    # The record validates the two columns, so the combined field has to be told
    # about their errors or an invalid range would only appear in the summary.
    def guest_details_boat_range_error
      record = guest_details_booking_guest_form
      return unless record.respond_to?(:errors)

      (record.errors[:boat_out_at] + record.errors[:boat_in_at]).first
    end

    def guest_details_booking_guest_form
      @booking_guest_form || selected_booking_guest
    end

    def guest_details_errors
      [ selected_guest, guest_details_booking_guest_form ].compact.flat_map { |record| record.errors.full_messages }.uniq
    end

    def can_manage_bookings?(user)
      booking_presenter.can_manage_bookings?(user)
    end

    def can_add_guests?(user)
      booking_presenter.can_add_guests?(user)
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
      path_for(selected_child_booking, **{ tab: "billing_preferences", child_booking_id: selected_child_booking.id }.merge(options).compact)
    end

    def group_overview_path
      path_for(booking, tab: active_tab, scope: "group")
    end

    def security_deposit_booking
      selected_child_booking
    end

    def security_deposits
      security_deposit_booking.deposits.select(&:kind_security?).sort_by { |deposit| [ deposit.received_at, deposit.id ] }.reverse
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
      deposit_rows.select { |row| row[:deposit].kind_security? && row[:deposit].booking_id == security_deposit_booking.id }
    end

    def unified_deposits
      records = if group_context_enabled?
        group_booking.deposits.to_a + child_bookings.flat_map { |child| child.deposits.to_a }
      else
        booking.deposits.to_a
      end
      records.uniq.sort_by { |deposit| [ deposit.received_at, deposit.id ] }.reverse
    end

    def deposit_rows
      unified_deposits.map do |deposit|
        {
          deposit: deposit,
          owner: deposit.group_booking_id.present? ? "Group" : "Booking #{deposit.booking.formatted_reservation_number}",
          kind: deposit.kind.humanize,
          status: deposit.status.humanize,
          currency: deposit.currency,
          amount: deposit_amount(deposit.amount),
          applied: deposit_amount(deposit.applied_amount),
          returned: deposit_amount(deposit.returned_amount),
          available: deposit_amount(deposit.available_amount),
          method: deposit.payment_method.humanize,
          reference: deposit.external_reference.presence || "—",
          received_at: time_label(deposit.received_at),
          staff: deposit.received_by&.name.presence || "—"
        }
      end
    end

    def total_deposit_available(currency: nil)
      deposits = currency.present? ? unified_deposits.select { |deposit| deposit.currency == currency } : unified_deposits
      deposits.sum(&:available_amount)
    end

    def deposit_amount(amount)
      format("%.2f", amount.to_d)
    end

    def deposit_application_rows
      unified_deposits.flat_map do |deposit|
        movements = deposit.deposit_movements.to_a
        reversed_ids = movements.filter_map { |movement| movement.reversal_of_id if movement.movement_type == "reverse" }.to_set
        movements.filter_map do |movement|
          next unless movement.movement_type == "apply" && !reversed_ids.include?(movement.id)

          folio = movement.booking_folio
          {
            movement: movement,
            owner: deposit.group_booking_id.present? ? "Group" : "Booking #{deposit.booking.formatted_reservation_number}",
            folio: folio ? "#{folio.booking.formatted_reservation_number} · #{folio.display_with_payer}" : "Folio unavailable",
            amount: money_for(deposit.booking || folio&.booking || selected_child_booking, movement.amount),
            occurred_at: time_label(movement.occurred_at)
          }
        end
      end
    end

    def eligible_deposit_folios(deposit)
      candidates = deposit.booking_id.present? ? deposit.booking.booking_folios : child_bookings.flat_map { |child| child.booking_folios.to_a }
      candidates.select { |folio| folio.open? && deposit.eligible_folio?(folio) }
    end

    def deposit_folio_options(deposit)
      eligible_deposit_folios(deposit).map { |folio| { label: "#{folio.booking.formatted_reservation_number} · #{folio.display_with_payer}", value: folio.id } }
    end

    def deposit_owner_options
      options = child_bookings.map { |child| { label: "Booking #{child.formatted_reservation_number}", value: "booking:#{child.id}" } }
      group_context_enabled? ? [ { label: "Group #{group_booking.formatted_reservation_number}", value: "group:#{group_booking.id}" }, *options ] : options
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
        deposits = child.deposits.select(&:kind_security?)
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

    def group_room_rate_rows
      child_bookings.flat_map { |child| room_rate_rows(child) }
    end

    def group_room_rate_issues
      child_bookings.filter_map do |child|
        message = room_rate_empty_message(child)
        { booking_reference: child_booking_number(child), message: message } if message.present?
      end
    end

    # One row per booking for the Overview stay table: a single booking yields one row, a
    # group yields one per child in group_position order. Rate plan is deliberately absent —
    # Room & Rate owns it per night.
    def stay_rows
      child_bookings.map do |child|
        room = child.booking_rooms.first
        {
          booking: child,
          booking_number: child_booking_number(child),
          guest: child.booking_guests.find(&:primary?)&.guest&.name.presence || child.guest_name,
          room_type: room ? room_type_label(room) : "Room type unavailable",
          room: room&.room_number.presence || "Unassigned",
          arrival: format_stay_date(child.check_in),
          departure: format_stay_date(child.check_out),
          nights: nights_between(child.check_in, child.check_out),
          pax: pax_label(child),
          status: presentable_badge(status_badge(child.status)),
          balance: money_for(child, child.booking_folios.sum { |folio| folio.projected_outstanding_balance.to_d })
        }
      end
    end

    def stay_rows_total_balance
      money(group_context_enabled? ? group_total_balance : total_balance)
    end

    # One row per billing identity, not per folio and not per booking. Folios are resolved to
    # an identity (see billing_identity_for) and merged across the group, so a group billed
    # entirely to one company reads as a single row carrying the whole amount.
    def financial_party_rows
      buckets = {}

      child_bookings.each do |child|
        child.booking_folios.each do |folio|
          identity = billing_identity_for(folio, child)
          bucket = buckets[identity[:key]] ||= {
            name: identity[:name], kind: identity[:kind], sort: identity[:sort],
            folio_count: 0, charged: 0.to_d, paid: 0.to_d, outstanding: 0.to_d
          }
          bucket[:folio_count] += 1
          bucket[:charged] += folio.total_charges.to_d
          bucket[:paid] += folio.total_payments.to_d
          bucket[:outstanding] += folio.projected_outstanding_balance.to_d
        end
      end

      buckets.values.sort_by { |row| [ row[:sort], row[:name].to_s ] }.map do |row|
        row.merge(
          charged: money(row[:charged]),
          paid: money(row[:paid]),
          outstanding: money(row[:outstanding])
        )
      end
    end

    # Identifiers for the reservation as a whole. SplitLegacyMultiRoom promotes external and
    # channel references to the group and nulls them on children, so in group context these
    # read from the group; a standalone booking carries its own.
    def reservation_reference_pairs
      pairs =
        if group_context_enabled?
          [
            [ "External Reference", group_booking.external_reference ],
            [ "Channel Manager", group_booking.channel_manager_reference ],
            [ "Organizer", group_booking.organizer_guest&.name ]
          ]
        else
          [
            [ "External Reference", booking.external_reference ],
            [ "Channel Manager", booking.channel_manager_reference ]
          ]
        end

      pairs.map { |label, value| [ label, value.presence || "—" ] }
    end

    # Identifiers for one room-booking: one row for a standalone booking, one per child for a
    # group, led by the group's own row so the four shared columns line up for comparison.
    # Folio account and guest registration have no group equivalent and read as em dashes.
    def booking_reference_rows
      rows = child_bookings.map do |child|
        {
          booking: child,
          booking_number: child_booking_number(child),
          confirmation_code: child.confirmation_token.presence || "—",
          receipt_number: child.formatted_receipt_number.presence || "—",
          source: format_source(child.source),
          invoice_number: child.formatted_invoice_number.presence || "—",
          folio_account: child.folio_account_reference_display.presence || "—",
          guest_registration: child.formatted_guest_registration_number.presence || "—"
        }
      end

      return rows unless group_context_enabled?

      rows.unshift(
        group: true,
        booking_number: group_booking_number,
        confirmation_code: group_booking.confirmation_token.presence || "—",
        receipt_number: group_booking.formatted_receipt_number.presence || "—",
        source: format_source(group_booking.source),
        invoice_number: "—",
        folio_account: "—",
        guest_registration: "—"
      )
    end

    def format_source(value)
      value.to_s.presence&.tr("_", " ")&.titleize || "—"
    end

    def financial_party_totals
      folios = child_bookings.flat_map(&:booking_folios)

      {
        charged: money(folios.sum { |folio| folio.total_charges.to_d }),
        paid: money(folios.sum { |folio| folio.total_payments.to_d }),
        outstanding: money(folios.sum { |folio| folio.projected_outstanding_balance.to_d })
      }
    end

    def nights_between(check_in, check_out)
      return "—" if check_in.blank? || check_out.blank?

      (check_out.to_date - check_in.to_date).to_i
    end

    def pax_label(child)
      adults = child.adults.to_i
      children = child.children.to_i
      children.positive? ? "#{adults}A · #{children}C" : "#{adults}A"
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
        terms = party.billing_terms
        BillingPartyRow.new(
          party.id,
          billing_party_kind_label(party),
          safe_text(party.display_name, fallback: "Billing party"),
          billing_party_role_label(party),
          billing_party_description(party),
          terms&.settlement_type.to_s.presence&.humanize || "Not set",
          party_folios.size,
          party_folios.map(&:display_name),
          party_folios.sum { |folio| folio.projected_outstanding_balance.to_d },
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
          row.record.company? ? "Corporate Accounts" : "Guests",
          row.label,
          [ row.role, row.description ].compact_blank.join(" · "),
          row.record
        )
      end
    end

    def folio_window_billing_party_option_groups
      folio_window_billing_party_options.group_by(&:group)
    end

    def can_manage_folio_windows?(user)
      user.has_permission?("manage_folio_windows", hotel: hotel)
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

    def billing_currency
      selected_child_booking.currency.presence || hotel.default_currency.presence || "MYR"
    end

    # A standalone booking is a group of one, so both rails render the same shape.
    def folio_tree_groups
      @folio_tree_groups ||= child_bookings.map do |child|
        rows = ordered_booking_folios(child).map do |folio|
          folio_tree_row(
            folio,
            active: child.id == selected_child_booking.id && folio_operations_folio_active?(folio)
          ).with(
            href: path_for(child, tab: active_tab, folio_id: folio.id)
          )
        end

        entity_tree_group(child, rows, add_folio_path_for(child))
      end
    end

    def guest_tree_groups
      @guest_tree_groups ||= child_bookings.map do |child|
        rows = ordered_booking_guests(child).map do |booking_guest|
          TreeRow.new(
            booking_guest.id,
            booking_guest_name(booking_guest, child),
            booking_guest.primary? ? "Primary guest" : "Additional guest",
            "guest",
            child.id == selected_child_booking.id && selected_booking_guest&.id == booking_guest.id,
            path_for(child, tab: active_tab, booking_guest_id: booking_guest.id)
          )
        end

        entity_tree_group(child, rows, add_guest_path_for(child))
      end
    end

    def billing_tree_groups
      @billing_tree_groups ||= child_bookings.map do |child|
        parties = ordered_billing_parties(child)
        guests = parties.count(&:guest?)
        accounts = parties.count(&:company?)
        description = [ pluralize_count(guests, "guest"), pluralize_count(accounts, "account") ].reject { |label| label.start_with?("0 ") }.join(" · ")
        description = "No payers yet" if description.blank?
        row = BillingRailRow.new(
          "booking-#{child.id}",
          pluralize_count(parties.size, "payer"),
          description,
          child.id == selected_child_booking.id,
          path_for(child, tab: active_tab, child_booking_id: child.id)
        )

        entity_tree_group(child, [ row ], nil)
      end
    end

    def room_rate_tree_groups
      @room_rate_tree_groups ||= child_bookings.map do |child|
        room = child.booking_rooms.first
        row = RoomRateRailRow.new(
          room&.id || "booking-#{child.id}",
          room&.rate_plan&.name.presence || (room ? "Standard" : "Not available"),
          room ? money_for(child, room.subtotal) : "—",
          child.id == selected_child_booking.id,
          path_for(child, tab: active_tab, child_booking_id: child.id)
        )

        entity_tree_group(child, [ row ], nil)
      end
    end

    def selected_folio
      return unless active_tab == "folio_operations"

      selected_folios = ordered_booking_folios(selected_child_booking)
      explicit_id = @params[:folio_id].presence || @params[:active_folio_id].presence
      selected_folios.find { |folio| folio.id.to_s == explicit_id.to_s } ||
        selected_folios.find(&:is_primary?) || selected_folios.first
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

    def build_quick_documents
      quick_folios = hotel.booking_folios
        .where(booking_id: booking.id)
        .includes(
          :booking_room,
          { invoice: :revisions },
          { booking: [ { booking_rooms: :room_type }, { booking_guests: :guest } ] },
          { booking_billing_party: [ { booking_guest: :guest }, { hotel_corporate_account: :corporate_account } ] },
          { hotel_corporate_account: :corporate_account }
        )
        .order(is_primary: :desc, folio_sequence: :asc, id: :asc)
        .to_a
      @document_folios_by_id = quick_folios.index_by(&:id)
      load_document_transaction_totals

      transaction_scope = FolioTransaction.where(booking_folio_id: @document_folios_by_id.keys)
      receipt_rows = Receipt
        .where(hotel_id: hotel.id, folio_transaction_id: transaction_scope.select(:id))
        .includes(folio_transaction: { booking_folio: :booking })
        .map do |receipt|
          folio = receipt.folio_transaction.booking_folio
          document_receipt_row(receipt, type: "Payment receipt", child: booking, room: document_room_label(folio))
        end
      receipt_rows.concat(
        Deposit.where(hotel_id: hotel.id, booking_id: booking.id).includes(:receipt).filter_map do |deposit|
          next unless deposit.receipt

          document_receipt_row(deposit.receipt, type: "Deposit receipt", child: booking, room: document_booking_room_label(booking))
        end
      )
      card = booking.guest_registration_card

      {
        invoice: quick_folios.filter_map { |folio| document_folio_invoice_row(folio) }.find(&:available?),
        ledger: quick_folios.map { |folio| document_ledger_row(folio) }.find(&:available?),
        receipt: receipt_rows.select(&:available?).max_by(&:issued_at),
        registration_card: (document_registration_card_row(booking, card) if card && (document_permission?("manage_bookings") || document_permission?("view_reports")))
      }
    end

    def build_documents
      load_document_records
      rows = document_folio_invoice_rows + document_ar_invoice_rows + document_ledger_rows +
        document_receipt_rows + document_registration_card_rows + document_statement_rows
      rows.sort_by do |row|
        [ @document_booking_positions.fetch(row.booking, [ -1, 0 ]), DOCUMENT_TYPE_ORDER.fetch(row.type), row.issued_at || Time.zone.at(0), row.key ]
      end
    end

    def load_document_records
      ids = if booking.group_booking_id?
        hotel.bookings.where(group_booking_id: booking.group_booking_id).pluck(:id)
      else
        [ booking.id ]
      end

      @document_bookings = hotel.bookings
        .where(id: ids)
        .includes(
          :guest_registration_card,
          { booking_rooms: :room_type },
          { booking_guests: :guest },
          booking_folios: [
            :booking_room,
            { invoice: :revisions },
            { ar_invoice: { hotel_corporate_account: :corporate_account } },
            { booking_billing_party: [ { booking_guest: :guest }, { hotel_corporate_account: :corporate_account } ] },
            { hotel_corporate_account: :corporate_account }
          ]
        )
        .order(:group_position, :id)
        .to_a
      @document_booking_positions = @document_bookings.to_h do |child|
        [ document_booking_label(child), [ child.group_position || 0, child.id ] ]
      end
      @document_folios = @document_bookings.flat_map(&:booking_folios)
      @document_folios_by_id = @document_folios.index_by(&:id)
      load_document_transaction_totals
      load_document_receipts
    end

    def load_document_transaction_totals
      totals = FolioTransaction
        .where(booking_folio_id: @document_folios_by_id.keys)
        .group(:booking_folio_id, :transaction_type)
        .sum(:amount)
      @document_folio_totals = Hash.new { |hash, key| hash[key] = Hash.new(0.to_d) }
      totals.each { |(folio_id, type), amount| @document_folio_totals[folio_id][type] = amount.to_d }
    end

    def load_document_receipts
      transaction_scope = FolioTransaction.where(booking_folio_id: @document_folios_by_id.keys)
      @document_folio_receipts = Receipt
        .where(hotel_id: hotel.id, folio_transaction_id: transaction_scope.select(:id))
        .includes(folio_transaction: :booking_folio)
        .to_a

      booking_deposits = Deposit.where(hotel_id: hotel.id, booking_id: @document_bookings.map(&:id)).includes(:receipt).to_a
      group_deposits = if booking.group_booking_id?
        Deposit.where(hotel_id: hotel.id, group_booking_id: booking.group_booking_id).includes(:receipt).to_a
      else
        []
      end
      @document_deposits = booking_deposits + group_deposits

      @document_ar_invoices = @document_folios.filter_map(&:ar_invoice)
      @document_ar_invoices_by_id = @document_ar_invoices.index_by(&:id)
      payment_ids = ArPaymentAllocation.where(ar_invoice_id: @document_ar_invoices.map(&:id)).select(:ar_payment_id)
      @document_ar_receipts = Receipt.where(hotel_id: hotel.id, ar_payment_id: payment_ids).includes(:ar_payment).to_a
      pairs = ArPaymentAllocation
        .where(ar_invoice_id: @document_ar_invoices.map(&:id), ar_payment_id: @document_ar_receipts.map(&:ar_payment_id))
        .pluck(:ar_payment_id, :ar_invoice_id)
      @document_ar_invoice_ids_by_payment = pairs.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(payment_id, invoice_id), grouped|
        grouped[payment_id] << invoice_id
      end
    end

    def document_folio_invoice_rows
      @document_folios.filter_map { |folio| document_folio_invoice_row(folio) }
    end

    def document_folio_invoice_row(folio)
      invoice = folio.invoice
      return unless invoice&.kind_settled?

      revision = invoice.current_revision
      return unless revision

      snapshot = revision.snapshot.to_h.deep_stringify_keys
      DocumentRow.new(
        key: "folio-invoice-#{invoice.id}",
        type: "Folio invoice",
        number: revision.document_reference,
        booking: document_booking_label(folio.booking),
        room: document_room_label(folio),
        payer: document_invoice_payer(snapshot, folio),
        currency: snapshot.dig("totals", "currency").presence || folio.currency,
        amount: document_invoice_amount(snapshot, folio),
        status: invoice.state.humanize,
        issued_at: revision.issued_at,
        href: (routes.hotel_folio_invoice_path(hotel, folio) if invoice.finalized? && folio.closed?),
        context_type: folio.folio_type.humanize,
        revision_actions: document_revision_actions(folio, invoice)
      )
    end

    def document_revision_actions(folio, invoice)
      return [] unless document_permission?("view_audit_logs")
      return [] unless invoice.revisions.many?

      invoice.revisions.reject { |revision| invoice.finalized? && revision.revision_number == invoice.current_revision_number }.map do |revision|
        {
          label: revision.document_reference,
          href: routes.hotel_folio_invoice_revision_path(hotel, folio, revision.revision_number)
        }
      end
    end

    def document_ar_invoice_rows
      return [] unless document_permission?("view_reports")

      @document_ar_invoices.map do |invoice|
        folio = invoice.booking_folio
        DocumentRow.new(
          key: "ar-invoice-#{invoice.id}",
          type: "AR invoice",
          number: invoice.formatted_invoice_number,
          booking: document_booking_label(folio.booking),
          room: document_room_label(folio),
          payer: invoice.corporate_account.name,
          currency: invoice.currency,
          amount: invoice.amount,
          status: invoice.status.humanize,
          issued_at: invoice.issued_on&.in_time_zone,
          href: routes.pdf_hotel_ar_invoice_path(hotel, invoice),
          context_type: folio.folio_type.humanize,
          revision_actions: []
        )
      end
    end

    def document_ledger_rows
      @document_folios.map { |folio| document_ledger_row(folio) }
    end

    def document_ledger_row(folio)
      DocumentRow.new(
        key: "folio-ledger-#{folio.id}",
        type: "Folio ledger",
        number: folio.folio_reference_display,
        booking: document_booking_label(folio.booking),
        room: document_room_label(folio),
        payer: document_folio_payer(folio),
        currency: folio.currency,
        amount: document_folio_balance(folio),
        status: folio.status.humanize,
        issued_at: folio.closed_at || folio.opened_at,
        href: routes.hotel_folio_ledger_path(hotel, folio, format: :pdf),
        context_type: folio.folio_type.humanize,
        revision_actions: []
      )
    end

    def document_receipt_rows
      rows = @document_folio_receipts.map do |receipt|
        folio = receipt.folio_transaction.booking_folio
        document_receipt_row(receipt, type: "Payment receipt", child: folio.booking, room: document_room_label(folio))
      end
      rows.concat(@document_deposits.filter_map do |deposit|
        next unless deposit.receipt

        child = deposit.booking
        type = deposit.group_booking_id? ? "Group deposit receipt" : "Deposit receipt"
        document_receipt_row(
          deposit.receipt,
          type:,
          child:,
          room: child ? document_booking_room_label(child) : "Group"
        )
      end)
      rows.concat(document_ar_receipt_rows) if document_permission?("view_reports")
      rows
    end

    def document_ar_receipt_rows
      @document_ar_receipts.filter_map do |receipt|
        invoices = @document_ar_invoice_ids_by_payment[receipt.ar_payment_id]
          .filter_map { |id| @document_ar_invoices_by_id[id] }
        next if invoices.empty?

        child = invoices.one? ? invoices.first.booking : nil
        room = invoices.one? ? document_room_label(invoices.first.booking_folio) : "Multiple rooms"
        payer = invoices.map { |invoice| invoice.corporate_account.name }.uniq.to_sentence
        document_receipt_row(receipt, type: "AR payment receipt", child:, room:, payer:)
      end
    end

    def document_receipt_row(receipt, type:, child:, room:, payer: nil)
      DocumentRow.new(
        key: "#{type.parameterize}-#{receipt.id}",
        type:,
        number: receipt.public_number,
        booking: child ? document_booking_label(child) : document_group_label,
        room:,
        payer: payer || receipt.payer_snapshot.to_h.stringify_keys["name"].presence || "Payer unavailable",
        currency: receipt.currency,
        amount: receipt.amount,
        status: receipt.status.humanize,
        issued_at: receipt.issued_at,
        href: routes.receipt_path(receipt.access_token),
        context_type: type,
        revision_actions: []
      )
    end

    def document_registration_card_rows
      return [] unless document_permission?("manage_bookings") || document_permission?("view_reports")

      @document_bookings.filter_map do |child|
        card = child.guest_registration_card
        next unless card

        document_registration_card_row(child, card)
      end
    end

    def document_registration_card_row(child, card)
      DocumentRow.new(
        key: "registration-card-#{card.id}",
        type: "Registration card",
        number: child.guest_registration_card_number_display.presence || "Registration card",
        booking: document_booking_label(child),
        room: document_booking_room_label(child),
        payer: document_primary_guest_name(child),
        currency: nil,
        amount: nil,
        status: card.status.humanize,
        issued_at: card.created_at,
        href: routes.hotel_booking_guest_registration_card_path(hotel, child),
        context_type: "Registration card",
        revision_actions: []
      )
    end

    def document_statement_rows
      return [] unless booking.group_booking_id? && document_permission?("view_reports")

      @document_ar_invoices.reject(&:void?).group_by { |invoice| [ invoice.hotel_corporate_account, invoice.currency ] }.map do |(account, currency), invoices|
        DocumentRow.new(
          key: "group-statement-#{account.id}-#{currency}",
          type: "Group statement",
          number: "#{account.corporate_account.name} · #{currency}",
          booking: document_group_label,
          room: "All rooms",
          payer: account.corporate_account.name,
          currency:,
          amount: nil,
          status: "Available",
          issued_at: invoices.map(&:issued_on).compact.max&.in_time_zone,
          href: routes.hotel_booking_group_statement_path(
            hotel,
            booking,
            hotel_corporate_account_id: account.id,
            currency:
          ),
          context_type: "Consolidated AR",
          revision_actions: []
        )
      end
    end

    def document_invoice_amount(snapshot, folio)
      totals = snapshot["totals"].to_h
      return totals["charges"].to_d + totals["adjustments"].to_d if totals.key?("charges")

      values = @document_folio_totals[folio.id]
      values["charge"] + values["adjustment"]
    end

    def document_folio_balance(folio)
      values = @document_folio_totals[folio.id]
      values["charge"] - values["payment"] + values["adjustment"]
    end

    def document_invoice_payer(snapshot, folio)
      snapshot.dig("payer", "name").presence || document_folio_payer(folio)
    end

    def document_folio_payer(folio)
      folio.booking_billing_party&.display_name.presence ||
        folio.hotel_corporate_account&.corporate_account&.name.presence ||
        document_primary_guest_name(folio.booking)
    end

    def document_primary_guest_name(child)
      child.booking_guests.find(&:primary?)&.guest&.name.presence || child.guest_name.presence || "Guest unavailable"
    end

    def document_booking_label(child)
      child.formatted_reservation_number.presence || child.confirmation_token
    end

    def document_group_label
      booking.group_booking&.formatted_reservation_number.presence || document_booking_label(booking)
    end

    def document_room_label(folio)
      document_room(folio.booking_room || folio.booking.booking_rooms.first)
    end

    def document_booking_room_label(child)
      document_room(child.booking_rooms.first)
    end

    def document_room(room)
      return "Unassigned" unless room

      [ room.room_number.presence && "Room #{room.room_number}", room.room_type&.name ].compact_blank.join(" · ").presence || "Unassigned"
    end

    def document_permission?(slug)
      @document_permissions ||= {}
      return @document_permissions[slug] if @document_permissions.key?(slug)

      @document_permissions[slug] = !!@user&.has_permission?(slug, hotel:)
    end

    def routes = Rails.application.routes.url_helpers

    # Only 40 of 76 folios carry a booking_billing_party. The rest are resolvable from the
    # folio itself: an auto-created primary guest folio belongs to the guest, and a company
    # folio with a corporate account belongs to that account. Anything left is a real billing
    # defect and is surfaced as Unassigned rather than hidden.
    def billing_identity_for(folio, child)
      party = folio.booking_billing_party

      if party.present?
        identity_id = party.booking_guest&.guest_id || party.hotel_corporate_account_id
        return {
          key: [ party.party_kind, identity_id || "party-#{party.id}" ],
          name: party.display_name, kind: party.party_kind.to_s.humanize, sort: party.company? ? 1 : 0
        }
      end

      if folio.hotel_corporate_account_id.present?
        return {
          key: [ "company", folio.hotel_corporate_account_id ],
          name: folio.hotel_corporate_account&.corporate_account&.name.presence || "Corporate account",
          kind: "Company", sort: 1
        }
      end

      if folio.payer_type.to_s == "guest"
        guest = child.booking_guests.find(&:primary?)
        return {
          key: [ "guest", guest&.guest_id || "booking-#{child.id}" ],
          name: document_guest_name(child), kind: "Guest", sort: 0
        }
      end

      { key: [ "unassigned", folio.id ], name: "Unassigned", kind: "—", sort: 2 }
    end

    def explicit_entity_child_booking
      case active_tab
      when "folio_operations"
        entity_id = @params[:folio_id].presence || @params[:active_folio_id].presence
        child_bookings.find { |child| child.booking_folios.any? { |folio| folio.id.to_s == entity_id.to_s } } if entity_id
      when "guest_details"
        entity_id = @params[:booking_guest_id].presence
        child_bookings.find { |child| child.booking_guests.any? { |guest| guest.id.to_s == entity_id.to_s } } if entity_id
      end
    end

    def ordered_booking_folios(child)
      child.booking_folios.to_a.sort_by do |folio|
        [ folio.is_primary? ? 0 : 1, folio.folio_sequence.to_i, folio.id ]
      end
    end

    def ordered_booking_guests(child)
      child.booking_guests.to_a.sort_by { |guest| [ guest.primary? ? 0 : 1, guest.id ] }
    end

    def ordered_billing_parties(child)
      child.booking_billing_parties.to_a.select { |party| party.archived_at.nil? }
        .sort_by { |party| billing_party_sort_key(party) }
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

    # Returns nil rather than a raw or half-decrypted value so callers can fall
    # back with `||`. A corrupted column must not reach a form field, where an
    # apparently-blank value would be written back over the good data on save.
    def safe_encrypted_value(record, attribute)
      return if record.blank?

      safe_text(record.public_send(attribute), fallback: "").presence
    rescue ActiveRecord::Encryption::Errors::Decryption, JSON::ParserError, ArgumentError
      nil
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

    def folio_tree_row(folio, active: false)
      FolioRailRow.new(
        id: folio.id,
        number: folio.folio_reference_display.to_s,
        payer_line: folio_payer_line(folio),
        status_badge: folio_status_badge(folio),
        outstanding: money_for(folio.booking, folio.projected_outstanding_balance),
        active: active,
        href: nil
      )
    end

    def folio_status_badge(folio)
      tone = case folio.status
      when "open" then :success
      when "voided" then :destructive
      else :neutral
      end
      { label: folio.status.humanize, variant: tone }
    end

    # The payer's identity for the folio rail: "{payer type} : {name}". Falls back
    # to just the type for house folios, which have no billing party.
    def folio_payer_line(folio)
      type = folio_payer_type_label(folio)
      name = folio_payer_name(folio)
      name.present? ? "#{type} : #{name}" : type
    end

    def folio_payer_type_label(folio)
      case folio.payer_type
      when "company"
        account_type = folio.booking_billing_party&.account_type.presence ||
          folio.hotel_corporate_account&.account_type.presence
        external_account_type_label(account_type)
      when "hotel" then "On Hotel House"
      else "Guest"
      end
    end

    def folio_payer_name(folio)
      folio.booking_billing_party&.display_name.presence ||
        folio.hotel_corporate_account&.corporate_account&.name.presence ||
        (folio.payer_type == "hotel" ? nil : folio.booking&.guest_name)
    end

    def child_booking_label(child)
      room = child.booking_rooms.first
      room&.room_number.present? ? "Room #{room.room_number}" : "Unassigned room"
    end

    def audit_booking_option_label(child)
      guest = child.booking_guests.find(&:primary?)
      guest_name = guest&.name_snapshot.presence || guest&.guest&.name.presence || child.guest_name.presence || "Guest unavailable"

      [ child_booking_number(child), guest_name, child_booking_label(child) ].join(" · ")
    end

    def child_booking_number(child)
      child.formatted_reservation_number.presence || "—"
    end

    # Rail headings lead with the room number because front desk works from it.
    # An unassigned child has no room number to lead with, so it falls back to
    # the reservation number, which is the only thing left that distinguishes it.
    def entity_tree_group(child, rows, add_href)
      room = child.booking_rooms.first
      label = room&.room_number.present? ? "Room #{room.room_number}" : child_booking_number(child)

      TreeGroup.new(label, child_booking_room_type(child), rows, child.id, add_href)
    end

    # Each group carries its own add action so it targets that child booking
    # rather than whichever child happens to be selected.
    def add_guest_path_for(child)
      return unless child.status.in?(%w[confirmed checked_in])

      Rails.application.routes.url_helpers.hotel_booking_action_manage_guest_path(
        hotel, child, mode: "add", return_to: close_drawer_path
      )
    end

    def add_folio_path_for(child)
      Rails.application.routes.url_helpers.hotel_folio_action_new_window_path(hotel, child)
    end

    def child_booking_room_type(child)
      room = child.booking_rooms.first
      return unless room

      room.room_type&.name.presence || room.room_type_snapshot.to_h["name"].presence
    end

    def booking_guest_name(booking_guest, child)
      booking_guest&.name_snapshot.presence || booking_guest&.guest&.name.presence || child.guest_name
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
      return unless active_tab == "folio_operations"

      selected_folio&.id
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
      return { label: "Voided", tone: "rose" } if statuses.all? { |status| status == "voided" }
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
      @booking_billing_parties ||= ordered_billing_parties(selected_child_booking)
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
      party.company? ? billing_party_account_type_label(party) : "Guest"
    end

    def billing_party_role_label(party)
      case party.party_kind
      when "guest"
        party.booking_guest&.primary? ? "Primary guest" : "Additional guest"
      when "company"
        "Corporate Account"
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
        account&.direct_bill_enabled? ? "City Ledger · Direct bill enabled" : "Account settlement"
      else
        "Billing party"
      end
    end

    def billing_party_account_type_label(party)
      external_account_type_label(
        party.account_type.presence || party.hotel_corporate_account&.account_type.presence
      )
    end

    def external_account_type_label(account_type)
      {
        "company" => "Company",
        "government" => "Government",
        "travel_agent" => "Travel agency",
        "airline" => "Airline"
      }.fetch(account_type, "Corporate Account")
    end

    def billing_party_folios(party)
      party.booking_folios.to_a
    end
    end
  end
end
