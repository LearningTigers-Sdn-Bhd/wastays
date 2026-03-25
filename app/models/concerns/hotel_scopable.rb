module HotelScopable
  extend ActiveSupport::Concern

  included do
    belongs_to :hotel
    validates :hotel_id, presence: true

    scope :for_hotel, ->(hotel) { where(hotel: hotel) }
  end
end
