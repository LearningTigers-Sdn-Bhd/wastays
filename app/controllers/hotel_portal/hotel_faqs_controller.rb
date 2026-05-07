# frozen_string_literal: true

module HotelPortal
  class HotelFaqsController < HotelPortal::BaseController
    before_action :set_hotel

    def edit
      authorize @hotel
    end

    def update
      authorize @hotel

      if @hotel.update(faq: parsed_faq)
        respond_to do |format|
          format.html { redirect_to edit_hotel_faq_path(@hotel), notice: "Hotel FAQ updated successfully." }
          format.json { render json: { ok: true } }
        end
      else
        respond_to do |format|
          format.html { render :edit, status: :unprocessable_content }
          format.json { render json: { ok: false, error: @hotel.errors.full_messages.to_sentence.presence || "Could not save FAQ." }, status: :unprocessable_content }
        end
      end
    end

    private

    def set_hotel
      @hotel = current_hotel
    end

    def parsed_faq
      value = params.fetch(:hotel, {}).permit(:faq)[:faq]
      return [] if value.blank?
      return value if value.is_a?(Array)

      JSON.parse(value)
    rescue JSON::ParserError
      []
    end
  end
end
