# frozen_string_literal: true

module HotelPortal
  module Bookings
    # One agent booking's payment schedule as the desk sees it: each stage with
    # what was promised, what became of it, and which actions the signed-in user
    # may take. The folio holds the money; this only reads it.
    class AgentPaymentsPresenter
      Row = Data.define(
        :instalment, :stage, :amount, :due, :status_label, :badge_variant, :detail,
        :outstanding, :can_mark_paid, :can_refund, :can_reopen
      )

      STATUS_LABELS = { "pending" => "Owed", "paid" => "Paid", "refunded" => "Refunded", "waived" => "Waived" }.freeze
      BADGE_VARIANTS = { "pending" => :warning, "paid" => :success, "refunded" => :neutral, "waived" => :neutral }.freeze

      attr_reader :booking

      def initialize(booking:, user:, hotel: booking.hotel)
        @booking = booking
        @user = user
        @hotel = hotel
      end

      def rows
        @rows ||= progress.instalments.map { |instalment| row_for(instalment) }
      end

      def reference = booking.formatted_reservation_number

      def total_label = money(booking.total_amount)
      def paid_label = money(progress.paid_total)
      def owed_label = money(progress.owed_total)

      def payment_method_options
        ::Bookings::PaymentInstalments::MarkPaid::PAYMENT_METHODS.map { |key, label| { label: label, value: key } }
      end

      def refund_source_options
        ::Folios::Payments::RefundSource.options.map { |label, value| { label: label, value: value } }
      end

      # A sensible starting point for a reopened stage: the hotel's usual hold
      # from today, as a date in the hotel's own zone.
      def default_reopen_date
        (Time.current + @hotel.agent_payment_hold_hours.hours).in_time_zone(@hotel.hotel_time_zone).to_date
      end

      def earliest_reopen_date = Time.current.in_time_zone(@hotel.hotel_time_zone).to_date + 1

      private

      def progress = @progress ||= ::Bookings::PaymentProgress.new(booking)

      def row_for(instalment)
        Row.new(
          instalment: instalment,
          stage: instalment.stage_label,
          amount: money(instalment.amount),
          due: instalment.due_at.in_time_zone(@hotel.hotel_time_zone).strftime("%d %b %Y, %-l.%M%P %Z"),
          status_label: STATUS_LABELS.fetch(instalment.status),
          badge_variant: BADGE_VARIANTS.fetch(instalment.status),
          detail: detail_for(instalment),
          outstanding: money(progress.outstanding_through(instalment)),
          can_mark_paid: instalment.status_pending? && !booking.closed? && earlier_stages_settled?(instalment) && permitted?("post_folio_payments"),
          can_refund: instalment.status_paid? && permitted?("execute_folio_refunds"),
          can_reopen: instalment.status_refunded? && !booking.closed? && permitted?("manage_ar_payments")
        )
      end

      def detail_for(instalment)
        case instalment.status
        when "paid" then paid_detail(instalment)
        when "refunded" then "Refunded #{stamp(instalment.refunded_at)}#{by(instalment.refunded_by)}: #{instalment.refund_reason}"
        else instalment.note
        end
      end

      def paid_detail(instalment)
        return instalment.note if instalment.paid_at.blank?

        [ "Paid #{stamp(instalment.paid_at)}#{by(instalment.paid_by)}", instalment.note ].compact.join(". ")
      end

      def earlier_stages_settled?(instalment)
        progress.instalments.none? { |other| other.position < instalment.position && other.status_pending? }
      end

      def permitted?(slug)
        @user.present? && @user.has_permission?(slug, hotel: @hotel)
      end

      def by(user) = user.present? ? " by #{user.name}" : ""

      def stamp(time) = time.in_time_zone(@hotel.hotel_time_zone).strftime("%d %b %Y")

      def money(amount)
        "#{booking.currency} #{ActiveSupport::NumberHelper.number_to_rounded(amount, precision: 2, delimiter: ',')}"
      end
    end
  end
end
