# frozen_string_literal: true

module Admin
  module Hotels
    class CreateForm
      include ActiveModel::Model

      attr_accessor :account_name, :user_name, :user_email, :hotel_name, :address, :city, :country, :star_rating, :salesperson_id, :preferred_channel_manager, :amenities, :sell_mode, :allow_boat_information

      validates :account_name, :user_name, :user_email, :hotel_name, :city, :country, :sell_mode, presence: true
      validates :sell_mode, inclusion: { in: ->(_) { RatePlan.sell_modes } }, allow_blank: true

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

      # The admin form renders a Hotel record, so validation failures have to
      # reach it: the summary reads hotel.errors, and each field asks the record
      # for its own message. Form attributes that exist on Hotel are copied
      # across so they surface inline; the ones that don't (account_name,
      # user_email, hotel_name) have no field to attach to and land on :base.
      def hotel
        @hotel ||= Hotel.new(hotel_attributes).tap do |record|
          errors.each do |error|
            if record.respond_to?(error.attribute)
              record.errors.add(error.attribute, error.message)
            else
              record.errors.add(:base, error.full_message)
            end
          end
        end
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
          sell_mode: sell_mode,
          allow_boat_information: allow_boat_information.nil? ? true : ActiveModel::Type::Boolean.new.cast(allow_boat_information)
        }
      end
    end
  end
end
