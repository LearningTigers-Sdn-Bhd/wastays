# frozen_string_literal: true

class HotelPortal::RefundRequestsController < HotelPortal::BaseController
  before_action :set_booking

  def new
    @eligibility = Refunds::Eligibility.new(@booking).call

    unless @eligibility.success?
      render turbo_stream: turbo_stream.append("toasts_container", partial: "shared/toast", locals: { key: "alert", value: @eligibility.error })
      return
    end

    @refund_request = RefundRequest.new(
      booking: @booking,
      refund_amount: @eligibility.suggested_amount
    )

    respond_to do |format|
      format.turbo_stream
      format.html
    end
  end

  def create
    @eligibility = Refunds::Eligibility.new(@booking).call
    unless @eligibility.success?
      redirect_to hotel_booking_path(current_hotel, @booking), alert: @eligibility.error
      return
    end

    @refund_request = RefundRequest.new(refund_request_params)
    @refund_request.booking = @booking
    @refund_request.status = "pending"

    if @refund_request.save
      redirect_to hotel_booking_path(current_hotel, @booking), notice: "Refund request submitted to Superadmin."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_booking
    @booking = current_hotel.bookings.find(params[:booking_id])
  end

  def refund_request_params
    params.require(:refund_request).permit(:reason, :bank_name, :account_holder_name, :account_number, :account_type, :refund_amount)
  end
end
