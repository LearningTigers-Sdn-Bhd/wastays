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

    DEFAULT_CANCELLATION_TEXT = "Cancellation policies are subject to the room type selected. Please review your quote before payment."

    def cancellation_summary
      @cancellation_summary ||= Cancellations::PolicySummary.for_hotel(@hotel)
    end

    def cancellation_policy
      cancellation_summary.to_text.presence || DEFAULT_CANCELLATION_TEXT
    end

    def starting_price(availability_service, room_types)
      return nil unless availability_service && room_types.any?
      availability_service.calculate_total_price(room_types.first)
    end

    def summary_photo
      room_types.first&.photos&.attached? ? room_types.first.photos.first : nil
    end

    def first_room_type_photo
      summary_photo
    end

    def first_room_type_photo_attached?
      summary_photo.present?
    end

    def primary_photo
      gallery_photos.first || first_room_type_photo
    end

    def secondary_photos_with_fallbacks
      (1..4).map do |i|
        if gallery_photos[i].present?
          { photo: gallery_photos[i], is_attachment: true }
        else
          { photo: fallback_images[i - 1], is_attachment: false }
        end
      end
    end

    def has_photos?
      photos.attached? && gallery_count.positive?
    end

    def google_maps_search_url
      if google_map_link.present?
        google_map_link
      else
        "https://www.google.com/maps/search/?api=1&query=#{ERB::Util.url_encode("#{name}, #{full_address}")}"
      end
    end

    def google_maps_embed_url
      query = if google_map_link.present?
                if google_map_link =~ %r{/maps/place/([^/@?]+)}
                  CGI.unescape($1).gsub("+", " ")
                elsif google_map_link =~ /@(-?\d+\.\d+),(-?\d+\.\d+)/
                  "#{$1},#{$2}"
                elsif google_map_link =~ /[?&]query=([^&]+)/
                  CGI.unescape($1).gsub("+", " ")
                elsif google_map_link =~ /[?&]q=([^&]+)/
                  CGI.unescape($1).gsub("+", " ")
                else
                  google_map_link.include?("maps.app.goo.gl") || google_map_link.include?("goo.gl/maps") ? "#{name}, #{full_address}" : google_map_link
                end
      else
                "#{name}, #{full_address}"
      end

      "https://maps.google.com/maps?q=#{ERB::Util.url_encode(query)}&t=&z=15&ie=UTF8&iwloc=&output=embed"
    end

    def currency_dropdown_options
      CurrencyCatalog::COMMON_CODES.map { |code| [ code, code ] }
    end
  end
end
