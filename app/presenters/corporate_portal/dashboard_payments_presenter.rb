# frozen_string_literal: true

module CorporatePortal
  # The "bookings awaiting payment" panel on the corporate dashboard.
  #
  # An agent's outstanding AR balance and their unpaid bookings are different
  # debts with different consequences -- an overdue invoice is chased, an unpaid
  # booking loses the rooms -- so the dashboard states them separately rather
  # than adding them together.
  #
  # Totals are grouped by currency because an agency may be linked to hotels
  # selling in different ones, and summing across them would be meaningless.
  class DashboardPaymentsPresenter
    PREVIEW_LIMIT = 5

    def initialize(relation:, now: Time.current)
      @relation = relation
      @now = now
    end

    attr_reader :now

    def any? = bookings.any?

    def count = bookings.size

    def overdue_count = bookings.count { |booking| presenter_for(booking).overdue? }

    def under_review_count = bookings.count { |booking| presenter_for(booking).under_review? }

    def totals_by_currency
      @totals_by_currency ||= bookings
        .group_by(&:currency)
        .transform_values { |group| group.sum { |booking| booking.total_amount.to_d } }
    end

    # Soonest first -- the query already orders by deadline -- so the rows the
    # agent has least time to act on are the ones shown.
    def preview = bookings.first(PREVIEW_LIMIT)

    def more_count = [ count - PREVIEW_LIMIT, 0 ].max

    def presenter_for(booking)
      presenters.fetch(booking.id)
    end

    private

    # Submissions are preloaded here rather than looked up per row: the payment
    # chip asks about them for every booking on the panel.
    def bookings
      @bookings ||= BookingsAwaitingPaymentQuery.call(relation: @relation)
        .includes(:hotel, :ar_payment_submissions, :hotel_corporate_account)
        .to_a
    end

    def presenters
      @presenters ||= bookings.index_by(&:id).transform_values do |booking|
        BookingPaymentPresenter.new(booking, now: now)
      end
    end
  end
end
