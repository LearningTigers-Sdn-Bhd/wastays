# frozen_string_literal: true

module HotelPortal
  # Answers "does this tax number belong to this person or company?" while the
  # guest is still at the desk, rather than letting LHDN reject the e-invoice
  # days later. Advisory only - the answer never blocks saving anything.
  class TinValidationsController < HotelPortal::BaseController
    before_action :authorize_check!

    def create
      result = EInvoice::ValidateTin.call(
        tin: params[:tin],
        id_value: params[:id_value],
        document_type: params[:document_type],
        setting: current_hotel.e_invoice_setting
      )

      render json: { status: result.status, message: result.message }
    end

    private

    def authorize_check!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
    end
  end
end
