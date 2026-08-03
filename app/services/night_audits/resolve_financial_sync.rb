# frozen_string_literal: true

require "ostruct"

module NightAudits
  class ResolveFinancialSync
    DEFINITIONS = {
      "payment" => {
        blocker_type: "captured_payment_not_synced",
        item_key: "payment_transaction_id",
        permission: "post_folio_payments"
      },
      "refund" => {
        blocker_type: "refund_not_synced",
        item_key: "refund_request_id",
        permission: "execute_folio_refunds"
      }
    }.freeze

    def self.call(night_audit:, booking:, actor:, kind:, item_id:, reason:)
      new(night_audit:, booking:, actor:, kind:, item_id:, reason:).call
    end

    def initialize(night_audit:, booking:, actor:, kind:, item_id:, reason:)
      @night_audit = night_audit
      @booking = booking
      @actor = actor
      @hotel = night_audit.hotel
      @kind = kind.to_s
      @definition = DEFINITIONS[@kind]
      @item_id = item_id.to_i
      @reason = reason.to_s.strip.presence || "Synchronize #{@kind} from Night Audit verification."
    end

    def call
      return failure("Unsupported financial synchronization type.") unless @definition
      return failure("You do not have permission to manage Night Audit.") unless permission?("manage_night_audit")

      validation_error = validate_context
      return failure(validation_error) if validation_error.present?
      return failure("The selected #{@kind} is not in the current Night Audit blocker set.") unless blocker_item

      ActiveRecord::Base.transaction do
        before = evidence
        result = synchronize
        raise(result&.error || "The #{@kind} could not be synchronized.") unless result&.success?

        evaluation = evaluate
        raise "The #{@kind} still requires financial review." if blocker_item(evaluation)

        NightAudits::Resolutions::RefreshSnapshot.call!(
          night_audit: @night_audit,
          business_date_record: current_business_date,
          evaluation: evaluation
        )
        record_resolution_log!(before:, after: evidence, transaction: result.transaction)
      end

      OpenStruct.new(success?: true, message: "#{@kind.humanize} synchronized to the folio.")
    rescue StandardError => error
      failure(error.message)
    end

    private

    def validate_context
      NightAudits::Resolutions::ValidateContext.call(
        night_audit: @night_audit,
        booking: @booking,
        actor: @actor,
        business_date_record: current_business_date,
        blocker_booking_ids: -> { Array(fresh_items).map { |item| item["booking_id"].to_i } },
        blocker_name: @definition[:blocker_type].humanize,
        permission: @definition[:permission],
        mode: @night_audit.preparing? ? :preparation : :blocked_run
      )
    end

    def synchronize
      if @kind == "payment"
        payment = @booking.payment_transactions.find(@item_id)
        Folios::Payments::RecordPaymentFromGateway.call(payment)
      else
        refund = @booking.refund_request
        raise ActiveRecord::RecordNotFound unless refund&.id == @item_id

        Folios::Payments::RecordRefund.call(refund_request: refund, user: @actor)
      end
    end

    def blocker_item(evaluation = fresh_evaluation)
      Array(evaluation[:blocked_details][@definition[:blocker_type]]).find do |item|
        item[@definition[:item_key]].to_i == @item_id && item["booking_id"].to_i == @booking.id
      end
    end

    def fresh_items
      fresh_evaluation[:blocked_details][@definition[:blocker_type]]
    end

    def fresh_evaluation
      @fresh_evaluation ||= evaluate
    end

    def evaluate
      NightAudits::Evaluate.new(
        hotel: @hotel,
        business_date: @night_audit.business_date,
        phase: @night_audit.preparing? ? :pre_close : :post_close
      ).call
    end

    def evidence
      folio = @booking.booking_folio
      transactions = folio&.folio_transactions&.payment&.to_a || []
      {
        blocker_type: @definition[:blocker_type],
        source_item_id: @item_id,
        matching_folio_transaction_ids: transactions.filter_map do |transaction|
          metadata = transaction.metadata.to_h
          transaction.id if metadata[@definition[:item_key]].to_i == @item_id
        end
      }
    end

    def record_resolution_log!(before:, after:, transaction:)
      NightAudits::RecordLog.call!(
        night_audit: @night_audit,
        user: @actor,
        action_type: "blocker_resolved",
        message: "Synchronized #{@kind} for booking #{@booking.confirmation_token}",
        metadata: {
          blocker_type: @definition[:blocker_type],
          booking_id: @booking.id,
          item_id: @item_id,
          folio_transaction_id: transaction&.id,
          reason: @reason,
          before:,
          after:
        }
      )
    end

    def current_business_date
      @current_business_date ||= @hotel.current_business_date_record
    end

    def permission?(slug)
      return true if @actor&.respond_to?(:superadmin?) && @actor.superadmin?

      @actor&.respond_to?(:has_permission?) && @actor.has_permission?(slug, hotel: @hotel)
    end

    def failure(error)
      OpenStruct.new(success?: false, error:, message: error)
    end
  end
end
