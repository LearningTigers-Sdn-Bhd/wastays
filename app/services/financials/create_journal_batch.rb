# frozen_string_literal: true

module Financials
  class CreateJournalBatch
    def self.call(hotel:, business_date:)
      new(hotel: hotel, business_date: business_date).call
    end

    def initialize(hotel:, business_date:)
      @hotel = hotel
      @business_date = business_date
    end

    def call
      ActiveRecord::Base.transaction do
        batch = @hotel.journal_batches.find_or_initialize_by(business_date: @business_date)
        batch.entries.destroy_all
        batch.status = "finalized"
        batch.finalized_at = Time.current

        transactions = FolioTransaction.joins(:booking_folio)
                                       .where(booking_folios: { hotel_id: @hotel.id })
                                       .where(posting_date: @business_date)

        missing_gl_count = transactions.where(gl_code: nil).count
        if missing_gl_count.positive?
          batch.errors.add(:base, "Cannot create journal batch: #{missing_gl_count} folio transactions are missing General Ledger Codes (GL Codes)")
          raise ActiveRecord::RecordInvalid, batch
        end

        grouped = transactions.group(:gl_code, :transaction_type).sum(:amount)

        summary_data = {
          total_transactions: transactions.count,
          gl_summaries: {}
        }

        grouped.each do |(gl_code, type), total|
          entry = batch.entries.build(
            gl_code: gl_code,
            transaction_type: type,
            description: "Daily summary for #{gl_code} (#{type})"
          )

          # Basic accounting logic:
          # Charges (Revenue) -> Credit
          # Payments (Bank/Cash) -> Debit (Refunds are negative payments)
          # Adjustments -> Debit if negative (write-offs), Credit if positive
          if type == "charge"
            entry.credit_amount = total
            entry.debit_amount = 0
          elsif type == "payment"
            if total.positive?
              entry.debit_amount = total
              entry.credit_amount = 0
            else
              entry.debit_amount = 0
              entry.credit_amount = total.abs
            end
          else # adjustment
            if total.positive?
              entry.credit_amount = total
              entry.debit_amount = 0
            else
              entry.debit_amount = total.abs
              entry.credit_amount = 0
            end
          end

          summary_data[:gl_summaries][gl_code] ||= { debit: 0, credit: 0 }
          summary_data[:gl_summaries][gl_code][:debit] += entry.debit_amount
          summary_data[:gl_summaries][gl_code][:credit] += entry.credit_amount
        end

        batch.summary_data = summary_data
        batch.save!
        batch
      end
    end
  end
end
