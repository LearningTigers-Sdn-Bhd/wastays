class Public::QuotesController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def create
    result = BookingEngine::CreateQuote.new(quote_params).call

    if result.success?
      redirect_to quote_path(result.quote.token)
    else
      redirect_back fallback_location: root_path, alert: result.message
    end
  end

  def show
    @quote = BookingQuote.find_by!(token: params[:id])

    if @quote.expires_at < Time.current
      flash[:alert] = "Your quote has expired. Please search again."
      redirect_to root_path
    end

    @hotel = @quote.hotel
    @quote_items = @quote.booking_quote_items
  end

  private

  def quote_params
    params.permit(:hotel_id, :room_type_id, :check_in, :check_out, :adults, :children, :room_count)
  end
end
