# frozen_string_literal: true

module HotelPortal
  class ArPaymentVoidsController < BaseController
    before_action :authorize_manage_ar_payments!

    def create
      payment = current_hotel.ar_payments.find(params[:ar_payment_id])
      result = ::ArPayments::Void.call(payment: payment, user: current_user, reason: params[:reason])

      if result.success?
        redirect_to hotel_ar_payment_path(current_hotel, payment), notice: "Payment voided."
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
