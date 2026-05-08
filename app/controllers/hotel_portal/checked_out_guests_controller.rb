class HotelPortal::CheckedOutGuestsController < HotelPortal::BaseController
  def index
    @query = params[:query].to_s.strip

    base_scope = current_hotel.bookings
                              .completed
                              .where(checked_out_at: Date.current.all_day)

    Rails.logger.debug "DEBUG: Date.current=#{Date.current}"
    Rails.logger.debug "DEBUG: Date.current.all_day=#{Date.current.all_day}"
    Rails.logger.debug "DEBUG: All completed bookings checked out today: #{current_hotel.bookings.completed.pluck(:id, :guest_name, :checked_out_at)}"

    @checked_out_count = base_scope.count

    checked_out_scope = base_scope.includes(:booking_rooms, :guests, :booking_guests)

    if @query.present?
      search_term = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      checked_out_scope = checked_out_scope.where(
        "guest_name ILIKE :search OR guest_email ILIKE :search OR guest_phone ILIKE :search OR confirmation_token ILIKE :search",
        search: search_term
      )
    end

    @all_checked_out_guests = checked_out_scope.order(checked_out_at: :desc, created_at: :desc)
    @checked_out_guests = @all_checked_out_guests.page(params[:page]).per(25)
  end
end
