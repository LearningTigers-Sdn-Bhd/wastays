# frozen_string_literal: true

module HotelPortal
  class ActiveHousekeepersQuery
    def initialize(hotel:)
      @hotel = hotel
    end

    def call
      User.where(id: UserHotelAccess.active
                                     .where(hotel_id: @hotel.id)
                                     .joins(:role)
                                     .where(roles: { slug: "housekeeper" })
                                     .select(:user_id))
          .order(:name)
    end
  end
end
