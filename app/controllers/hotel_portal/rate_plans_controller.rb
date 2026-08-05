# frozen_string_literal: true

class HotelPortal::RatePlansController < HotelPortal::BaseController
  include SheetActionCompletion

  before_action :authorize!
  before_action :set_rate_plan, only: %i[edit update destroy archive unarchive]

  def new
    @rate_plan = current_hotel.rate_plans.build(sell_mode: default_sell_mode)
    render layout: false
  end

  def edit
    render layout: false
  end

  def create
    attrs = rate_plan_params
    room_type_pricing = attrs.delete(:room_type_pricing) || {}

    @rate_plan = current_hotel.rate_plans.build(attrs)
    @rate_plan.currency = current_hotel.default_currency || "MYR"

    saved = false
    with_batched_ari_sync do
      ActiveRecord::Base.transaction do
        saved = @rate_plan.save
        saved = sync_room_type_pricing!(@rate_plan, room_type_pricing) if saved
        raise ActiveRecord::Rollback unless saved
      end
    end

    if saved
      push_ari(@rate_plan, room_type_pricing)
      finish_sheet(notice: "Rate plan '#{@rate_plan.name}' created successfully.")
    else
      render :new, layout: false, status: :unprocessable_content
    end
  end

  def update
    attrs = rate_plan_params
    room_type_pricing = attrs.delete(:room_type_pricing) || {}

    saved = false
    with_batched_ari_sync do
      ActiveRecord::Base.transaction do
        saved = @rate_plan.update(attrs)
        saved = sync_room_type_pricing!(@rate_plan, room_type_pricing) if saved
        raise ActiveRecord::Rollback unless saved
      end
    end

    if saved
      push_ari(@rate_plan, room_type_pricing)
      finish_sheet(notice: "Rate plan '#{@rate_plan.name}' updated successfully.")
    else
      render :edit, layout: false, status: :unprocessable_content
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
    return finish_sheet(alert: "System rate plans cannot be archived.") unless @rate_plan.archivable?

    @rate_plan.archive!
    finish_sheet(notice: "Rate plan '#{@rate_plan.name}' archived. It will no longer be offered for new bookings.")
  end

  def unarchive
    @rate_plan.unarchive!
    finish_sheet(notice: "Rate plan '#{@rate_plan.name}' restored.")
  end

  private

  # Closes the sheet (when the request came from one) and lands back on the
  # rates settings page. Mirrors SheetActionCompletion#complete_sheet_action,
  # which only carries a notice — archive/delete guards need an alert too.
  def finish_sheet(notice: nil, alert: nil)
    destination = hotel_rates_settings_path(current_hotel)

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
    turbo_frame_request_id.presence || "settings_action_sheet"
  end

  def set_rate_plan
    @rate_plan = current_hotel.rate_plans.find(params[:id])
  end

  def default_sell_mode
    current_hotel.pax_pricing_only? ? "per_person" : "per_room"
  end

  def rate_plan_params
    params.require(:rate_plan).permit(
      :name,
      :sell_mode,
      :base_occupancy,
      :extra_pax_charge,
      :single_supplement,
      :child_price_multiplier,
      rate_plan_age_bands_attributes: [ :id, :min_age, :max_age, :pricing_mode, :price_value, :label, :position, :_destroy ],
      room_type_pricing: {}
    )
  end

  # Syncs which room types this rate plan applies to, and each room type's
  # pricing_mode/pricing_value, from the per-room-type rows submitted by the
  # form. Returns false (adding an error onto rate_plan) if any row fails to
  # save, so the caller can roll back the whole create/update.
  #
  # A standard plan is created with its room category and stays bound to it:
  # reassigning one would attach a second category to another category's anchor
  # plan and leave the first without an anchor of its own. The form renders that
  # section read-only, and this drops the parameters regardless of what was
  # submitted.
  def sync_room_type_pricing!(rate_plan, room_type_pricing)
    return true if rate_plan.standard_rate?

    sync_room_type_pricing_rows!(rate_plan, room_type_pricing)
  end

  # RoomTypeRatePlan#trigger_ari_sync fires per row, which would enqueue a
  # separate 500-day rate push for every room category on the plan. push_ari
  # sends one instead.
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

  def push_ari(rate_plan, room_type_pricing)
    return if rate_plan.standard_rate?

    # room_type_pricing is ActionController::Parameters, which has each_pair but
    # not the full Enumerable surface.
    enabled_ids = []
    room_type_pricing.each_pair do |room_type_id, attrs|
      enabled_ids << room_type_id.to_i if ActiveModel::Type::Boolean.new.cast(attrs[:enabled])
    end

    ChannelManagers::SyncRatePlanAri.call(rate_plan: rate_plan, room_type_ids: enabled_ids)
  end

  def sync_room_type_pricing_rows!(rate_plan, room_type_pricing)
    room_type_pricing.each do |room_type_id, attrs|
      room_type = current_hotel.room_types.find_by(id: room_type_id)
      next unless room_type

      rtrp = rate_plan.room_type_rate_plans.find_or_initialize_by(room_type_id: room_type.id)
      enabled = ActiveModel::Type::Boolean.new.cast(attrs[:enabled])

      if enabled
        rtrp.pricing_mode = attrs[:pricing_mode].presence || "fixed"
        rtrp.pricing_value = attrs[:pricing_value].presence

        unless rtrp.save
          rate_plan.errors.add(:base, "#{room_type.name}: #{rtrp.errors.full_messages.to_sentence}")
          return false
        end
      elsif rtrp.persisted?
        rtrp.destroy
      end
    end

    true
  end

  def authorize!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
  end
end
