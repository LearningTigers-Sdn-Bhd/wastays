module Admin
  module HotelParamsHandler
    extend ActiveSupport::Concern

    private

    def create_hotel_params
      params.require(:hotel).permit(:name, :address, :city, :country, :star_rating, :salesperson_id, :preferred_channel_manager).merge(status: "approved")
    end

    def update_hotel_params
      params.require(:hotel).permit(:name, :address, :city, :country, :star_rating, :salesperson_id, :preferred_channel_manager)
    end

    def account_params
      params.require(:account).permit(:name)
    end

    def user_params
      params.require(:user).permit(:name, :email)
    end

    def salesperson_name_param
      params.dig(:hotel, :salesperson_name).to_s.strip
    end

    def salesperson_email_param
      params.dig(:hotel, :salesperson_email).to_s.strip
    end
  end
end
