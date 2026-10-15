# frozen_string_literal: true

module Folios
  class TransferFolios
    include Authorizable
    include Folios::MovementLocking

    Result = ApplicationResult.define(:transactions, :rows, :balances, :preview_token, :routing_previews)

    def self.preview(**attributes)
      new(**attributes).preview
    end

    def self.call(**attributes)
      new(**attributes).call
    end

    def initialize(booking:, actor:, source_folio_ids:, transaction_ids:, target_folio_id:, reason: nil,
      idempotency_key:, route_code_ids: [], preview_token: nil)
      @booking = booking
      @actor = actor
      @source_ids = Array(source_folio_ids).reject(&:blank?).map(&:to_i).uniq.sort
      @transaction_ids = Array(transaction_ids).reject(&:blank?).map(&:to_i).uniq.sort
      @target_id = target_folio_id.to_i
      @reason = reason.to_s.strip
      @key = idempotency_key.to_s
      @route_code_ids = Array(route_code_ids).reject(&:blank?).map(&:to_i).uniq.sort
      @token = preview_token
    end

    def preview
      load_selection!
      error = validation_error
      return failure(error) if error

      rows = expanded_transactions
      balances = (sources + [ target ] + rows.map(&:booking_folio)).uniq(&:id).map do |folio|
        delta = rows.select { |row| row.booking_folio_id == folio.id }.sum { |row| row.payment? ? -row.amount : row.amount }
        delta = -rows.reject { |row| row.booking_folio_id == target.id }.sum { |row| row.payment? ? -row.amount : row.amount } if folio.id == target.id
        { folio: folio, before: folio.outstanding_balance, after: folio.outstanding_balance - delta }
      end
      token = verifier.generate(snapshot, purpose: "folio_transfer", expires_in: 15.minutes)
      Result.success(rows:, balances:, preview_token: token, routing_previews: routing_previews, transactions: [])
    rescue ActiveRecord::RecordNotFound => e
      failure("A selected folio or transaction is unavailable.")
    end

    def call
      return failure("You do not have permission to move folio transactions.") unless permitted?
      return failure("This transfer is missing its idempotency key.") if @key.blank?
      result_rows = []
      ActiveRecord::Base.transaction do
        # Locks the group before reading the completed batch or its reviewed rows.
        @booking.group_booking&.lock!
        Folios::DestinationPolicy.bookings(booking: @booking).order(:id).lock.load
        batch = FolioTransferBatch.find_by(hotel_id: @booking.hotel_id, idempotency_key: @key)
        if batch
          return failure("This idempotency key was already used for a different transfer.") unless batch.request_fingerprint == request_fingerprint
          return Result.success(transactions: FolioTransaction.where(id: batch.result_transaction_ids).order(:id).to_a) if batch.completed_at
        end
        load_selection!
        lock_movement!(folios: sources + [ target ] + expanded_transactions.map(&:booking_folio), transactions: expanded_transactions)
        load_selection!
        error = validation_error
        return failure(error) if error
        reviewed = verifier.verified(@token, purpose: "folio_transfer")
        return failure("This transfer preview changed or expired. Review the transfer again.") unless reviewed == snapshot

        batch ||= FolioTransferBatch.create!(hotel: @booking.hotel, idempotency_key: @key, request_fingerprint: request_fingerprint)
        transactions.each do |transaction|
          result = Folios::Transactions::MoveTransaction.call(transaction:, target_folio: target, user: @actor, reason: operation_reason)
          raise result.error unless result.success?

          result_rows.concat(result.transactions)
        end
        routing_changes.each do |source_booking, routes|
          result = Folios::Routing::ApplyBatch.call(booking: source_booking, actor: @actor, routes:,
            confirmation: "future_only", forecast_confirmation: "reconcile_upcoming", reason: operation_reason,
            idempotency_key: "#{@key}:routes:#{source_booking.id}")
          raise result.error unless result.success?
        end
        batch.update!(result_transaction_ids: result_rows.map(&:id), completed_at: Time.current)
      end
      Result.success(transactions: result_rows)
    rescue StandardError => e
      failure(e.message)
    end

    private

    attr_reader :sources, :transactions, :target

    def operation_reason = @reason.presence || "Folio transfer"

    def load_selection!
      scope = Folios::DestinationPolicy.folios(booking: @booking)
      @sources = scope.where(id: @source_ids).to_a
      @target = scope.find(@target_id)
      @transactions = FolioTransaction.where(booking_folio_id: @source_ids, id: @transaction_ids)
        .includes(:transaction_code, :source_booking, booking_folio: :booking).order(:id).to_a
      @expanded = nil
    end

    def validation_error
      return "You do not have permission to move folio transactions." unless permitted?
      return "This transfer is missing its idempotency key." if @key.blank?
      return "Select at least one source folio." if @source_ids.empty?
      return "A source folio is unavailable." unless sources.size == @source_ids.size
      return "Destination cannot also be a source folio." if @source_ids.include?(target.id)
      return "Select at least one transaction." if @transaction_ids.empty?
      return "A selected transaction is unavailable." unless transactions.size == @transaction_ids.size
      error = Folios::DestinationPolicy.error(booking: @booking, folio: target)
      return error if error
      sources.each do |folio|
        error = Folios::DestinationPolicy.error(booking: @booking, folio:)
        return error if error
      end
      transactions.each do |row|
        error = Folios::Transactions::MovementPolicy.error(row)
        return error if error
      end
      error = expanded_transactions.filter_map do |row|
        Folios::DestinationPolicy.error(booking: @booking, folio: row.booking_folio)
      end.first
      return error if error
      routing_previews.each_value { |result| return result.error unless result.success? }
      nil
    end

    def expanded_transactions
      @expanded ||= transactions.flat_map do |row|
        row.charge? ? [ row, *Folios::Transactions::AttachedTaxTransactions.call(row) ] : [ row ]
      end.uniq(&:id)
    end

    def request_fingerprint
      Digest::SHA256.hexdigest([ @booking.id, @actor&.id, @source_ids, @transaction_ids, @target_id, @reason, @route_code_ids ].to_json)
    end

    def snapshot
      { "request" => request_fingerprint,
        "folios" => (sources + [ target ] + expanded_transactions.map(&:booking_folio)).uniq(&:id).sort_by(&:id).map do |folio|
          [ folio.id, folio.status, folio.booking.reload.group_booking_id, folio.currency,
            folio.outstanding_balance.to_s("F"), folio.updated_at.iso8601(6),
            folio.folio_transactions.order(:id).pluck(:id, :voided_by_transaction_id),
            folio.folio_forecasted_charges.order(:id).pluck(:id, :status) ]
        end,
        "routing" => sources.map(&:booking_id).uniq.sort.map do |booking_id|
          [ booking_id, FolioRoutingRule.where(booking_id:).order(:id).pluck(:id, :target_folio_id, :active, :updated_at).map { |attrs| attrs.map { |value| value.respond_to?(:iso8601) ? value.iso8601(6) : value } } ]
        end }
    end

    def routing_changes
      return {} if @route_code_ids.empty?

      sources.map(&:booking).uniq(&:id).to_h do |source_booking|
        routes = @route_code_ids.to_h do |code_id|
          [ code_id.to_s, { "target_folio_id" => target.id.to_s, "billing_party_id" => target.booking_billing_party_id.to_s } ]
        end
        [ source_booking, routes ]
      end
    end

    def routing_previews
      routing_changes.to_h { |source_booking, routes| [ source_booking, Folios::Routing::ApplyBatch.preview(booking: source_booking, routes:) ] }
    end

    def permitted? = actor_permits?(@actor, "manage_folio_movements", hotel: @booking.hotel)
    def verifier = Rails.application.message_verifier("folio_transfer")
    def failure(error) = Result.failure(error, transactions: [])
  end
end
