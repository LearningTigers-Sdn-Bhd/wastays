# frozen_string_literal: true

class HotelPortal::RatePlanAttachmentsController < HotelPortal::SettingsBaseController
  include SheetActionCompletion

  before_action :set_hotel
  before_action :authorize_hotel

  def new
    load_form_state(selected_room_type_ids: [ params[:room_type_id] ])
    render layout: false
  end

  def create
    attributes = attachment_params
    result = RatePlans::Attach.call(
      hotel: @hotel,
      user: current_user,
      rate_plan_id: attributes[:rate_plan_id],
      rate_plan_name: attributes[:rate_plan_name],
      room_type_ids: attributes[:room_type_ids]
    )

    if result.success?
      finish_sheet(attachment_notice(result))
    else
      @attachment_error = result.error
      load_form_state(
        rate_plan_id: attributes[:rate_plan_id],
        rate_plan_name: attributes[:rate_plan_name],
        selected_room_type_ids: attributes[:room_type_ids]
      )
      render :new, layout: false, status: :unprocessable_content
    end
  end

  def autocomplete
    results = RatePlans::Autocomplete.call(hotel: @hotel, query: params[:q], limit: 20)
    render json: { results: results }
  end

  private

  def set_hotel
    @hotel = current_hotel
  end

  def authorize_hotel
    authorize @hotel, :update?, policy_class: HotelPolicy
  end

  def attachment_params
    params.require(:rate_plan_attachment).permit(:rate_plan_id, :rate_plan_name, room_type_ids: [])
  end

  def load_form_state(rate_plan_id: nil, rate_plan_name: nil, selected_room_type_ids: [])
    @room_types = @hotel.room_types.order(:name, :id)
    @selected_room_type_ids = Array(selected_room_type_ids).compact_blank.map(&:to_s)
    @attachment = HotelPortal::RatePlanAttachmentForm.new(
      rate_plan_id: rate_plan_id,
      rate_plan_name: rate_plan_name,
      room_type_ids: @selected_room_type_ids
    )
  end

  def attachment_notice(result)
    return "#{result.rate_plan.name} is already assigned to the selected room categories." if result.attached_count.zero?

    "#{result.rate_plan.name} assigned to #{helpers.pluralize(result.attached_count, 'room category')}."
  end

  def finish_sheet(notice)
    complete_sheet_action(
      destination: hotel_room_types_path(@hotel),
      notice: notice,
      frame: turbo_frame_request_id.presence || "settings_action_sheet"
    )
  end
end
