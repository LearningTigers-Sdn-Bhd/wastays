module Admin
  class BookingsController < BaseController
    def index
      @all_bookings = Booking.all.order(created_at: :desc)
      if params[:status].present? && Booking::STATUSES.include?(params[:status])
        @all_bookings = @all_bookings.where(status: params[:status])
      end
      @bookings = @all_bookings.page(params[:page])
    end

    def show
      @booking = Booking.find(params[:id])
    end
  end
end
