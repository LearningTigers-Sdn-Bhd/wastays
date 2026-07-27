# frozen_string_literal: true


module Folios
  module Checkout
    class CloseForCheckout
      def self.call(booking:, user:, checked_out_at: Time.current, options: {})
        new(booking: booking, user: user, checked_out_at: checked_out_at, options: options).call
      end

      def initialize(booking:, user:, checked_out_at: Time.current, options: {})
        @booking = booking
        @user = user
        @checked_out_at = checked_out_at
        @options = options
        @exception_folio_ids = Array(@options[:exception_folio_ids]).map(&:to_i)
        @direct_bill_folio_ids = Array(@options[:direct_bill_folio_ids]).map(&:to_i)
      end

      def call
        folios = @booking.booking_folios.includes(:folio_forecasted_charges, :folio_transactions).to_a
        return failure("Booking has no folio.") if folios.empty?
        primary_folio = @booking.booking_folio || folios.first

        @booking.with_lock do
          folios.each(&:lock!)
          folios.each(&:reload)
          if folios.any?(&:closed?) && !multi_folio_exception_checkout?
            message = folios.one? ? "Folio is already closed." : "One or more folios are already closed."
            return failure(message, folio: primary_folio)
          end
          return failure("Voided folios cannot be checked out.", folio: primary_folio) if folios.any?(&:voided?)

          posting_guard_error = validate_checkout_business_date(primary_folio)
          return failure(posting_guard_error, folio: primary_folio) if posting_guard_error.present?

          sync_error = sync_payment_and_refund_state(primary_folio)
          return failure(sync_error, folio: primary_folio) if sync_error.present?

          folios.each { |folio| Folios::Forecasts::SyncForecastedCharges.call(booking_folio: folio) }
          folios.each(&:reload)

          missing_charges_error = validate_all_nights_posted(folios)
          return failure(missing_charges_error, folio: primary_folio) if missing_charges_error.present?

          balances = folios.index_with { |folio| calculate_fresh_balance(folio) }
          closable_folios = folios.reject { |folio| exception_folio?(folio) || folio.closed? }
          invalid_closable = closable_folios.find { |folio| invalid_closable_balance?(folio, balances.fetch(folio)) }
          if invalid_closable.present?
            balance = balances.fetch(invalid_closable)
            return legacy_balance_failure(balance, primary_folio, balances) unless multi_folio_exception_checkout?

            return failure("Cannot check out with #{invalid_closable.display_name} balance of #{formatted_balance(balance)}.", folio: primary_folio, balance: total_balance(balances))
          end

          guest_exception = folios.find { |folio| guest_folio?(folio) && exception_folio?(folio) }
          return failure("#{guest_exception.display_name}: guest folio must be financially resolved before checkout.", folio: primary_folio, balance: total_balance(balances)) if guest_exception.present?

          invoice_num = HotelCounter.increment!(hotel: primary_folio.hotel, type: "invoice")
          closable_folios.each do |folio|
            attributes = { status: "closed", closed_at: Time.current, closed_by: @user }
            attributes[:invoice_number] = invoice_num if folio.id == primary_folio.id
            folio.update!(attributes)
            ar_invoice = create_direct_bill_ar_invoice!(folio, balances.fetch(folio)) if direct_bill_folio?(folio)
            record_financial_audit_event!(folio, balances.fetch(folio))
            record_direct_bill_audit_event!(folio, ar_invoice, balances.fetch(folio)) if ar_invoice.present?
          end
          success(folio: primary_folio.reload, balance: total_balance(balances))
        end
      rescue ActiveRecord::RecordInvalid => e
        failure(e.record.errors.full_messages.to_sentence)
      end

      private

      def validate_checkout_business_date(folio)
        business_date = folio.hotel.current_business_date
        FinancialControls::PostingGuard.call!(
          hotel: folio.hotel,
          business_date: business_date,
          actor: @user,
          posting_source: @options[:posting_source].presence || "checkout",
          override: @options[:override_night_audit],
          override_reason: @options[:correction_reason],
          permission_context: @options[:permission_context] || @user,
          blocker_resolution: @options[:blocker_resolution],
          system_posting: !!@options[:system_posting]
        )
        nil
      rescue FinancialControls::PostingGuard::PostingBlocked => e
        e.message
      end

      def validate_all_nights_posted(folios)
        checkout_date = Bookings::ScheduledStay.local_date(hotel: @booking.hotel, value: @booking.check_out)
        unsettled = FolioForecastedCharge.where(booking_folio_id: folios.map(&:id)).forecast
          .where(arel_table[:stay_date].lt(checkout_date))
          .reject { |forecast| matching_posted_charge_exists?(forecast) }
        return if unsettled.none?

        dates = unsettled.map(&:stay_date).uniq.sort
        "Missing nightly charges for: #{dates.map { |d| d.strftime('%d %b') }.join(', ')}. Please ensure all nightly charges are posted before checkout."
      end

      def matching_posted_charge_exists?(forecast)
        nightly_key = Folios::Charges::ChargePostingKeys.nightly_charge_key(
          booking: @booking,
          date: forecast.stay_date,
          charge_kind: forecast.charge_kind,
          identity: forecast.identity
        )
        catch_up_key = Folios::Charges::ChargePostingKeys.catch_up_charge_key(
          booking: @booking,
          date: forecast.stay_date,
          charge_kind: forecast.charge_kind,
          identity: forecast.identity
        )

        FolioTransaction.joins(:booking_folio)
          .where(booking_folios: { booking_id: @booking.id })
          .charge
          .where(voided_by_transaction_id: nil)
          .where(
            "metadata->>'nightly_charge_key' = :nightly_key OR catch_up_key = :catch_up_key OR metadata->>'catch_up_key' = :catch_up_key",
            nightly_key: nightly_key,
            catch_up_key: catch_up_key
          )
          .exists?
      end

      def arel_table
        FolioForecastedCharge.arel_table
      end

      def calculate_fresh_balance(folio)
        charges = FolioTransaction.charge.where(booking_folio_id: folio.id).sum(:amount)
        payments = FolioTransaction.payment.where(booking_folio_id: folio.id).sum(:amount)
        adjustments = FolioTransaction.adjustment.where(booking_folio_id: folio.id).sum(:amount)

        charges.to_d - payments.to_d + adjustments.to_d
      end

      def multi_folio_exception_checkout?
        @options.key?(:exception_folio_ids)
      end

      def exception_folio?(folio)
        @exception_folio_ids.include?(folio.id)
      end

      def direct_bill_folio?(folio)
        @direct_bill_folio_ids.include?(folio.id)
      end

      def invalid_closable_balance?(folio, balance)
        return false if balance.zero?
        return !valid_direct_bill_close?(folio, balance) if direct_bill_folio?(folio)

        true
      end

      def valid_direct_bill_close?(folio, balance)
        relationship = folio.hotel_corporate_account
        folio.payer_type == "company" &&
          balance.positive? &&
          relationship.present? &&
          relationship.active? &&
          relationship.direct_bill_enabled? &&
          folio.ar_invoice.blank?
      end

      def create_direct_bill_ar_invoice!(folio, balance)
        Folios::Lifecycle::CreateDirectBillArInvoice.call!(folio: folio, balance: balance)
      end

      def guest_folio?(folio)
        folio.folio_type == "guest" && folio.payer_type == "guest"
      end

      def total_balance(balances)
        balances.values.sum(&:to_d)
      end

      def legacy_balance_failure(balance, primary_folio, balances)
        if balance.positive?
          failure("Cannot check out with outstanding balance of #{formatted_balance(balance)}.", folio: primary_folio, balance: total_balance(balances))
        else
          failure("Cannot check out with credit balance of #{formatted_balance(balance)}. Process refund or adjustment first.", folio: primary_folio, balance: total_balance(balances))
        end
      end

      def sync_payment_and_refund_state(folio)
        @booking.payment_transactions.where(status: "captured").find_each do |payment_transaction|
          next if payment_synced?(folio, payment_transaction)

          result = Folios::Payments::RecordPaymentFromGateway.call(payment_transaction)
          folio.reload
          next if result&.success? && payment_synced?(folio, payment_transaction)

          return "Cannot check out: captured payment is not synced to the folio."
        end

        refund_request = @booking.refund_request
        if refund_request&.completed? && !refund_synced?(folio, refund_request)
          result = Folios::Payments::RecordRefund.call(
            refund_request: refund_request,
            user: @user,
            options: { posting_source: "sync", system_posting: true }
          )
          folio.reload
          unless result&.success? && refund_synced?(folio, refund_request)
            return "Cannot check out: completed refund is not synced to the folio."
          end
        end

        nil
      end

      def payment_synced?(folio, payment_transaction)
        expected_amount = payment_transaction.amount_subunits.to_d / 100.0

        folio.folio_transactions.payment.any? do |transaction|
          transaction.metadata["payment_transaction_id"].to_s == payment_transaction.id.to_s &&
            transaction.amount.to_d == expected_amount
        end
      end

      def refund_synced?(folio, refund_request)
        expected_amount = -refund_request.refund_amount.to_d

        folio.folio_transactions.payment.any? do |transaction|
          transaction.metadata["refund_request_id"].to_s == refund_request.id.to_s &&
            transaction.amount.to_d == expected_amount
        end
      end

      def formatted_balance(balance)
        "#{@booking.currency.presence || 'MYR'} #{format('%.2f', balance)}"
      end

      def record_financial_audit_event!(folio, balance)
        FinancialControls::AuditEventRecorder.call!(
          hotel: folio.hotel,
          business_date: folio.hotel.current_business_date,
          event_type: "folio_closed_for_checkout",
          source: "checkout",
          actor: @user,
          booking_folio: folio,
          booking: @booking,
          amount: balance,
          currency: @booking.currency,
          metadata: {
            invoice_number: folio.invoice_number,
            balance: balance.to_s,
            checked_out_at: checked_out_at_for_metadata
          }
        )
      end

      def record_direct_bill_audit_event!(folio, ar_invoice, balance)
        relationship = folio.hotel_corporate_account
        FinancialControls::AuditEventRecorder.call!(
          hotel: folio.hotel,
          business_date: folio.hotel.current_business_date,
          event_type: "direct_bill_folio_closed",
          source: "checkout",
          actor: @user,
          booking_folio: folio,
          booking: @booking,
          amount: balance,
          currency: folio.currency,
          metadata: {
            ar_invoice_id: ar_invoice.id,
            ar_invoice_number: ar_invoice.invoice_number,
            hotel_corporate_account_id: relationship.id,
            corporate_account_id: relationship.corporate_account_id,
            due_on: ar_invoice.due_on.iso8601,
            settlement_method: "direct_bill"
          }
        )
      end

      def checked_out_at_for_metadata
        return @checked_out_at.iso8601 if @checked_out_at.respond_to?(:iso8601)

        @checked_out_at.to_s
      end

      def success(folio:, balance: 0.to_d)
        Folios::Checkout::CheckoutResult.success(folio: folio, balance: balance)
      end

      def failure(error, folio: nil, balance: nil)
        Folios::Checkout::CheckoutResult.failure(error, folio: folio, balance: balance)
      end
    end
  end
end
