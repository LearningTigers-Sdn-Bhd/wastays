# frozen_string_literal: true

module HotelPortal
  class ArPaymentAllocationReversalsController < BaseController
    before_action :authorize_manage_ar_payments!

    def create
      payment = current_hotel.ar_payments.find(params[:ar_payment_id])
      allocation = payment.ar_payment_allocations.find(params[:allocation_id])
      result = ::ArPayments::ReverseAllocation.call(
        allocation: allocation,
        user: current_user,
        reason: params[:reason]
      )

      if result.success?
        redirect_to hotel_ar_payment_path(current_hotel, payment), notice: "Payment allocation reversed."
      else
        redirect_to hotel_ar_payment_path(current_hotel, payment), alert: result.error
      end
    end

    private

    def authorize_manage_ar_payments!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_ar_payments", hotel: current_hotel)
    end
  end
end
