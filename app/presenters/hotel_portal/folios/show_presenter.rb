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
      :row_kind,
      :reversed,
      keyword_init: true
    )

    def initialize(booking:, hotel:, user: nil, projected_lines: nil)
      @booking = booking
      @hotel = hotel
      @user = user
      @projected_lines_override = projected_lines
      @booking_presenter = HotelPortal::BookingPresenter.new(booking, hotel)
    end

    attr_reader :booking, :hotel, :user

    def folio
      booking.booking_folio
    end

    def currency
      booking.currency.presence || "MYR"
    end

    def folio_reference
      booking.formatted_folio_number.presence || folio&.folio_number.presence || booking.confirmation_token
    end

    def booking_reference
      booking.confirmation_token
    end

    def header_subtitle
      "Booking #{booking_reference} · #{guest_name} · #{stay_summary}"
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
        [ "Folio Reference", folio_reference ],
        [ "Guest", guest_name ],
        [ "Room", room_summary ],
        [ "Stay / Nights", formatted_stay_nights ],
        [ "Folio Type", "Booking folio" ]
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
        blockers = []
        blockers << "Guest owes #{money(current_balance)}" if current_balance.positive?
        blockers << "Hotel owes guest #{money(current_balance.abs)}" if current_balance.negative?
        blockers << "#{forecasted_rows.size} upcoming #{'charge'.pluralize(forecasted_rows.size)} pending" if forecasted_rows.any?
        blockers << "Audit is running" if hotel.current_business_date_record&.audit_running?
        blockers << "Audit is blocked" if hotel.current_business_date_record&.audit_blocked?
        blockers << "Captured payment is not synced" if unsynced_captured_payment?
        blockers << "Completed refund is not synced" if unsynced_completed_refund?
        blockers << "Folio is closed" if folio&.status == "closed"
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
      hotel.transaction_codes.active.charge.order(:code)
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

    def checkout_ready?
      if @checkout_ready.nil?
        @checkout_ready = current_balance.zero? &&
          forecasted_rows.empty? &&
          folio&.status == "open" &&
          !hotel.current_business_date_record&.audit_running? &&
          !hotel.current_business_date_record&.audit_blocked? &&
          !unsynced_captured_payment? &&
          !unsynced_completed_refund?
      end

      @checkout_ready
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
