# frozen_string_literal: true

module Folios
  class TransactionActionPolicy
    OVERRIDE_PERMISSION = FinancialControls::PostingGuard::OVERRIDE_PERMISSION

    attr_reader :transaction, :user, :posting_date

    def initialize(transaction:, user:, posting_date: nil)
      @transaction = transaction
      @user = user
      hotel = transaction.booking_folio.hotel
      @posting_date = (posting_date || hotel.current_business_date || hotel.business_date_for(Time.current)).to_date
    end

    def reverse_allowed?
      non_reversible_reason.blank?
    end

    def reverse_error
      non_reversible_reason || "Transaction can be reversed."
    end

    def action_label
      return "Voided" if transaction.voided_by_transaction_id.present?
      return "Correction" if transaction.reversal_of_transaction_id.present?
      return "Tax reverses with parent" if generated_tax_child?
      return gateway_payment_action_label if gateway_payment?
      return ota_payment_action_label if ota_payment?
      return "—" if completed_gateway_refund?
      return "Night Audit" if night_audit_row?
      return "Reverse group" if reverse_allowed? && taxable_parent?
      return "Reverse payment" if reverse_allowed? && manual_payment?
      return "Reverse" if reverse_allowed?

      "—"
    end

    def reversible_action_label
      return unless reverse_allowed?

      action_label
    end

    def action_kind
      return :reverse if reverse_allowed?
      return :disabled if action_label.present? && action_label != "—"

      :none
    end

    def modal_title
      case action_label
      when "Reverse group" then "Reverse tax group"
      when "Reverse payment" then "Reverse payment"
      else "Reverse transaction"
      end
    end

    def override_options(correction_reason:, correction_note:)
      options = {}
      if closed_folio?
        return options unless override_allowed?

        options[:override_closed_folio] = true
      end

      if closed_or_past_business_date?
        return options unless override_allowed?

        options[:override_night_audit] = true
      end

      if options.any?
        options[:correction_reason] = correction_reason
        options[:correction_note] = correction_note
      end

      options
    end

    def taxable_parent?
      generated_tax_children.any?
    end

    def generated_tax_child?
      metadata["parent_folio_transaction_id"].present? || metadata["tax_line"].present?
    end

    def generated_tax_children
      Folios::AttachedTaxTransactions.call(transaction)
    end

    def posting_source
      metadata["posting_source"].presence
    end

    def gateway_payment?
      transaction.payment? && (
        metadata["payment_source"] == "gateway" ||
        metadata["payment_transaction_id"].present? ||
        posting_source == "gateway_payment"
      )
    end

    def ota_payment?
      transaction.payment? && (
        metadata["payment_source"] == "ota" ||
        (transaction.category == "booking_payment" && metadata["ota_reference"].present?) ||
        posting_source.to_s.include?("ota")
      )
    end

    def completed_gateway_refund?
      transaction.payment? && transaction.category == "refund" && (
        metadata["refund_request_id"].present? || posting_source == "gateway_refund"
      )
    end

    def night_audit_row?
      transaction.night_audit_id.present? || metadata["night_audit_id"].present? || posting_source == "night_audit"
    end

    private

    def non_reversible_reason
      return "Transaction has already been reversed." if transaction.voided_by_transaction_id.present?
      return "Reversal transactions cannot be reversed." if transaction.reversal_of_transaction_id.present?
      return "Generated tax rows reverse with their parent charge." if generated_tax_child?
      return "Gateway payments must use the payment refund or reconciliation workflow." if gateway_payment?
      return "OTA-collected payments must use source reconciliation." if ota_payment?
      return "Completed gateway refunds cannot be reversed from the folio ledger." if completed_gateway_refund?
      return "Night audit rows cannot be reversed from the folio ledger." if night_audit_row?
      return "Folio is closed." if closed_folio? && !override_allowed?
      return "Closed business dates require #{OVERRIDE_PERMISSION} permission." if closed_or_past_business_date? && !override_allowed?
      return "You do not have permission to post folio corrections." unless correction_permission?

      nil
    end

    def manual_payment?
      return false unless transaction.payment?

      metadata["payment_source"].in?(%w[cash bank card]) ||
        (metadata["payment_source"].blank? && transaction.category.in?(%w[cash refund booking_payment]))
    end

    def closed_folio?
      transaction.booking_folio.status == "closed"
    end

    def closed_or_past_business_date?
      hotel = transaction.booking_folio.hotel
      current_business_date = hotel.current_business_date || hotel.business_date_for(Time.current)
      posting_date < current_business_date || hotel.date_closed?(posting_date)
    end

    def correction_permission?
      return true if user&.respond_to?(:superadmin?) && user.superadmin?
      return false unless user&.respond_to?(:has_permission?)

      user.has_permission?("post_folio_corrections", hotel: transaction.booking_folio.hotel)
    end

    def override_allowed?
      return true if user&.respond_to?(:superadmin?) && user.superadmin?
      return false unless user&.respond_to?(:has_permission?)

      user.has_permission?(OVERRIDE_PERMISSION, hotel: transaction.booking_folio.hotel)
    end

    def gateway_payment_action_label
      "Refund"
    end

    def ota_payment_action_label
      "Reconcile"
    end

    def metadata
      @metadata ||= transaction.metadata.to_h.with_indifferent_access
    end
  end
end
