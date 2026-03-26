module Admin
  class BookingsController < BaseController
    def index
      @bookings = Booking.all.order(created_at: :desc)
      if params[:status].present? && Booking::STATUSES.include?(params[:status])
        @bookings = @bookings.where(status: params[:status])
      end
      @bookings = @bookings.page(params[:page]) if defined?(Kaminari)
    end

    def show
      @booking = Booking.find(params[:id])
    end
  end
end
