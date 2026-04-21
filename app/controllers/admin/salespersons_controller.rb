class Admin::SalespersonsController < Admin::BaseController
  before_action :set_salesperson, only: [ :edit, :update, :destroy ]
  before_action :set_hotels, only: [ :index, :edit, :create, :update ]

  def index
    @query = params[:query].to_s.strip
    @salespersons = filtered_salespersons(@query).order(:name)
    @hotels = Hotel.order(:name)
    @new_salesperson = User.new(role: "salesperson")
    @selected_hotel_ids = []
  end

  def edit
    @hotels = Hotel.order(:name)
  end

  def create
    @query = params[:query].to_s.strip
    @salespersons = filtered_salespersons(@query).order(:name)
    @hotels = Hotel.order(:name)
    @selected_hotel_ids = selected_hotel_ids
    @new_salesperson = User.new(salesperson_params)
    @new_salesperson.role = "salesperson"
    @new_salesperson.account = current_user.account
    @new_salesperson.email = salesperson_params[:email].presence || generated_salesperson_email
    @new_salesperson.password ||= generated_salesperson_password
    @new_salesperson.password_confirmation ||= @new_salesperson.password

    if @new_salesperson.save
      assign_hotels(@new_salesperson, @selected_hotel_ids)
      redirect_to admin_salespersons_path(query: @query.presence), notice: "Salesperson created successfully."
    else
      render :index, status: :unprocessable_content
    end
  end

  def update
    @query = params[:query].to_s.strip
    hotel_ids = selected_hotel_ids

    if @salesperson.update(salesperson_params)
      if hotel_ids.empty?
        Hotel.where(salesperson_id: @salesperson.id).update_all(salesperson_id: nil)
        @salesperson.destroy
        respond_to do |format|
          format.html { redirect_to admin_salespersons_path(query: @query.presence), notice: "Salesperson removed because no hotels are assigned." }
          format.turbo_stream do
            flash.now[:notice] = "Salesperson removed because no hotels are assigned."
            render turbo_stream: [
              turbo_stream.remove(helpers.dom_id(@salesperson, :row)),
              turbo_stream.prepend("flash_toasts", partial: "shared/toast", locals: { key: "notice", value: flash[:notice] })
            ]
          end
        end
      else
        assign_hotels(@salesperson, hotel_ids)
        respond_to do |format|
          format.html { redirect_to admin_salespersons_path(query: @query.presence), notice: "Salesperson updated successfully." }
          format.turbo_stream do
            flash.now[:notice] = "Salesperson updated successfully."
            @salespersons = filtered_salespersons(@query).order(:name)
            @hotels = Hotel.order(:name)
            streams = [
              turbo_stream.prepend("flash_toasts", partial: "shared/toast", locals: { key: "notice", value: flash[:notice] })
            ]

            if @query.present? && !salesperson_matches_query?(@salesperson, @query)
              streams << turbo_stream.remove(helpers.dom_id(@salesperson, :row))
            else
              streams << turbo_stream.replace(
                helpers.dom_id(@salesperson, :row),
                partial: "admin/salespersons/salesperson_row",
                locals: {
                  salesperson: @salesperson,
                  index: @salespersons.index(@salesperson) || 0,
                  editing: false
                }
              )
            end
            render turbo_stream: streams
          end
        end
      end
    else
      @salespersons = filtered_salespersons(@query).order(:name)
      @salespersons = @salespersons.map { |record| record.id == @salesperson.id ? @salesperson : record }
      @editing_salesperson_id = @salesperson.id
      @hotels = Hotel.order(:name)
      render :index, status: :unprocessable_content
    end
  end

  def destroy
    @salesperson.destroy!
    respond_to do |format|
      format.html { redirect_to admin_salespersons_path(query: params[:query].presence), notice: "Salesperson deleted successfully." }
      format.turbo_stream do
        flash.now[:notice] = "Salesperson deleted successfully."
        render turbo_stream: [
          turbo_stream.remove(helpers.dom_id(@salesperson, :row)),
          turbo_stream.prepend("flash_toasts", partial: "shared/toast", locals: { key: "notice", value: flash[:notice] })
        ]
      end
    end
  end

  private

  def set_salesperson
    @salesperson = User.find(params[:id])
  end

  def salesperson_params
    params.fetch(:user, ActionController::Parameters.new).permit(:name, :email)
  end

  def selected_hotel_ids
    Array(params[:hotel_ids]).reject(&:blank?).map(&:to_i)
  end

  def assign_hotels(salesperson, hotel_ids)
    Hotel.where(salesperson_id: salesperson.id).update_all(salesperson_id: nil)
    Hotel.where(id: hotel_ids).update_all(salesperson_id: salesperson.id)
  end

  def generated_salesperson_email
    "salesperson-#{SecureRandom.hex(6)}@wastays.local"
  end

  def generated_salesperson_password
    SecureRandom.hex(16)
  end

  def filtered_salespersons(query)
    scope = current_user.account.users.where(role: "salesperson").includes(:assigned_hotels)

    return scope if query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    scope.left_outer_joins(:assigned_hotels)
      .where(
        "LOWER(users.name) LIKE :query OR LOWER(users.email) LIKE :query OR LOWER(hotels.name) LIKE :query",
        query: pattern
      )
      .distinct
  end

  def salesperson_matches_query?(salesperson, query)
    return true if query.blank?

    haystack = [
      salesperson.name,
      salesperson.email,
      salesperson.assigned_hotels.map(&:name).join(" ")
    ].join(" ").downcase

    haystack.include?(query.downcase)
  end
end
