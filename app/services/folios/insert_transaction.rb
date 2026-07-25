# frozen_string_literal: true


module Folios
  class InsertTransaction
    include Authorizable

    def initialize(booking_folio:, amount:, transaction_type:, category:, user:, description: nil, posting_date: nil, catch_up_key: nil, options: {})
      @booking_folio = booking_folio
      @amount = amount.to_d
      @transaction_type = transaction_type.to_s
      @category = category.to_s
      @user = user
      @description = description
      @posting_date = posting_date || @booking_folio.hotel.current_business_date
      @options = options
      @transaction_code = options[:transaction_code]
      @catch_up_key = catch_up_key.presence || @options[:catch_up_key].presence
    end

    def call
      @booking_folio.with_lock do
        @booking_folio.reload

        override_error = validate_override_context
        return failure(override_error) if override_error.present?

        permission_error = validate_staff_permission
        return failure(permission_error) if permission_error.present?

        if @booking_folio.status == "closed" && !@options[:override_closed_folio]
          return failure("Folio is closed. Please provide an override flag to post to a closed folio.")
        end

        guard_error = validate_business_date_posting
        return failure(guard_error) if guard_error.present?

        transaction = @booking_folio.folio_transactions.build(
          amount: @amount,
          transaction_type: @transaction_type,
          category: @category,
          user: @user,
          description: @description,
          posting_date: @posting_date,
          posted_at: @options[:posted_at] || Time.current,
          currency: @options[:currency] || @booking_folio.booking.currency,
          reversal_of_transaction: @options[:reversal_of_transaction],
          parent_transaction: @options[:parent_transaction],
          split_from_transaction: @options[:split_from_transaction],
          moved_from_transaction: @options[:moved_from_transaction],
          correction_reason: @options[:correction_reason],
          correction_note: @options[:correction_note],
          night_audit: @options[:night_audit],
          catch_up_key: @catch_up_key,
          transfer_group_id: @options[:transfer_group_id],
          operation_key: @options[:operation_key],
          transaction_code: @transaction_code,
          metadata: transaction_metadata
        )

        if transaction.save
          record_financial_audit_event!(transaction)
          success(transaction)
        else
          failure(transaction.errors.full_messages.to_sentence)
        end
      end
    rescue StandardError => e
      failure(e.message)
    end

    private

    def validate_override_context
      return unless override_requested?
      return "Override postings require a user." if @user.blank? && !@options[:system_posting]
      return "Override reason can't be blank." if @options[:correction_reason].to_s.strip.blank?
      return "Override note can't be blank." if @options[:correction_note].to_s.strip.blank?

      nil
    end

    def validate_staff_permission
      return if @options[:system_posting] || @user.nil?
      return if %w[night_audit no_show].include?(posting_source)

      permission = if @options[:reversal_of_transaction].present?
                     "post_folio_corrections"
      else
                     FolioTransaction.permission_for(@transaction_type, @category)
      end

      return if permission.blank?
      return if actor_permits?(@user, permission, hotel: @booking_folio.hotel)

      "You do not have permission to post this transaction (#{permission})."
    end

    def validate_business_date_posting
      FinancialControls::PostingGuard.call!(
        hotel: @booking_folio.booking.hotel,
        business_date: @posting_date,
        actor: @user,
        posting_source: posting_source,
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

    def override_requested?
      @options[:override_closed_folio] || @options[:override_night_audit]
    end

    def transaction_metadata
      metadata = (@options[:metadata] || {}).merge(posted_by_user_id: @user&.id)
      metadata[:catch_up_key] ||= @catch_up_key if @catch_up_key.present?
      metadata[:night_audit_id] = @options[:night_audit].id if @options[:night_audit].present?
      metadata[:posting_source] ||= @options[:posting_source] if @options[:posting_source].present?
      metadata[:blocker_resolution] ||= @options[:blocker_resolution] if @options[:blocker_resolution].present?
      return metadata unless override_requested?

      metadata.merge(
        override_closed_folio: !!@options[:override_closed_folio],
        override_night_audit: !!@options[:override_night_audit],
        system_posting: !!@options[:system_posting],
        override_reason: @options[:correction_reason].to_s,
        override_note: @options[:correction_note].to_s
      )
    end

    def posting_source
      @options[:posting_source].presence || (@options[:metadata] || {})[:posting_source].presence || "staff"
    end

    def record_financial_audit_event!(transaction)
      FinancialControls::AuditEventRecorder.call!(
        hotel: @booking_folio.booking.hotel,
        business_date: @posting_date,
        event_type: financial_audit_event_type,
        source: posting_source,
        actor: @user,
        folio_transaction: transaction,
        reason: @options[:correction_reason],
        metadata: financial_audit_metadata(transaction)
      )
    end

    def financial_audit_event_type
      return "audit_blocker_resolution_posted" if posting_source == "audit_blocker_resolution"
      return "closed_date_override_posted" if @options[:override_night_audit]
      return "folio_transaction_reversed" if posting_source == "reversal"

      "folio_transaction_created"
    end

    def financial_audit_metadata(transaction)
      {
        transaction_type: transaction.transaction_type,
        category: transaction.category,
        posting_source: posting_source,
        description: transaction.description,
        correction_reason: transaction.correction_reason,
        correction_note: transaction.correction_note,
        override_closed_folio: !!@options[:override_closed_folio],
        override_night_audit: !!@options[:override_night_audit],
        blocker_resolution: @options[:blocker_resolution]
      }.compact.merge(transaction.metadata || {})
    end

    def success(transaction)
      Folios::TransactionResult.success(transaction: transaction)
    end

    def failure(error)
      Folios::TransactionResult.failure(error)
    end
  end
end
