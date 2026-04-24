module Admin
  class BookingsController < BaseController
    def index
      @all_bookings = Booking.all.order(created_at: :desc)

      # Apply filters
      if params[:status].present? && params[:status] != "All Status"
        @all_bookings = @all_bookings.where(status: params[:status].downcase.gsub(" ", "_"))
      end
      @all_bookings = @all_bookings.search(params[:q]) if params[:q].present?

      @bookings = @all_bookings.page(params[:page]).per(25)

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def show
      @booking = Booking.find(params[:id])
    end
  end
end
