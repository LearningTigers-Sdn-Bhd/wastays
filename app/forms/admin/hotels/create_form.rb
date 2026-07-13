# frozen_string_literal: true

module Admin
  module Hotels
    class CreateForm
      include ActiveModel::Model

      attr_accessor :account_name, :user_name, :user_email, :hotel_name, :address, :city, :country, :star_rating, :salesperson_id, :preferred_channel_manager, :amenities, :allow_pax_pricing

      validates :account_name, :user_name, :user_email, :hotel_name, :city, :country, presence: true

      def save
        return false unless valid?

        result = HotelOps::CreateHotel.new(
          account_params: { name: account_name },
          user_params: { name: user_name, email: user_email },
          hotel_params: hotel_attributes
        ).call

        if result[:success]
          @hotel = result[:hotel]
          true
        else
          errors.add(:base, result[:error])
          false
        end
      end

      def hotel
        @hotel || Hotel.new(hotel_attributes)
      end

      private

      def hotel_attributes
        {
          name: hotel_name,
          address: address,
          city: city,
          country: country,
          star_rating: star_rating,
          salesperson_id: salesperson_id,
          preferred_channel_manager: preferred_channel_manager,
          amenities: amenities || [],
          status: "approved",
          allow_pax_pricing: ActiveModel::Type::Boolean.new.cast(allow_pax_pricing) || false
        }
      end
    end
  end
end
