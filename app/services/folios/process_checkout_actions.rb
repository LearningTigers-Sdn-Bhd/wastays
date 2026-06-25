# frozen_string_literal: true

require "ostruct"

module Folios
  class ProcessCheckoutActions
    PAYMENT_ACTION = "pay_now"
    DIRECT_BILL_ACTION = "direct_bill"
    CLOSE_ACTION = "close"
    BLOCKING_ACTIONS = %w[refund_credit_handling voided].freeze
    EXCEPTION_ACTIONS = %w[keep_open manager_review write_off_approval].freeze
    PAYMENT_METHODS = %w[cash card].freeze

    def self.call(booking:, hotel:, user:, action_params:, posting_date:, options: {})
      new(
        booking: booking,
        hotel: hotel,
        user: user,
        action_params: action_params,
        posting_date: posting_date,
        options: options
      ).call
    end

    def initialize(booking:, hotel:, user:, action_params:, posting_date:, options: {})
      @booking = booking
      @hotel = hotel
      @user = user
      @action_params = action_params.to_h.with_indifferent_access
      @posting_date = posting_date
      @options = options
      @exception_folio_ids = []
      @direct_bill_folio_ids = []
    end

    def call
      error = validate
      return failure(error) if error.present?

      folios.each do |folio|
        action = action_for(folio)
        case action
        when PAYMENT_ACTION
          result = post_payment(folio)
          return failure(result.error) unless result.success?
        when DIRECT_BILL_ACTION
          @direct_bill_folio_ids << folio.id
        when *EXCEPTION_ACTIONS
          @exception_folio_ids << folio.id
          log_exception(folio)
        end
      end

      success(exception_folio_ids: @exception_folio_ids, direct_bill_folio_ids: @direct_bill_folio_ids)
    rescue StandardError => e
      failure(e.message)
    end

    private

    def validate
      return "Booking has no folio." if folios.empty?

      readiness = Folios::BookingCheckoutReadiness.call(booking: @booking, hotel: @hotel)
      pending_error = pending_charge_error(readiness)
      return pending_error if pending_error.present?

      folios.each do |folio|
        params = params_for(folio)
        action = action_for(folio)
        balance = folio.projected_outstanding_balance.to_d
        allowed_actions = allowed_actions_for(folio, balance)

        return "#{folio.display_name}: checkout action is required." if action.blank?
        return "#{folio.display_name}: #{action.humanize} is not allowed." unless allowed_actions.include?(action)
        return "#{folio.display_name}: refund / credit handling must be completed before checkout." if action == "refund_credit_handling"
        return "#{folio.display_name}: cannot check out while folio is voided." if action == "voided"

        if action == PAYMENT_ACTION
          return "#{folio.display_name}: payment amount must equal #{money(balance)}." unless payment_amount_for(folio) == balance
          return "#{folio.display_name}: payment method is not supported." unless payment_method_for(folio).in?(PAYMENT_METHODS)
          return "You do not have permission to post checkout payments." unless can_post_payments?
        end

        if action == DIRECT_BILL_ACTION
          return "#{folio.display_name}: Direct Bill is not available." unless direct_bill_enabled?(folio)
          return "#{folio.display_name}: Direct Bill requires a positive balance." unless balance.positive?
        end

        if EXCEPTION_ACTIONS.include?(action) && reason_for(folio).blank?
          return "#{folio.display_name}: reason is required for #{action.humanize.downcase}."
        end

        if guest_folio?(folio) && action != CLOSE_ACTION && action != PAYMENT_ACTION
          return "#{folio.display_name}: guest folio must be financially resolved before checkout."
        end
      end

      nil
    end

    def pending_charge_error(readiness)
      pending_blocker = readiness.blockers.find { |blocker| blocker.include?("upcoming") && blocker.include?("pending") }
      return if pending_blocker.blank?

      "Upcoming charges must be posted before checkout. #{pending_blocker}"
    end

    def post_payment(folio)
      source = Folios::PaymentSource.fetch(payment_method_for(folio))
      return failure("Checkout payment method is not supported.") if source.blank?

      Folios::PostStaffTransaction.call(
        folio: folio,
        user: @user,
        transaction_type: "payment",
        category: "cash",
        amount: payment_amount_for(folio),
        description: payment_description(folio, source),
        posting_date: @posting_date,
        options: payment_options(folio, source)
      )
    end

    def payment_options(folio, source)
      metadata = @options.fetch(:metadata, {}).merge(payment_reference_metadata(folio, source))
      @options.merge(payment_source: source.key, metadata: metadata)
    end

    def payment_description(folio, source)
      reference = payment_reference_for(folio)
      [ "Checkout payment for #{folio.display_name} via #{source.label}", reference && "#{source.reference_prefix} #{reference}" ].compact.join(" - ")
    end

    def payment_reference_metadata(folio, source)
      reference = payment_reference_for(folio)
      return {} if reference.blank?

      {
        reference: reference,
        source.reference_key => reference
      }
    end

    def log_exception(folio)
      FolioOperationLog.create!(
        hotel: @hotel,
        booking: @booking,
        actor: @user,
        operation_type: "checkout_exception",
        source_folio: folio,
        target_folio: folio,
        amount: folio.projected_outstanding_balance.to_d,
        currency: folio.currency,
        reason: reason_for(folio),
        metadata: {
          checkout_action: action_for(folio),
          balance: folio.projected_outstanding_balance.to_d.to_s("F")
        }
      )
    end

    def allowed_actions_for(folio, balance)
      return [ "closed" ] if folio.closed?
      return [ "voided" ] if folio.voided?

      if guest_folio?(folio)
        return [ PAYMENT_ACTION ] if balance.positive?
        return [ CLOSE_ACTION ] if balance.zero?

        [ "refund_credit_handling" ]
      elsif company_folio?(folio)
        return company_folio_positive_balance_actions(folio) if balance.positive?
        return [ CLOSE_ACTION ] if balance.zero?

        [ "refund_credit_handling", "keep_open" ]
      else
        return [ CLOSE_ACTION ] if balance.zero?

        EXCEPTION_ACTIONS
      end
    end

    def folios
      @folios ||= @booking.booking_folios.includes(:folio_transactions, :folio_forecasted_charges, hotel_corporate_account: :corporate_account).order(:id).to_a
    end

    def params_for(folio)
      @action_params[folio.id.to_s].to_h.with_indifferent_access
    end

    def action_for(folio)
      if guest_folio?(folio)
        balance = folio.projected_outstanding_balance.to_d
        if balance.positive?
          PAYMENT_ACTION
        elsif balance.zero?
          CLOSE_ACTION
        else
          "refund_credit_handling"
        end
      else
        params_for(folio)[:action].to_s
      end
    end

    def payment_amount_for(folio)
      params_for(folio)[:amount].to_d
    end

    def payment_method_for(folio)
      params_for(folio)[:payment_method].to_s.presence || "cash"
    end

    def payment_reference_for(folio)
      params_for(folio)[:payment_reference].to_s.strip.presence
    end

    def reason_for(folio)
      params_for(folio)[:reason].to_s.strip.presence
    end

    def guest_folio?(folio)
      folio.folio_type == "guest" && folio.payer_type == "guest"
    end

    def company_folio?(folio)
      folio.payer_type == "company"
    end

    def company_folio_positive_balance_actions(folio)
      actions = [ PAYMENT_ACTION ]
      actions << DIRECT_BILL_ACTION if direct_bill_enabled?(folio)
      actions << "keep_open"
      actions
    end

    def direct_bill_enabled?(folio)
      relationship = folio.hotel_corporate_account
      relationship.present? && relationship.active? && relationship.direct_bill_enabled?
    end

    def can_post_payments?
      @user&.respond_to?(:superadmin?) && @user.superadmin? ||
        @user&.respond_to?(:has_permission?) && @user.has_permission?("post_folio_payments", hotel: @hotel)
    end

    def money(amount)
      "#{@booking.currency.presence || @hotel.default_currency.presence || 'MYR'} #{format('%.2f', amount.to_d)}"
    end

    def success(exception_folio_ids:, direct_bill_folio_ids:)
      OpenStruct.new(success?: true, exception_folio_ids: exception_folio_ids, direct_bill_folio_ids: direct_bill_folio_ids)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error, exception_folio_ids: [], direct_bill_folio_ids: [])
    end
  end
end
