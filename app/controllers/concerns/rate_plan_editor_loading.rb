# frozen_string_literal: true

# Everything the tabbed rate plan editor needs to render itself, and the two
# ways it answers a write: the turbo_stream that keeps the sheet open, or the
# HTML redirect back into the same tab. Shared by RatePlansController and
# RatePlanRoomPricingsController so the two cannot drift on either.
module RatePlanEditorLoading
  extend ActiveSupport::Concern

  EDITOR_FRAME = "settings_action_sheet"

  private

  def load_rate_plan_editor(tab: nil, room_type_id: nil)
    @all_room_types = current_hotel.room_types.order(:name, :id).to_a
    @assignments = @rate_plan.room_type_rate_plans
      .includes(:occupancy_prices, :room_type, :rate_plan)
      .to_a
      .sort_by { |assignment| [ assignment.room_type.name.downcase, assignment.room_type_id ] }
    @assigned_room_types = @assignments.map(&:room_type)
    @available_room_types = @all_room_types.reject { |room_type| @assigned_room_types.include?(room_type) }
    @booking_referenced_room_type_ids = @rate_plan.booking_rooms
      .where(room_type_id: @assigned_room_types.map(&:id))
      .distinct
      .pluck(:room_type_id)

    requested_room = @all_room_types.find { |room_type| room_type.id == room_type_id.to_i }
    requested_room = nil if @rate_plan.standard_rate? && !@assigned_room_types.include?(requested_room)
    @selected_room_type = requested_room || @assigned_room_types.first
    @selected_assignment = @assignments.find { |assignment| assignment.room_type_id == @selected_room_type&.id }
    @room_pricing ||= if @selected_room_type
      HotelPortal::RatePlanWizard::RoomPricing.from_assignment(
        @selected_assignment,
        room_type: @selected_room_type,
        sells_per_person: current_hotel.sells_per_person?
      )
    end

    offered_tabs = %w[details rooms]
    offered_tabs << "children" if current_hotel.sells_per_person?
    @active_tab = offered_tabs.include?(tab.to_s) ? tab.to_s : "details"
  end

  # True only for requests Turbo aimed at the editor's own frame. The settings
  # registry drives the same archive/unarchive routes with turbo_frame "_top",
  # and both carry a turbo_stream Accept header — the frame is what separates
  # "stay in the sheet" from "navigate the page".
  def rate_plan_editor_request?
    turbo_frame_request_id == EDITOR_FRAME
  end

  def render_editor_success(message, tab:, room_type_id: params[:room_type_id])
    load_rate_plan_editor(tab: tab, room_type_id: room_type_id)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(EDITOR_FRAME, partial: "hotel_portal/rate_plans/editor_sheet", locals: {
            rate_plan: @rate_plan,
            active_tab: @active_tab,
            selected_room_type: @selected_room_type,
            room_pricing: @room_pricing
          }),
          turbo_stream.replace("rate-plan-row-#{@rate_plan.id}", partial: "hotel_portal/settings/rate_plan_row", locals: {
            rate_plan: @rate_plan,
            hotel: current_hotel,
            qualify_names: @rate_plan.standard_rate?
          }),
          toast_stream(message, type: :success)
        ]
      end
      format.html do
        redirect_to edit_hotel_rate_plan_path(current_hotel, @rate_plan, tab: @active_tab, room_type_id: room_type_id),
                    notice: message, status: :see_other
      end
    end
  end

  def render_editor_errors(tab:, room_type_id: params[:room_type_id])
    load_rate_plan_editor(tab: tab, room_type_id: room_type_id)
    render "hotel_portal/rate_plans/edit", formats: :html, layout: false, status: :unprocessable_content
  end

  # RoomTypeRatePlan#trigger_ari_sync fires per row, which would enqueue a
  # separate 500-day rate push for every room category touched. The callers
  # send one push afterwards instead.
  #
  # This has to wrap the whole transaction, not just the writes: the callback
  # is after_commit, so a flag reset inside the transaction block would already
  # be cleared by the time it runs.
  def with_batched_ari_sync
    Thread.current[:skip_ari_sync] = true
    yield
  ensure
    Thread.current[:skip_ari_sync] = nil
  end

  def authorize_rate_plan_editor!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
  end
end
