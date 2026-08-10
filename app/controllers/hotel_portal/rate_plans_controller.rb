# frozen_string_literal: true

class HotelPortal::RatePlansController < HotelPortal::BaseController
  include SheetActionCompletion
  include RatePlanEditorLoading

  before_action :authorize_rate_plan_editor!
  before_action :set_rate_plan, only: %i[edit update destroy archive unarchive]

  def new
    @rate_plan = current_hotel.rate_plans.build
    @rate_plan.currency = current_hotel.default_currency || "MYR"
    load_new_rate_plan_form(room_type_id: params[:room_type_id])
    render layout: false
  end

  def edit
    load_rate_plan_editor(room_type_id: params[:room_type_id])
    render layout: false
  end

  def create
    attrs = rate_plan_params
    room_type_id = attrs.delete(:room_type_id)
    selected_rate_plan_id = attrs.delete(:rate_plan_id)
    @selected_room_type = current_hotel.room_types.find_by(id: room_type_id)
    @room_pricing = HotelPortal::RatePlanRoomPricing.from_h(
      room_pricing_params,
      room_type: @selected_room_type,
      sells_per_person: current_hotel.sells_per_person?
    )

    result = nil
    pricing_result = nil
    with_batched_ari_sync do
      ActiveRecord::Base.transaction do
        unless @selected_room_type
          @rate_plan = current_hotel.rate_plans.build(attrs)
          @rate_plan.errors.add(:base, "Select a room category")
          raise ActiveRecord::Rollback
        end

        result = RatePlans::Resolve.call(
          hotel: current_hotel,
          rate_plan_id: selected_rate_plan_id,
          rate_plan_name: attrs[:name],
          create_attributes: attrs.except(:name).merge(currency: current_hotel.default_currency || "MYR")
        )
        unless result.success?
          @rate_plan = result.rate_plan || current_hotel.rate_plans.build(attrs)
          @rate_plan.errors.add(:base, result.error)
          raise ActiveRecord::Rollback
        end

        @rate_plan = result.rate_plan
        pricing_result = RatePlans::SaveRoomPricing.call(
          rate_plan: @rate_plan,
          room_type: @selected_room_type,
          pricing: @room_pricing
        )
        unless pricing_result.success?
          @rate_plan.errors.add(:base, pricing_result.error)
          raise ActiveRecord::Rollback
        end
      end
    end

    if result&.success? && pricing_result&.success?
      ChannelManagers::SyncRatePlanAri.call(rate_plan: @rate_plan, room_type_ids: [ @selected_room_type.id ])
      finish_sheet(notice: "Rate plan '#{@rate_plan.name}' created successfully.")
    else
      load_new_rate_plan_form(room_type_id: room_type_id, preserve_pricing: true)
      render :new, layout: false, status: :unprocessable_content
    end
  end

  def update
    attrs = rate_plan_params
    room_type_id = attrs.delete(:room_type_id)
    attrs.delete(:rate_plan_id)
    attrs = attrs.except(:name, :description) if @rate_plan.standard_rate?
    @selected_room_type = @rate_plan.room_types.find_by(id: room_type_id)
    @room_pricing = if @selected_room_type
      HotelPortal::RatePlanRoomPricing.from_h(
        room_pricing_params,
        room_type: @selected_room_type,
        sells_per_person: current_hotel.sells_per_person?
      )
    end

    saved = false
    with_batched_ari_sync do
      ActiveRecord::Base.transaction do
        unless @selected_room_type
          @rate_plan.errors.add(:base, "Select an attached room category")
          raise ActiveRecord::Rollback
        end

        unless @rate_plan.update(attrs)
          raise ActiveRecord::Rollback
        end

        unless @rate_plan.standard_rate? && !current_hotel.sells_per_person?
          pricing_result = RatePlans::SaveRoomPricing.call(
            rate_plan: @rate_plan,
            room_type: @selected_room_type,
            pricing: @room_pricing
          )
          unless pricing_result.success?
            @rate_plan.errors.add(:base, pricing_result.error)
            raise ActiveRecord::Rollback
          end
        end

        saved = true
      end
    end

    if saved
      # Plan-level fields (including flattened Channex child fees) apply to
      # every assignment, so one batched reconciliation covers them all.
      ChannelManagers::SyncRatePlanAri.call(rate_plan: @rate_plan, room_type_ids: @rate_plan.room_type_ids)
      render_editor_success("Rate plan saved.", room_type_id: @selected_room_type.id)
    else
      render_editor_errors(room_type_id: room_type_id)
    end
  end

  def destroy
    return finish_sheet(alert: "This rate plan cannot be deleted.") unless @rate_plan.deletable?

    if @rate_plan.destroy
      finish_sheet(notice: "Rate plan '#{@rate_plan.name}' deleted successfully.")
    else
      finish_sheet(alert: "Failed to delete rate plan.")
    end
  end

  def archive
    unless @rate_plan.archivable?
      return respond_to_status_change("'#{@rate_plan.name}' is the category's price anchor and cannot be archived.", success: false)
    end

    @rate_plan.archive!
    respond_to_status_change("Rate plan '#{@rate_plan.name}' archived. It will no longer be offered for new bookings.")
  rescue ActiveRecord::RecordInvalid => error
    respond_to_status_change(error.record.errors.full_messages.to_sentence.presence || "Rate plan could not be archived.", success: false)
  end

  def unarchive
    @rate_plan.unarchive!
    respond_to_status_change("Rate plan '#{@rate_plan.name}' restored.")
  rescue ActiveRecord::RecordInvalid => error
    respond_to_status_change(error.record.errors.full_messages.to_sentence.presence || "Rate plan could not be restored.", success: false)
  end

  private

  def respond_to_status_change(message, success: true)
    destination = hotel_room_types_path(current_hotel)
    assignment = @rate_plan.room_type_rate_plans
      .includes(:channel_mapping, :occupancy_prices, :rate_plan, :room_type)
      .find_by(room_type_id: params[:room_type_id])

    respond_to do |format|
      format.turbo_stream do
        streams = []
        if success && assignment
          streams << turbo_stream.replace(
            "room-inventory-rate-plan-#{assignment.id}",
            partial: "hotel_portal/room_types/inventory_rate_plan",
            locals: { assignment: assignment, room_type: assignment.room_type }
          )
        end
        streams << toast_stream(message, type: success ? :success : :error)
        render turbo_stream: streams, status: success ? :ok : :unprocessable_content
      end
      format.html do
        redirect_to destination,
                    notice: (message if success),
                    alert: (message unless success),
                    status: :see_other
      end
    end
  end

  # Closes the sheet and returns to Room Inventory. This mirrors
  # SheetActionCompletion#complete_sheet_action while also carrying alerts for
  # archive/delete guards.
  def finish_sheet(notice: nil, alert: nil)
    destination = hotel_room_types_path(current_hotel)

    respond_to do |format|
      format.turbo_stream do
        flash[:notice] = notice if notice
        flash[:alert] = alert if alert
        render_sheet_action_completion(destination, frame: sheet_frame)
      end
      format.html { redirect_to destination, notice: notice, alert: alert, status: :see_other }
    end
  end

  def sheet_frame
    turbo_frame_request_id.presence || EDITOR_FRAME
  end

  def set_rate_plan
    @rate_plan = current_hotel.rate_plans.find(params[:id])
  end

  # :sell_mode is deliberately absent — RatePlan inherits it from the hotel, so
  # a submitted value would only ever be ignored or fight the property setting.
  def rate_plan_params
    params.require(:rate_plan).permit(
      :name,
      :description,
      :room_type_id,
      :rate_plan_id,
      :base_occupancy,
      :extra_pax_charge,
      :single_supplement,
      :child_price_multiplier,
      :channex_children_fee,
      :channex_infant_fee,
      rate_plan_age_bands_attributes: [ :id, :min_age, :max_age, :pricing_mode, :price_value, :label, :position, :_destroy ]
    )
  end

  def room_pricing_params
    params.fetch(:room_pricing, {}).permit(
      :rate_mode,
      :default_rate,
      :derive_mode,
      :derive_value,
      :primary_occupancy,
      :increase_by,
      :increase_unit,
      :decrease_by,
      :decrease_unit,
      prices: {}
    )
  end

  def load_new_rate_plan_form(room_type_id:, preserve_pricing: false)
    @room_types = current_hotel.room_types
      .includes(:rate_plans, room_type_rate_plans: :occupancy_prices)
      .order(:name, :id)
      .to_a
    @selected_room_type ||= @room_types.find { |room_type| room_type.id == room_type_id.to_i } || @room_types.first
    return unless @selected_room_type
    return if preserve_pricing && @room_pricing

    standard_plan = @selected_room_type.standard_rate_plan
    standard_assignment = @selected_room_type.room_type_rate_plans.find do |assignment|
      assignment.rate_plan_id == standard_plan&.id
    end
    @room_pricing = HotelPortal::RatePlanRoomPricing.from_assignment(
      standard_assignment,
      room_type: @selected_room_type,
      sells_per_person: current_hotel.sells_per_person?
    )
    if !current_hotel.sells_per_person? && @room_pricing.default_rate.blank?
      @room_pricing.default_rate = @selected_room_type.base_price
    end
  end
end
