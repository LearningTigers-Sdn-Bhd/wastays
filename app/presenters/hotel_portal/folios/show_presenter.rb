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
      :tax,
      :balance,
      :balance_kind,
      :action_label,
      :row_kind,
      :reversed,
      keyword_init: true
    )

    def initialize(booking:, hotel:)
      @booking = booking
      @hotel = hotel
      @booking_presenter = HotelPortal::BookingPresenter.new(booking, hotel)
    end

    attr_reader :booking, :hotel

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
        summary_item("Projected Total", money(projected_total), "Posted + forecast")
      ]
    end

    def secondary_summary_items
      [
        summary_item("Posted", "Posted amount", "Posted only"),
        summary_item("Posted Amount", money(posted_charges), "Charges"),
        summary_item("Paid/Refunded", "Paid/refunded", "Net received"),
        summary_item("Paid/Refunded Amount", money(payments_refunds), "Payments / refunds"),
        summary_item("Forecasted", "Forecasted", "Pending charges"),
        summary_item("Forecasted Amount", money(forecasted_charges), "Will post by audit"),
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
        summary_item("Projected Total", money(projected_total), "Posted + forecast"),
        summary_item("Posted Charges", money(posted_charges), "Posted only"),
        summary_item("Paid", money(paid_amount), "Net received"),
        summary_item("Forecasted Charges", forecasted_count_label, "Will post by audit"),
        summary_item("Forecasted Amount", money(forecasted_charges), "Pending charges"),
        summary_item("Refunds", money(refund_amount), refunds_hint),
        summary_item("Close", close_folio_label, close_folio_hint)
      ]
    end

    def folio_detail_rows
      [
        [ "Booking Reference", booking_reference ],
        [ "Folio Reference", folio_reference ],
        [ "Guest", guest_name ],
        [ "Room", room_summary ],
        [ "Stay", stay_summary ],
        [ "Nights", nights_label ],
        [ "Folio Type", "Booking folio" ]
      ]
    end

    def financial_metric_rows
      [
        [ "Current Balance", money(current_balance) ],
        [ "Balance State", balance_state_label ],
        [ "Posted Charges", money(posted_charges) ],
        [ "Payments/Refunds", money(payments_refunds) ],
        [ "Upcoming Charges", money(forecasted_charges) ],
        [ "Upcoming Lines", forecasted_count_label ],
        [ "Close Readiness", close_folio_label ]
      ]
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
        [ "Forecasted", money(forecasted_charges) ],
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
      forecasted_rows.empty? && current_balance.zero? && folio&.status == "open"
    end

    def close_folio_label
      close_folio_ready? ? "Ready" : "Not ready"
    end

    def close_folio_hint
      return "Ready to close" if close_folio_ready?
      return "#{forecasted_rows.size} forecasted #{'charge'.pluralize(forecasted_rows.size)} will post by night audit" if forecasted_rows.any?
      return "Guest owes #{money(current_balance)}" if current_balance.positive?
      return "Hotel owes guest #{money(current_balance.abs)}" if current_balance.negative?
      return "Folio is closed" if folio&.status == "closed"

      "Review folio before close"
    end

    def close_folio_status_text
      "Close Folio: #{close_folio_label} · #{close_folio_hint}"
    end

    def projected_lines
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

    def summary_item(label, value, hint)
      { label: label, value: value, hint: hint }
    end

    def posted_transactions
      @posted_transactions ||= folio&.folio_transactions&.includes(:transaction_code, :user)&.order(posting_date: :asc, created_at: :asc)&.to_a || []
    end

    def posted_row(transaction, effect, balance)
      LedgerRow.new(
        date_label: transaction.posting_date.strftime("%d %b"),
        code: posted_code(transaction),
        description: transaction.description,
        reference_label: reference_label(transaction),
        detail_label: "#{transaction.transaction_type.humanize} · #{transaction.category.humanize}",
        source_label: source_label(transaction),
        debit: effect.positive? ? amount_label(effect) : "—",
        credit: effect.negative? ? amount_label(effect) : "—",
        tax: tax_transaction?(transaction) ? amount_label(transaction.amount) : "—",
        balance: signed_amount_label(balance),
        balance_kind: "Balance",
        action_label: "⋯",
        row_kind: :posted,
        reversed: transaction.reversed?
      )
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
        tax: line[:category].to_s == "tax" ? amount_label(amount) : "—",
        balance: "Pending",
        balance_kind: "Balance",
        action_label: "—",
        row_kind: :forecasted,
        reversed: false
      )
    end

    def balance_effect(transaction)
      amount = transaction.amount.to_d
      transaction.payment? ? -amount : amount
    end

    def posted_code(transaction)
      transaction.transaction_code&.code.presence || metadata_transaction_code(transaction) || fallback_code(transaction.transaction_type, transaction.category, transaction.description)
    end

    def forecasted_code(line)
      fallback_code("charge", line[:category], line[:description])
    end

    def fallback_code(transaction_type, category, description = nil)
      text = "#{category} #{description}".downcase
      return "ROOM" if category.to_s == "accommodation"
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

    def reference_label(transaction)
      metadata = transaction.metadata.to_h
      reference = metadata["payment_transaction_id"].presence ||
        metadata[:payment_transaction_id].presence ||
        metadata["refund_request_id"].presence ||
        metadata[:refund_request_id].presence ||
        metadata["parent_folio_transaction_id"].presence ||
        metadata[:parent_folio_transaction_id].presence ||
        metadata["source_transaction_code_id"].presence ||
        metadata[:source_transaction_code_id].presence ||
        metadata["catch_up_key"].presence ||
        metadata[:catch_up_key].presence ||
        metadata["night_audit_id"].presence ||
        metadata[:night_audit_id].presence

      reference.present? ? "Ref #{reference}" : "—"
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

    def signed_amount_label(amount)
      value = amount.to_d
      prefix = value.negative? ? "-" : ""
      "#{prefix}#{amount_label(value)}"
    end
    end
  end
end
