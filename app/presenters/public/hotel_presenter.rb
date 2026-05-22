# frozen_string_literal: true

module Public
  class HotelPresenter < SimpleDelegator
    def initialize(hotel, view_context)
      @hotel = hotel
      @view_context = view_context
      super(hotel)
    end

    def gallery_photos
      @gallery_photos ||= ordered_photo_attachments.first(5)
    end

    def photo_urls_json
      ordered_photo_attachments.map { |p| @view_context.url_for(p) }.to_json
    end

    def gallery_count
      photos.attached? ? photos.count : 0
    end

    def extra_photos_count
      [ gallery_count - gallery_photos.size, 0 ].max
    end

    def fallback_images
      [
        "https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&q=80&w=600",
        "https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&q=80&w=600",
        "https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?auto=format&fit=crop&q=80&w=600",
        "https://images.unsplash.com/photo-1549443105-2070367f4077?auto=format&fit=crop&q=80&w=600"
      ]
    end

    def full_address
      "#{address}, #{city}, #{country}"
    end

    def star_rating_int
      star_rating.to_i
    end

    def check_in_time
      property_policy&.check_in_time || "2:00 PM"
    end

    def check_out_time
      property_policy&.check_out_time || "12:00 PM"
    end

    def cancellation_policy
      property_policy&.cancellation_policy.presence || "Cancellation policies are subject to the room type selected. Please review your quote before payment."
    end

    def starting_price(availability_service, room_types)
      return nil unless availability_service && room_types.any?
      availability_service.calculate_total_price(room_types.first)
    end
  end
end
