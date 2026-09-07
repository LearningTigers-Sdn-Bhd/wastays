# frozen_string_literal: true

module HotelPortal
  class NearbyAttractionsController < HotelPortal::SettingsBaseController
    helper_method :attraction_issue_label, :attraction_issue_variant

    before_action :set_hotel
    before_action :authorize_hotel
    before_action :set_hotel_nearby_attraction, only: %i[edit update destroy]

    def index
      set_nearby_attractions
    end

    def new
      @attraction = Attraction.new
      render :new, layout: false
    end

    def preview
      @attraction = Attraction.new(google_maps_url: attraction_params[:google_maps_url])
      result = Attractions::GoogleMapsUrlParser.call(@attraction.google_maps_url)

      if result.success?
        @parsed_attraction = result.parsed
        @duplicate_attraction = Attractions::FindDuplicate.call(fingerprint: result.parsed.fingerprint)
        @estimated_distance_km = preview_distance(result.parsed)
        render :preview, layout: false
      else
        @attraction.errors.add(:google_maps_url, result.error)
        render :new, layout: false, status: :unprocessable_content
      end
    end

    def create
      result = Attractions::FindOrCreateAndLink.call(
        hotel: @hotel,
        google_maps_url: attraction_params[:google_maps_url],
        submitted_by: current_user
      )

      if result.success?
        message = "Attraction added to your hotel."
        respond_to do |format|
          format.turbo_stream { render_saved_stream(message) }
          format.html { redirect_to hotel_nearby_attractions_path(@hotel), notice: message }
        end
      else
        @attraction = result.attraction || Attraction.new(google_maps_url: attraction_params[:google_maps_url])
        @attraction.errors.add(:google_maps_url, result.error)
        render :new, layout: false, status: :unprocessable_content
      end
    end

    def edit
      render :edit, layout: false
    end

    def update
      if @hotel_nearby_attraction.update(hotel_nearby_attraction_params)
        respond_to do |format|
          format.turbo_stream { render_saved_stream("Guest description updated.") }
          format.html { redirect_to hotel_nearby_attractions_path(@hotel), notice: "Guest description updated." }
        end
      else
        render :edit, layout: false, status: :unprocessable_content
      end
    end

    def destroy
      @hotel_nearby_attraction.destroy!

      respond_to do |format|
        format.turbo_stream { render_saved_stream("Attraction removed from your hotel.") }
        format.html do
          redirect_to hotel_nearby_attractions_path(@hotel), notice: "Attraction removed from your hotel."
        end
      end
    end

    private

    def set_nearby_attractions
      @all_nearby_attractions = @hotel.hotel_nearby_attractions.includes(:attraction).order(created_at: :desc)
      @pagy, @nearby_attractions = pagy(:offset, @all_nearby_attractions, limit: 25)
      @suggestions = Attractions::Suggestions.call(hotel: @hotel, limit: 10, radius_km: 25)
      @hotel_coordinates_available = @hotel.latitude.present? && @hotel.longitude.present?
    end

    def render_saved_stream(message)
      set_nearby_attractions
      render turbo_stream: [
        turbo_stream.replace(
          "nearby_attractions_suggestions",
          partial: "hotel_portal/nearby_attractions/suggestions"
        ),
        turbo_stream.replace(
          "nearby_attractions_list",
          partial: "hotel_portal/nearby_attractions/list"
        ),
        turbo_stream.update("nearby_attraction_form", ""),
        toast_stream(message, type: :success)
      ]
    end

    def set_hotel
      @hotel = current_hotel
    end

    def authorize_hotel
      authorize @hotel, :update?, policy_class: HotelPolicy
    end

    def set_hotel_nearby_attraction
      @hotel_nearby_attraction = @hotel.hotel_nearby_attractions.includes(:attraction).find(params[:id])
    end

    def attraction_params
      params.require(:attraction).permit(:google_maps_url)
    end

    def hotel_nearby_attraction_params
      params.require(:hotel_nearby_attraction).permit(:description)
    end

    def attraction_issue_label(attraction)
      case attraction.status
      when "rejected" then "Needs attention"
      when "archived" then "Unavailable"
      end
    end

    def attraction_issue_variant(attraction)
      attraction.status_rejected? ? :destructive : :neutral
    end

    def preview_distance(parsed_attraction)
      return if @hotel.latitude.blank? || @hotel.longitude.blank?

      Attractions::Distance.kilometers(
        @hotel.latitude,
        @hotel.longitude,
        parsed_attraction.latitude,
        parsed_attraction.longitude
      )
    end
  end
end
