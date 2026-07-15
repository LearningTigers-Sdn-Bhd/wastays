# frozen_string_literal: true

module HotelPortal
  class NearbyAttractionsController < HotelPortal::SettingsBaseController
    before_action :set_hotel
    before_action :authorize_hotel
    before_action :set_nearby_attraction, only: %i[edit update destroy]

    def index
      set_nearby_attractions
    end

    def new
      @nearby_attraction = @hotel.nearby_attractions.build
      render :new, layout: false
    end

    def create
      @nearby_attraction = @hotel.nearby_attractions.build(nearby_attraction_params)

      if @nearby_attraction.save
        respond_to do |format|
          format.turbo_stream { render_saved_stream("Nearby attraction created successfully.") }
          format.html { redirect_to hotel_nearby_attractions_path(@hotel), notice: "Nearby attraction created successfully." }
        end
      else
        render :new, layout: false, status: :unprocessable_content
      end
    end

    def edit
      render :edit, layout: false
    end

    def update
      if @nearby_attraction.update(nearby_attraction_params)
        respond_to do |format|
          format.turbo_stream { render_saved_stream("Nearby attraction updated successfully.") }
          format.html { redirect_to hotel_nearby_attractions_path(@hotel), notice: "Nearby attraction updated successfully." }
        end
      else
        render :edit, layout: false, status: :unprocessable_content
      end
    end

    def destroy
      @nearby_attraction.destroy
      redirect_to hotel_nearby_attractions_path(@hotel), notice: "Nearby attraction deleted successfully."
    end

    private

    def set_nearby_attractions
      @all_nearby_attractions = @hotel.nearby_attractions.order(created_at: :desc)
      @nearby_attractions = @all_nearby_attractions.page(params[:page]).per(25)
    end

    def render_saved_stream(message)
      set_nearby_attractions
      render turbo_stream: [
        turbo_stream.replace("nearby_attractions_list", partial: "hotel_portal/nearby_attractions/list"),
        turbo_stream.update("nearby_attraction_form", ""),
        turbo_stream.append("toast-viewport",
                            partial: "shared/feedback/toast_trigger",
                            locals: { message: message, type: "success", description: nil })
      ]
    end

    def set_hotel
      @hotel = current_hotel
    end

    def authorize_hotel
      authorize @hotel, :update?, policy_class: HotelPolicy
    end

    def set_nearby_attraction
      @nearby_attraction = @hotel.nearby_attractions.find(params[:id])
    end

    def nearby_attraction_params
      params.require(:nearby_attraction).permit(:name, :description, :address, :city, :country)
    end
  end
end
