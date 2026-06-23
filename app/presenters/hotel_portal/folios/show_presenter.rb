# frozen_string_literal: true

module HotelPortal
  module Folios
    class ShowPresenter
    include ActionView::Helpers::NumberHelper

    LedgerRow = Struct.new(
      :date_label,
      :code,
      :description,
      :reference_label,
      :detail_label,
      :source_label,
      :debit,
      :credit,
      :balance,
      :balance_kind,
      :action_label,
      :action_kind,
      :modal_title,
      :transaction_id,
      :forecast_id,
      :movement_allowed,
      :row_kind,
      :reversed,
      keyword_init: true
    )

    BillingInstructionRow = Struct.new(
      :rule,
      :code,
      :charge_label,
      :target_label,
      :target_reference,
      :status,
      :source,
      :editable,
      :children,
      :expanded,
      keyword_init: true
    )

    BillingInstructionChildRow = Struct.new(
      :rule,
      :code,
      :charge_label,
      :target_label,
      :target_reference,
      :status,
      :source,
      :enabled,
      keyword_init: true
    )

    RoutePreviewRow = Struct.new(
      :date_label,
      :code,
      :description,
      :amount,
      :source,
      :warning,
      keyword_init: true
    )

    RoutePreviewGroup = Struct.new(
      :folio,
      :target_label,
      :target_reference,
      :total,
      :rows,
      keyword_init: true
    )

    ActivityLogRow = Struct.new(
      :time_label,
      :action_label,
      :actor_label,
      :details,
      keyword_init: true
    )

    VALID_TABS = %w[ledger billing_instructions route_preview activity_log].freeze
    TAB_LABELS = {
      "ledger" => "Ledger",
      "billing_instructions" => "Billing Instructions",
      "route_preview" => "Route Preview",
      "activity_log" => "Activity Log"
    }.freeze

    def initialize(booking:, hotel:, user: nil, projected_lines: nil, active_folio_id: nil, active_tab: nil)
      @booking = booking
      @hotel = hotel
      @user = user
      @projected_lines_override = projected_lines
      @active_folio_id = active_folio_id.presence
      @active_tab = active_tab.presence
      @booking_presenter = HotelPortal::BookingPresenter.new(booking, hotel)
    end

    attr_reader :booking, :hotel, :user

    def folio
      @folio ||= begin
        selected = folios.detect { |candidate| candidate.id.to_s == @active_folio_id.to_s } if @active_folio_id.present?
        selected || booking.booking_folio || folios.first
      end
    end

    def folios
      @folios ||= booking.booking_folios.to_a.sort_by { |candidate| [ candidate.is_primary? ? 0 : 1, candidate.open? ? 0 : 1, candidate.folio_sequence.to_i, candidate.folio_number.to_i, candidate.id ] }
    end

    def active_folio_id
      folio&.id
    end

    def active_tab
      VALID_TABS.include?(@active_tab.to_s) ? @active_tab.to_s : "ledger"
    end

    def active_tab_label
      TAB_LABELS.fetch(active_tab)
    end

    def page_tabs
      TAB_LABELS.map do |name, label|
        {
          name: name,
          label: label,
          icon: tab_icon(name),
          active: name == active_tab
        }
      end
    end

    def other_open_folios
      folios.select { |candidate| candidate.open? && candidate.id != active_folio_id }
    end

    def can_manage_folio_windows?
      permitted?("manage_folio_windows")
    end

    def can_manage_folio_movements?
      can_show_normal_folio_actions? && permitted?("manage_folio_movements") && other_open_folios.any?
    end

    def can_manage_billing_instructions?
      permitted?("manage_folio_movements") && folios.any?(&:open?)
    end

    def folio_window_rows
      folios.map do |candidate|
        {
          id: candidate.id,
          name: candidate.display_name,
          payer: candidate.payer_type.to_s.humanize,
          type: candidate.folio_type.to_s.humanize,
          status: candidate.status.to_s.humanize,
          reference: candidate.folio_reference_display,
          balance: money(candidate.projected_outstanding_balance),
          active: candidate.id == active_folio_id,
          primary: candidate.is_primary?
        }
      end
    end

    def active_folio_window_row
      folio_window_rows.find { |row| row[:active] } || folio_window_rows.first
    end

    def currency
      folio&.currency.presence || booking.currency.presence || "MYR"
    end

    def folio_reference
      folio&.folio_reference_display.presence || booking.confirmation_token
    end

    def folio_account_reference
      booking.folio_account_reference_display.presence || booking.confirmation_token
    end

    def booking_reference
      booking.confirmation_token
    end

    def header_subtitle
      "Manage folio windows, posting actions, and ledger activity for this booking."
    end

    def guest_name
      @booking_presenter.primary_guest_name
    end

    def room_summary
      @booking_presenter.room_summary
    end

    def stay_summary
      "#{booking.check_in.strftime('%d %b')} - #{booking.check_out.strftime('%d %b %Y')}"
    end

    def compact_stay_summary
      "#{booking.check_in.strftime('%d %b')} - #{booking.check_out.strftime('%d %b')}"
    end

    def status_summary
      [ folio&.status&.humanize, booking.status.to_s.tr("_", " ").humanize ].compact_blank.join(" · ")
    end

    def status_hint
      return "Closed folio" if folio&.status == "closed"
      return "Active stay" if booking.status.in?(%w[checked_in in_house])

      "Folio · Booking"
    end

    def nights_label
      nights = (booking.check_out.to_date - booking.check_in.to_date).to_i
      "#{nights} #{'night'.pluralize(nights)}"
    end

    def formatted_stay_nights
      nights = (booking.check_out.to_date - booking.check_in.to_date).to_i
      dates = "#{booking.check_in.strftime('%d %b %Y')} - #{booking.check_out.strftime('%d %b %Y')}"
      "#{dates} / #{nights} #{'Night'.pluralize(nights)}"
    end

    def posted_charges
      (folio&.total_charges || 0).to_d
    end

    def payments_refunds
      (folio&.total_payments || 0).to_d
    end

    def posted_adjustments
      (folio&.total_adjustments || 0).to_d
    end

    def posted_balance
      (folio&.outstanding_balance || 0).to_d
    end

    def forecasted_charges
      projected_lines.sum { |line| line[:amount].to_d }
    end

    def current_balance
      posted_balance + forecasted_charges
    end

    def projected_total
      posted_charges + forecasted_charges
    end

    def forecasted_count_label
      "#{forecasted_rows.size} pending"
    end

    def paid_amount
      posted_transactions.select { |transaction| transaction.payment? && transaction.amount.to_d.positive? }.sum { |transaction| transaction.amount.to_d }
    end

    def refund_amount
      posted_transactions.select { |transaction| transaction.payment? && transaction.amount.to_d.negative? }.sum { |transaction| transaction.amount.to_d.abs }
    end

    def refunds_hint
      refund_amount.zero? ? "No refunds issued" : "Refunds issued"
    end

    def balance_state_label
      if current_balance.positive?
        "Guest owes hotel"
      elsif current_balance.negative?
        "Hotel owes guest"
      else
        "Settled"
      end
    end

    def balance_state_hint
      if current_balance.positive?
        "Payment required"
      elsif current_balance.negative?
        "Refund or adjustment needed"
      else
        "No amount due"
      end
    end

    def primary_summary_items
      [
        summary_item("Booking", booking_reference, "Booking reference"),
        summary_item("Guest", guest_name, "Primary guest"),
        summary_item("Room", room_summary, "Room / room type"),
        summary_item("Stay", stay_summary, "Check-in/out"),
        summary_item("Status", status_summary, "Folio · Booking"),
        summary_item("Balance", "#{balance_state_label} · #{money(current_balance)}", balance_state_hint),
        summary_item("Projected Total", money(projected_total), "Posted + upcoming")
      ]
    end

    def secondary_summary_items
      [
        summary_item("Posted", "Posted amount", "Posted only"),
        summary_item("Posted Amount", money(posted_charges), "Charges"),
        summary_item("Paid/Refunded", "Paid/refunded", "Net received"),
        summary_item("Paid/Refunded Amount", money(payments_refunds), "Payments / refunds"),
        summary_item("Upcoming", "Upcoming", "Pending charges"),
        summary_item("Upcoming Amount", money(forecasted_charges), "Will post by audit"),
        summary_item("Currency", currency, "Folio currency")
      ]
    end

    def folio_detail_items
      [
        summary_item("Booking", booking_reference, "Booking reference"),
        summary_item("Guest", guest_name, "Primary guest"),
        summary_item("Room", room_summary, "Room / room type"),
        summary_item("Stay", compact_stay_summary, nights_label),
        summary_item("Folio Type", "Booking folio", "Operational folio"),
        summary_item("Status", status_summary, status_hint),
        summary_item("Currency", currency, "Folio currency"),
        summary_item("Source", "Booking", booking_reference)
      ]
    end

    def financial_metric_items
      [
        summary_item("Balance", "#{balance_state_label} · #{money(current_balance)}", balance_state_hint),
        summary_item("Projected Total", money(projected_total), "Posted + upcoming"),
        summary_item("Posted Charges", money(posted_charges), "Posted only"),
        summary_item("Paid", money(paid_amount), "Net received"),
        summary_item("Upcoming Charges", forecasted_count_label, "Will post by audit"),
        summary_item("Upcoming Amount", money(forecasted_charges), "Pending charges"),
        summary_item("Refunds", money(refund_amount), refunds_hint),
        summary_item("Checkout", checkout_readiness_label, checkout_status_description)
      ]
    end

    def folio_detail_rows
      [
        [ "Booking Reference", booking_reference ],
        [ "Folio Account Reference", folio_account_reference ],
        [ "Folio Reference", folio_reference ],
        [ "Guest", guest_name ],
        [ "Room", room_summary ],
        [ "Stay / Nights", formatted_stay_nights ],
        [ "Currency", currency ]
      ]
    end

    def financial_metric_rows
      [
        [ "Current Balance", money(current_balance) ],
        [ "Balance State", balance_state_label ],
        [ "Posted Charges", money(posted_charges) ],
        [ "Payments / Refunds", money(payments_refunds) ],
        [ "Upcoming Charges", money(forecasted_charges) ],
        [ "Checkout Readiness", checkout_readiness_label ]
      ]
    end

    def checkout_readiness_label
      checkout_ready? ? "Ready" : "Not ready"
    end

    def checkout_status_label
      checkout_ready? ? "Ready for checkout" : "Not ready for checkout"
    end

    def checkout_status_description
      return "Balance settled · No upcoming charges · Payments/refunds synced" if checkout_ready?

      checkout_blockers.join(" · ")
    end

    def checkout_blockers
      @checkout_blockers ||= begin
        blockers = booking_checkout_readiness.blockers.dup
        blockers << "Captured payment is not synced" if unsynced_captured_payment?
        blockers << "Completed refund is not synced" if unsynced_completed_refund?
        blockers.presence || [ "Review booking checkout status" ]
      end
    end

    def booking_show_url
      Rails.application.routes.url_helpers.hotel_booking_path(hotel, booking)
    end

    def action_section_state
      return :closed if folio&.status == "closed"

      business_date_record = hotel.current_business_date_record
      return :audit_running_blocked if business_date_record&.audit_running?
      return :audit_blocked_blocked if business_date_record&.audit_blocked?

      :normal
    end

    def actions_blocked?
      %i[audit_running_blocked audit_blocked_blocked].include?(action_section_state)
    end

    def actions_blocked_reason
      case action_section_state
      when :audit_running_blocked
        "Night audit is currently running for this business date."
      when :audit_blocked_blocked
        "Night audit is blocked. Resolve blockers from the Night Audit page, then retry audit."
      end
    end

    def actions_blocked_title
      case action_section_state
      when :audit_running_blocked
        "Financial posting is temporarily unavailable."
      when :audit_blocked_blocked
        "Normal folio posting is blocked."
      when :closed
        "Folio is closed."
      end
    end

    def actions_blocked_url
      case action_section_state
      when :audit_running_blocked
        night_audit_url
      when :audit_blocked_blocked
        night_audit_blockers_url
      end
    end

    def actions_blocked_link_label
      case action_section_state
      when :audit_running_blocked
        "View Night Audit"
      when :audit_blocked_blocked
        "View Night Audit Blockers"
      end
    end

    def closed_folio_action_message
      "Normal posting actions are unavailable for a closed folio."
    end

    def night_audit_url
      return unless can_view_night_audit?

      if current_business_date_night_audit
        routes.hotel_night_audit_path(hotel, current_business_date_night_audit)
      else
        routes.hotel_night_audits_path(hotel)
      end
    end

    def night_audit_blockers_url
      return unless can_view_night_audit?

      if current_business_date_night_audit&.blocked?
        routes.resolve_hotel_night_audit_path(hotel, current_business_date_night_audit)
      else
        routes.hotel_night_audits_path(hotel)
      end
    end

    def can_show_normal_folio_actions?
      action_section_state == :normal && hotel.current_business_date_record&.allows_normal_posting?
    end

    def can_post_payment?
      can_show_normal_folio_actions? && permitted?("post_folio_payments")
    end

    def can_post_charge?
      can_show_normal_folio_actions? && permitted?("post_folio_charges")
    end

    def can_execute_refund?
      can_show_normal_folio_actions? && permitted?("execute_folio_refunds")
    end

    def adjustment_category_options
      return [] unless can_show_normal_folio_actions?

      options = []
      options += %w[adjustment discount other] if permitted?("post_folio_adjustments")
      options << "correction" if permitted?("post_folio_corrections")
      options << "write_off" if permitted?("post_folio_write_offs")
      options
    end

    def can_post_adjustment?
      adjustment_category_options.any?
    end

    def normal_folio_actions_available?
      can_post_payment? || can_post_charge? || can_post_adjustment? || can_execute_refund?
    end

    def booking_invoice_report_available?
      booking.checked_out? && folio&.closed?
    end

    def charge_transaction_codes
      @charge_transaction_codes ||= begin
        codes = hotel.transaction_codes.active.charge.includes(:transaction_code_taxes).order(:code).to_a
        hotel_tax_code_ids = hotel.hotel_taxes.where(transaction_code_id: codes.map(&:id)).pluck(:transaction_code_id)

        codes.reject { |code| hotel_tax_code_ids.include?(code.id) && !code.system_required? }
      end
    end

    def billing_instruction_rows
      parent_code_ids = charge_transaction_codes.map(&:id)
      folio_routing_rules.select { |rule| parent_code_ids.include?(rule.transaction_code_id) }.map do |rule|
        BillingInstructionRow.new(
          rule: rule,
          code: rule.transaction_code&.code || "—",
          charge_label: rule.transaction_code&.name || "Unknown charge",
          target_label: rule.target_folio&.display_name || "Missing folio",
          target_reference: rule.target_folio&.folio_reference_display,
          status: rule.active? ? "Active" : "Inactive",
          source: "Rule",
          editable: can_manage_billing_instructions?,
          children: billing_instruction_child_rows(rule.transaction_code, rule),
          expanded: billing_instruction_child_rows(rule.transaction_code, rule).any?
        )
      end
    end

    def default_billing_instruction_rows
      routed_code_ids = folio_routing_rules.select(&:active?).map(&:transaction_code_id)
      charge_transaction_codes.reject { |code| routed_code_ids.include?(code.id) }.map do |code|
        BillingInstructionRow.new(
          rule: nil,
          code: code.code,
          charge_label: code.name,
          target_label: folio&.display_name || "Primary folio",
          target_reference: folio&.folio_reference_display,
          status: "System",
          source: "Default",
          editable: false,
          children: billing_instruction_child_rows(code),
          expanded: billing_instruction_child_rows(code).any?
        )
      end
    end

    def route_preview_groups
      route_preview.grouped_by_folio.map do |target_folio, rows|
        preview_rows = rows.map { |row| route_preview_row(row) }
        RoutePreviewGroup.new(
          folio: target_folio,
          target_label: target_folio&.display_name || "Unresolved",
          target_reference: target_folio&.folio_reference_display,
          total: rows.sum { |row| row[:amount].to_d },
          rows: preview_rows
        )
      end.sort_by { |group| [ group.folio.nil? ? 1 : 0, group.target_label.to_s ] }
    end

    def route_preview_line_count
      route_preview.rows.size
    end

    def activity_log_rows
      folio_operation_logs.map do |log|
        ActivityLogRow.new(
          time_label: log.created_at.strftime("%d %b %H:%M"),
          action_label: log.operation_type.to_s.tr("_", " ").titleize,
          actor_label: log.actor&.name.presence || "System",
          details: operation_log_details(log)
        )
      end
    end

    def mobile_summary_items
      [
        [ "Booking", booking_reference ],
        [ "Guest", guest_name ],
        [ "Room", room_summary ],
        [ "Stay", compact_stay_summary ],
        [ "Status", status_summary ],
        [ "Balance", "#{balance_state_label} · #{money(current_balance)}" ],
        [ "Posted", money(posted_charges) ],
        [ "Paid/Refunded", money(payments_refunds) ],
        [ "Upcoming", money(forecasted_charges) ],
        [ "Projected", money(projected_total) ],
        [ "Currency", currency ]
      ]
    end

    def posted_rows
      balance = 0.to_d
      posted_transactions.map do |transaction|
        effect = balance_effect(transaction)
        balance += effect
        posted_row(transaction, effect, balance)
      end
    end

    def forecasted_rows
      balance = posted_balance
      projected_lines.map do |line|
        balance += line[:amount].to_d
        forecasted_row(line, balance)
      end
    end

    def ledger_entry_count
      posted_rows.size + forecasted_rows.size
    end

    def posted_section_summary
      parts = [ "#{posted_rows.size} posted" ]
      parts << "#{money(posted_charges)} charges" unless posted_charges.zero?
      parts << "#{money(payments_refunds)} payments" unless payments_refunds.zero?
      parts.join(" · ")
    end

    def forecasted_section_summary
      "#{forecasted_rows.size} pending · #{money(forecasted_charges)} upcoming · Will post by audit"
    end

    def close_folio_ready?
      checkout_ready?
    end

    def close_folio_label
      checkout_readiness_label
    end

    def close_folio_hint
      checkout_status_description
    end

    def close_folio_status_text
      "Checkout: #{checkout_readiness_label} · #{checkout_status_description}"
    end

    def projected_lines
      return @projected_lines_override unless @projected_lines_override.nil?

      @projected_lines ||= Array(folio&.projected_forecasts).map do |forecast|
        {
          forecast_id: forecast.id,
          date: forecast.stay_date,
          description: forecast.description,
          amount: forecast.amount,
          category: forecast.charge_kind,
          identity: forecast.identity
        }
      end
    end

    def money(amount)
      "#{currency} #{number_with_precision(amount.to_d, precision: 2)}"
    end

    def amount_label(amount)
      number_with_precision(amount.to_d.abs, precision: 2)
    end

    private

    def tab_icon(name)
      {
        "ledger" => "receipt-text",
        "billing_instructions" => "route",
        "route_preview" => "map",
        "activity_log" => "history"
      }.fetch(name)
    end

    def folio_routing_rules
      @folio_routing_rules ||= booking.folio_routing_rules.includes(:transaction_code, :target_folio, :created_by, :updated_by).order(active: :desc, created_at: :asc, id: :asc).to_a
    end

    def active_folio_routing_rules_by_transaction_code_id
      @active_folio_routing_rules_by_transaction_code_id ||= folio_routing_rules.select(&:active?).index_by(&:transaction_code_id)
    end

    def billing_instruction_child_rows(transaction_code, parent_rule = nil)
      return [] if transaction_code.blank?

      transaction_code.transaction_code_taxes.includes(:hotel_tax).map do |tax_rule|
        child_code = tax_rule.posting_transaction_code
        child_rule = active_folio_routing_rules_by_transaction_code_id[child_code&.id]
        target_folio = child_rule&.target_folio || parent_rule&.target_folio || folio

        BillingInstructionChildRow.new(
          rule: child_rule,
          code: composite_tax_code(transaction_code, child_code, tax_rule),
          charge_label: tax_rule.display_name,
          target_label: target_folio&.display_name || "Primary folio",
          target_reference: target_folio&.folio_reference_display,
          status: tax_rule.enabled_for_posting? ? (child_rule.present? ? "Active" : "Follows parent") : "Disabled",
          source: child_rule.present? ? "Rule" : "Attached tax/fee",
          enabled: tax_rule.enabled_for_posting?
        )
      end
    end

    def composite_tax_code(parent_code, child_code, tax_rule)
      child_label = child_code&.code.presence || tax_rule.tax_line_type.to_s.upcase.presence || "TAX"
      "#{parent_code.code}_#{child_label}"
    end

    def route_preview
      @route_preview ||= ::Folios::RoutePreview.call(booking: booking, actor: user)
    end

    def route_preview_row(row)
      RoutePreviewRow.new(
        date_label: row[:date].strftime("%d %b"),
        code: row[:display_code_label],
        description: row[:description],
        amount: money(row[:amount]),
        source: route_source_label(row[:route_source]),
        warning: row[:warning]
      )
    end

    def route_source_label(source)
      case source
      when "routing_rule" then "Rule"
      when "follows_parent" then "Follows"
      when "manual_override" then "Override"
      when "primary_folio" then "Default"
      else "Preview"
      end
    end

    def folio_operation_logs
      @folio_operation_logs ||= booking.folio_operation_logs
        .includes(:actor, :source_folio, :target_folio, :source_transaction, :target_transaction)
        .order(created_at: :desc, id: :desc)
        .limit(50)
        .to_a
    end

    def operation_log_details(log)
      metadata = log.metadata.to_h
      case log.operation_type
      when "create_routing_rule", "update_routing_rule", "deactivate_routing_rule"
        [
          metadata["transaction_code_code"],
          log.target_folio&.display_name || metadata["target_folio_reference"],
          log.reason.presence
        ].compact_blank.join(" -> ")
      when "move_transaction", "split_transaction", "move_forecast"
        [ log.source_folio&.display_name, log.target_folio&.display_name, log.reason.presence ].compact_blank.join(" -> ")
      when "create_folio", "rename_folio", "set_default_folio", "close_folio", "reopen_folio"
        [ log.target_folio&.display_name || log.source_folio&.display_name, log.reason.presence ].compact_blank.join(" · ")
      else
        log.reason.presence || metadata.except("previous").compact.to_a.map { |key, value| "#{key.to_s.humanize}: #{value}" }.join(" · ").presence || "—"
      end.presence || "—"
    end

    def checkout_ready?
      if @checkout_ready.nil?
        @checkout_ready = booking_checkout_readiness.ready? &&
          !unsynced_captured_payment? &&
          !unsynced_completed_refund?
      end

      @checkout_ready
    end

    def booking_checkout_readiness
      @booking_checkout_readiness ||= ::Folios::BookingCheckoutReadiness.call(booking: booking, hotel: hotel)
    end

    def unsynced_captured_payment?
      if @unsynced_captured_payment.nil?
        @unsynced_captured_payment = booking.payment_transactions.where(status: "captured").any? do |payment_transaction|
          !payment_synced?(payment_transaction)
        end
      end

      @unsynced_captured_payment
    end

    def unsynced_completed_refund?
      if @unsynced_completed_refund.nil?
        refund_request = booking.refund_request
        @unsynced_completed_refund = refund_request&.completed? && !refund_synced?(refund_request)
      end

      @unsynced_completed_refund
    end

    def payment_synced?(payment_transaction)
      expected_amount = payment_transaction.amount_subunits.to_d / 100.0

      posted_transactions.any? do |transaction|
        transaction.payment? &&
          transaction.metadata.to_h["payment_transaction_id"].to_s == payment_transaction.id.to_s &&
          transaction.amount.to_d == expected_amount
      end
    end

    def refund_synced?(refund_request)
      expected_amount = -refund_request.refund_amount.to_d

      posted_transactions.any? do |transaction|
        transaction.payment? &&
          transaction.metadata.to_h["refund_request_id"].to_s == refund_request.id.to_s &&
          transaction.amount.to_d == expected_amount
      end
    end

    def summary_item(label, value, hint)
      { label: label, value: value, hint: hint }
    end

    def permitted?(slug)
      return true if user&.respond_to?(:superadmin?) && user.superadmin?
      return false unless user&.respond_to?(:has_permission?)

      user.has_permission?(slug, hotel: hotel)
    end

    def can_view_night_audit?
      permitted?("manage_night_audit")
    end

    def current_business_date_night_audit
      @current_business_date_night_audit ||= begin
        business_date = hotel.current_business_date
        business_date.present? ? hotel.night_audits.where(business_date: business_date).order(created_at: :desc).first : nil
      end
    end

    def routes
      Rails.application.routes.url_helpers
    end

    def posted_transactions
      @posted_transactions ||= folio&.folio_transactions&.includes(:transaction_code, :user)&.order(posting_date: :asc, created_at: :asc)&.to_a || []
    end

    def posted_row(transaction, effect, balance)
      policy = ::Folios::TransactionActionPolicy.new(transaction: transaction, user: user)
      action_label = suppress_normal_ledger_actions? ? "—" : policy.action_label
      action_kind = suppress_normal_ledger_actions? ? :none : policy.action_kind
      LedgerRow.new(
        date_label: transaction.posting_date.strftime("%d %b"),
        code: posted_code(transaction),
        description: transaction.description,
        reference_label: reference_label(transaction),
        detail_label: detail_label(transaction),
        source_label: source_label(transaction),
        debit: effect.positive? ? amount_label(effect) : "—",
        credit: effect.negative? ? amount_label(effect) : "—",
        balance: signed_amount_label(balance),
        balance_kind: "Balance",
        action_label: action_label,
        action_kind: action_kind,
        modal_title: action_kind == :reverse ? policy.modal_title : nil,
        transaction_id: transaction.id,
        forecast_id: nil,
        movement_allowed: transaction.charge? && !tax_transaction?(transaction) && !transaction.reversed? && transaction.reversal_of_transaction_id.blank?,
        row_kind: :posted,
        reversed: transaction.reversed?
      )
    end

    def suppress_normal_ledger_actions?
      actions_blocked?
    end

    def forecasted_row(line, balance)
      amount = line[:amount].to_d
      LedgerRow.new(
        date_label: line[:date].strftime("%d %b"),
        code: forecasted_code(line),
        description: line[:description],
        reference_label: "—",
        detail_label: forecasted_detail(line),
        source_label: "Upcoming",
        debit: amount.positive? ? amount_label(amount) : "—",
        credit: amount.negative? ? amount_label(amount) : "—",
        balance: "Pending",
        balance_kind: "Balance",
        action_label: "—",
        action_kind: :none,
        modal_title: nil,
        transaction_id: nil,
        forecast_id: line[:forecast_id],
        movement_allowed: line[:forecast_id].present?,
        row_kind: :forecasted,
        reversed: false
      )
    end

    def balance_effect(transaction)
      amount = transaction.amount.to_d
      transaction.payment? ? -amount : amount
    end

    def posted_code(transaction)
      return derived_tax_transaction_code(transaction) if tax_transaction?(transaction)

      transaction.transaction_code&.code.presence || metadata_transaction_code(transaction) || fallback_code(transaction.transaction_type, transaction.category, transaction.description)
    end

    def forecasted_code(line)
      fallback_code("charge", line[:category], line[:description])
    end

    def fallback_code(transaction_type, category, description = nil)
      text = "#{category} #{description}".downcase
      return "ROOM" if category.to_s == "accommodation"
      return "EARLY_DEP" if category.to_s == "early_departure_charge"
      return "LATE_CO" if category.to_s == "late_checkout_charge"
      return "SST" if text.include?("sst")
      return "TTX" if text.include?("tourism")
      return "SVC" if text.include?("service charge")
      return "TAX" if category.to_s == "tax"
      return "CASH" if category.to_s == "cash"
      return "REFUND" if category.to_s == "refund"
      return "PAYMENT" if transaction_type.to_s == "payment"
      return "ADJ" if transaction_type.to_s == "adjustment"

      transaction_type.to_s.upcase.presence || "—"
    end

    def metadata_transaction_code(transaction)
      metadata = transaction.metadata.to_h
      metadata.dig("tax_line", "transaction_code_code").presence || metadata.dig(:tax_line, :transaction_code_code).presence
    end

    def derived_tax_transaction_code(transaction)
      child_code = metadata_transaction_code(transaction) || transaction.transaction_code&.code.presence
      source_code = source_transaction_code_for(transaction)&.code.presence
      return "#{source_code}_#{child_code}" if source_code.present? && child_code.present?

      child_code || transaction.transaction_code&.code.presence || fallback_code(transaction.transaction_type, transaction.category, transaction.description)
    end

    def source_transaction_code_for(transaction)
      metadata = transaction.metadata.to_h
      tax_line = metadata["tax_line"].to_h
      source_id = tax_line["source_transaction_code_id"].presence ||
        metadata["source_transaction_code_id"].presence ||
        metadata[:source_transaction_code_id].presence
      parent_id = metadata["parent_folio_transaction_id"].presence || metadata[:parent_folio_transaction_id].presence
      source_id ||= posted_transactions_by_id[parent_id.to_i]&.transaction_code_id if parent_id.present?
      return if source_id.blank?

      transaction_codes_by_id[source_id.to_i]
    end

    def reference_label(transaction)
      metadata = transaction.metadata.to_h
      return tax_reference_label(transaction, metadata) if tax_transaction?(transaction)
      return payment_reference_label(transaction, metadata) if transaction.payment?

      reference = metadata["reference"].presence ||
        metadata[:reference].presence ||
        metadata["source_transaction_code_id"].presence ||
        metadata[:source_transaction_code_id].presence ||
        metadata["catch_up_key"].presence ||
        metadata[:catch_up_key].presence ||
        metadata["night_audit_id"].presence ||
        metadata[:night_audit_id].presence

      reference.present? ? "Ref #{reference}" : "—"
    end

    def detail_label(transaction)
      metadata = transaction.metadata.to_h
      if transaction.payment? && metadata["payment_source"].present?
        payment_source = ::Folios::PaymentSource.fetch(metadata["payment_source"])
        return [ "Payment", payment_source&.display_label, state_label(transaction) ].compact.join(" · ")
      end

      label = "#{transaction.transaction_type.humanize} · #{transaction.category.humanize}"
      state = state_label(transaction)
      state.present? ? "#{label} · #{state}" : label
    end

    def source_label(transaction)
      source = transaction.metadata.to_h["posting_source"].presence || transaction.metadata.to_h[:posting_source].presence
      actor = transaction.user&.name.presence || "System"
      detail = source.presence || (transaction.user ? "Manual" : "Night Audit")
      actor == "System" ? "System" : "#{actor} / #{detail.to_s.tr('_', ' ').titleize}"
    end

    def tax_transaction?(transaction)
      transaction.category.to_s == "tax" || transaction.metadata.to_h["tax_line"].present? || transaction.metadata.to_h[:tax_line].present?
    end

    def forecasted_detail(line)
      line[:category].to_s == "tax" ? "Tax linked to ROOM" : line[:category].to_s.humanize
    end

    def tax_reference_label(transaction, metadata)
      parent_id = metadata["parent_folio_transaction_id"].presence || metadata[:parent_folio_transaction_id].presence
      parent_code = parent_id.present? ? parent_transaction_code(parent_id) : nil
      [ "Tax linked to #{parent_code || 'parent'}", parent_id.present? ? "Parent ##{parent_id}" : nil ].compact.join(" · ")
    end

    def payment_reference_label(transaction, metadata)
      if metadata["payment_source"].present?
        return staff_payment_reference_label(transaction, metadata)
      end

      if metadata["payment_transaction_id"].present? || metadata["posting_source"] == "gateway_payment"
        payment = payment_transactions_by_id[metadata["payment_transaction_id"].to_s]
        gateway_ref = payment&.external_reference || metadata["payment_reference"].presence || metadata["reference"].presence || metadata["payment_transaction_id"].presence
        parts = [ gateway_ref.present? ? "Gateway Ref #{gateway_ref}" : "Gateway payment" ]
        parts << payment.gateway.to_s.titleize if payment&.gateway.present?
        parts << payment.payment_method.to_s.titleize if payment&.payment_method.present?
        parts << "Synced"
        return parts.compact_blank.join(" · ")
      end

      if transaction.category == "cash"
        parts = []
        reference = metadata["reference"].presence || metadata[:reference].presence
        parts << "Receipt #{reference}" if reference.present?
        parts << "Cash"
        parts << "Staff: #{transaction.user.name}" if transaction.user&.name.present?
        return parts.join(" · ")
      end

      if metadata["refund_request_id"].present?
        return "Refund Request ##{metadata['refund_request_id']} · #{source_state_label(transaction)}"
      end

      if transaction.category == "refund"
        refund_source = ::Folios::RefundSource.fetch(metadata["refund_source"].presence || metadata[:refund_source].presence)
        reference = metadata["reference"].presence || metadata[:reference].presence
        return [ reference.present? ? "Ref #{reference}" : nil, refund_source&.display_label, "Refund", source_state_label(transaction) ].compact.join(" · ")
      end

      reference = metadata["reference"].presence || metadata[:reference].presence
      [ reference.present? ? "Ref #{reference}" : nil, transaction.category.humanize, source_state_label(transaction) ].compact.join(" · ").presence || "—"
    end

    def staff_payment_reference_label(transaction, metadata)
      payment_source = ::Folios::PaymentSource.fetch(metadata["payment_source"])
      return "—" if payment_source.blank?

      reference = payment_source_reference(metadata, payment_source)
      parts = []
      parts << "#{payment_source.reference_prefix} #{reference}" if reference.present?
      parts << payment_source.display_label
      parts << "Staff: #{transaction.user.name}" if transaction.user&.name.present?
      parts.compact_blank.join(" · ")
    end

    def payment_source_reference(metadata, payment_source)
      source_references = metadata["source_references"].presence || metadata[:source_references].presence || {}
      source_references[payment_source.reference_key].presence ||
        source_references[payment_source.reference_key.to_sym].presence ||
        metadata[payment_source.reference_key].presence ||
        metadata[payment_source.reference_key.to_sym].presence ||
        metadata["reference"].presence ||
        metadata[:reference].presence
    end

    def parent_transaction_code(parent_id)
      posted_transactions_by_id[parent_id.to_i]&.then { |parent| posted_code(parent) }
    end

    def transaction_codes_by_id
      @transaction_codes_by_id ||= hotel.transaction_codes.index_by(&:id)
    end

    def state_label(transaction)
      return "Voided" if transaction.voided_by_transaction_id.present?
      return "Reversal" if transaction.reversal_of_transaction_id.present?

      source_state_label(transaction)
    end

    def source_state_label(transaction)
      metadata = transaction.metadata.to_h
      source = metadata["posting_source"].presence || metadata[:posting_source].presence
      return "Night Audit" if transaction.night_audit_id.present? || metadata["night_audit_id"].present? || source == "night_audit"
      return "Gateway" if source == "gateway_payment" || metadata["payment_transaction_id"].present?
      return "Gateway" if metadata["payment_source"] == "gateway"
      return "OTA" if source.to_s.include?("ota") || metadata["payment_source"] == "ota"
      return "Manual" if transaction.user.present? || source == "staff"

      "System"
    end

    def posted_transactions_by_id
      @posted_transactions_by_id ||= posted_transactions.index_by(&:id)
    end

    def payment_transactions_by_id
      @payment_transactions_by_id ||= begin
        ids = posted_transactions.filter_map { |transaction| transaction.metadata.to_h["payment_transaction_id"].presence&.to_s }
        ids.any? ? PaymentTransaction.where(id: ids).index_by { |payment| payment.id.to_s } : {}
      end
    end

    def signed_amount_label(amount)
      value = amount.to_d
      prefix = value.negative? ? "-" : ""
      "#{prefix}#{amount_label(value)}"
    end
    end
  end
end
