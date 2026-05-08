# frozen_string_literal: true

module HotelPortal
  class HotelPoliciesController < HotelPortal::BaseController
    before_action :set_hotel

    def edit
      authorize @hotel
    end

    def update
      authorize @hotel

      if @hotel.update(policy: normalized_policy)
        respond_to do |format|
          format.html { redirect_to edit_hotel_policy_path(@hotel), notice: "Hotel policy updated successfully." }
          format.json { render json: { ok: true } }
        end
      else
        respond_to do |format|
          format.html { render :edit, status: :unprocessable_content }
          format.json { render json: { ok: false, error: @hotel.errors.full_messages.to_sentence.presence || "Could not save policy." }, status: :unprocessable_content }
        end
      end
    end

    private

    def set_hotel
      @hotel = current_hotel
    end

    def normalized_policy
      value = params.fetch(:hotel, {}).permit(:policy)[:policy]
      items = value.present? ? JSON.parse(value) : []

      Array(items).filter_map do |item|
        next unless item.is_a?(Hash)

        title = item["title"].to_s.strip
        content = item["content"].to_s.strip
        next if title.blank? && content.blank?

        {
          "title" => title,
          "content" => content
        }
      end
    rescue JSON::ParserError
      []
    end
  end
end
