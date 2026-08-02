# frozen_string_literal: true


module Folios
  module Checkout
    class ProcessCheckoutActions
      include Authorizable

      PAYMENT_ACTION = "pay_now"
      DIRECT_BILL_ACTION = "direct_bill"
      CLOSE_ACTION = "close"
      CLOSED_ACTION = "closed"
      VOIDED_ACTION = "voided"
      BLOCKING_ACTIONS = %w[refund_credit_handling voided].freeze
      EXCEPTION_ACTIONS = %w[keep_open manager_review write_off_approval].freeze

      # Which folios checkout should treat as exceptions, and which it should send
      # to direct bill. Checkout reads both lists back when it closes the booking.
      Result = ApplicationResult.define(:exception_folio_ids, :direct_bill_folio_ids)

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

        readiness = Folios::Checkout::BookingCheckoutReadiness.call(booking: @booking, hotel: @hotel)
        pending_error = pending_charge_error(readiness)
        return pending_error if pending_error.present?

        pending_direct_bill_amounts = Hash.new(0.to_d)
        folios.each do |folio|
          action = action_for(folio)
          balance = folio.projected_outstanding_balance.to_d
          allowed_actions = allowed_actions_for(folio, balance)

          return "#{folio.display_name}: checkout action is required." if action.blank?
          return "#{folio.display_name}: #{action.humanize} is not allowed." unless allowed_actions.include?(action)

          # Already-closed folios are settled history — nothing left to resolve.
          next if action == CLOSED_ACTION
          return "#{folio.display_name}: refund / credit handling must be completed before checkout." if action == "refund_credit_handling"
          return "#{folio.display_name}: cannot check out while folio is voided." if action == "voided"

          if action == PAYMENT_ACTION
            return "#{folio.display_name}: settle the folio balance before checkout."
          end

          if action == DIRECT_BILL_ACTION
            return "#{folio.display_name}: Direct Bill is not available." unless direct_bill_enabled?(folio)
            return "#{folio.display_name}: Direct Bill requires a positive balance." unless balance.positive?

            key = [ folio.hotel_corporate_account_id, folio.currency ]
            pending_direct_bill_amounts[key] += balance
            authorization = authorize_credit_exposure(folio, pending_direct_bill_amounts[key])
            return "#{folio.display_name}: #{authorization.error}" unless authorization.success?
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
        return [ CLOSED_ACTION ] if folio.closed?
        return [ VOIDED_ACTION ] if folio.voided?

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
        return CLOSED_ACTION if folio.closed?
        return VOIDED_ACTION if folio.voided?

        balance = folio.projected_outstanding_balance.to_d
        submitted_action = params_for(folio)[:action].to_s
        return CLOSE_ACTION if balance.zero? && (guest_folio?(folio) || submitted_action.present?)

        if guest_folio?(folio)
          if balance.positive?
            PAYMENT_ACTION
          else
            "refund_credit_handling"
          end
        else
          submitted_action
        end
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

      def authorize_credit_exposure(folio, balance)
        ArInvoices::AuthorizeCreditExposure.call(
          hotel_corporate_account: folio.hotel_corporate_account,
          pending_amount: balance,
          pending_currency: folio.currency,
          user: @user,
          override: params_for(folio)[:credit_override],
          override_reason: params_for(folio)[:credit_override_reason]
        )
      end

      def success(exception_folio_ids:, direct_bill_folio_ids:)
        Result.success(exception_folio_ids: exception_folio_ids, direct_bill_folio_ids: direct_bill_folio_ids)
      end

      def failure(error)
        Result.failure(error, exception_folio_ids: [], direct_bill_folio_ids: [])
      end
    end
  end
end
