# frozen_string_literal: true

module ArInvoices
  class RefreshOverdueStatuses
    def self.call(hotel:, as_of_date: nil)
      new(hotel: hotel, as_of_date: as_of_date).call
    end

    def initialize(hotel:, as_of_date: nil)
      @hotel = hotel
      @as_of_date = (as_of_date.presence || hotel.current_business_date).to_date
    end

    def call
      scope.update_all(status: "overdue", updated_at: Time.current)
    end

    private

    def scope
      @hotel.receivables
        .with_open_balance
        .where(status: %w[open partially_paid])
        .where(ArInvoice.arel_table[:due_on].lt(@as_of_date))
    end
  end
end
