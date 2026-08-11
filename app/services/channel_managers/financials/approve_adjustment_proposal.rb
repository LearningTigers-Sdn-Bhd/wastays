# frozen_string_literal: true

module ChannelManagers
  module Financials
    class ApproveAdjustmentProposal
      Result = ApplicationResult.define(:transactions)

      def self.call(snapshot:, user:)
        new(snapshot:, user:).call
      end

      def initialize(snapshot:, user:)
        @snapshot = snapshot
        @user = user
        @proposal = snapshot.metadata.to_h["adjustment_proposal"].to_h
      end

      def call
        return Result.failure("No pending OTA adjustment proposal exists.") if @proposal["identity"].blank?
        return Result.success(transactions: existing_transactions) if existing_transactions.any?

        transactions = []
        ActiveRecord::Base.transaction do
          @snapshot.lock!
          concurrent = existing_transactions
          if concurrent.any?
            transactions.concat(concurrent)
            next
          end

          @proposal.fetch("allocations").each do |allocation|
            booking = target_bookings.find(allocation.fetch("booking_id"))
            folio = booking.booking_folio || raise("Booking has no folio")
            result = Folios::Transactions::PostStaffTransaction.call(
              folio: folio, user: @user, transaction_type: "adjustment", category: "adjustment",
              amount: allocation.fetch("amount").to_d,
              description: "Approved OTA revision adjustment #{@snapshot.channel_manager_reference}",
              posting_date: @snapshot.hotel.current_business_date || @snapshot.hotel.business_date_for(Time.current),
              options: {
                posting_source: "ota_adjustment_approval",
                metadata: {
                  ota_adjustment_proposal_identity: @proposal.fetch("identity"),
                  ota_financial_snapshot_id: @snapshot.id,
                  approved_by_user_id: @user.id
                }
              }
            )
            unless result.success?
              @error = result.error
              raise ActiveRecord::Rollback
            end

            transactions << result.transaction
          end
        end
        return Result.failure(@error || "OTA adjustment could not be posted.") if transactions.size != @proposal.fetch("allocations").size

        Result.success(transactions: transactions)
      end

      private

      def target_bookings
        @snapshot.booking ? Booking.where(id: @snapshot.booking_id, hotel_id: @snapshot.hotel_id) :
          @snapshot.group_booking.bookings.where(hotel_id: @snapshot.hotel_id)
      end

      def existing_transactions
        FolioTransaction.joins(:booking_folio)
          .where(booking_folios: { booking_id: target_bookings.select(:id) }, voided_by_transaction_id: nil)
          .where("folio_transactions.metadata->>'ota_adjustment_proposal_identity' = ?", @proposal["identity"]).to_a
      end
    end
  end
end
