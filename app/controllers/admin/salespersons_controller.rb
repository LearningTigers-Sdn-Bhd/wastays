class Admin::SalespersonsController < Admin::BaseController
  before_action :set_salesperson, only: [ :edit, :update, :destroy ]
  before_action :set_hotels, only: [ :index, :edit, :create, :update ]

  def index
    @query = search_query
    @salespersons = Admin::Salespersons::Filter.new(current_user.account.users, @query).call.order(:name)
    @new_salesperson = User.new(role: "salesperson")
    @selected_hotel_ids = []
  end

  def edit; end

  def create
    @query = search_query
    result = Admin::Salespersons::CreateService.new(
      account: current_user.account,
      params: salesperson_params,
      hotel_ids: selected_hotel_ids
    ).call

    if result.success?
      redirect_to admin_salespersons_path(query: @query.presence), notice: "Salesperson created successfully."
    else
      @new_salesperson = result.salesperson
      @salespersons = Admin::Salespersons::Filter.new(current_user.account.users, @query).call.order(:name)
      @selected_hotel_ids = selected_hotel_ids
      render :index, status: :unprocessable_content
    end
  end

  def update
    @query = search_query
    result = Admin::Salespersons::UpdateService.new(
      salesperson: @salesperson,
      params: salesperson_params,
      hotel_ids: selected_hotel_ids
    ).call

    if result.success?
      handle_update_success(result)
    else
      handle_update_failure
    end
  end

  def destroy
    @salesperson.destroy!
    respond_to do |format|
      format.html { redirect_to admin_salespersons_path(query: search_query.presence), notice: "Salesperson deleted successfully." }
      format.turbo_stream { render_turbo_remove("Salesperson deleted successfully.") }
    end
  end

  private

  def set_salesperson
    @salesperson = User.find(params[:id])
  end

  def set_hotels
    @hotels = Hotel.order(:name)
  end

  def handle_update_success(result)
    notice = "Salesperson updated successfully."

    respond_to do |format|
      format.html { redirect_to admin_salespersons_path(query: @query.presence), notice: notice }
      format.turbo_stream do
        if @query.present? && !Admin::Salespersons::Filter.matches?(@salesperson, @query)
          render_turbo_remove(notice)
        else
          render_turbo_update(notice)
        end
      end
    end
  end

  def handle_update_failure
    @salespersons = Admin::Salespersons::Filter.new(current_user.account.users, @query).call.order(:name)
    @salespersons = @salespersons.map { |r| r.id == @salesperson.id ? @salesperson : r }
    @editing_salesperson_id = @salesperson.id
    render :index, status: :unprocessable_content
  end

  def render_turbo_remove(notice)
    flash.now[:notice] = notice
    render turbo_stream: [
      turbo_stream.remove(helpers.dom_id(@salesperson, :row)),
      toast_stream(notice, type: :success)
    ]
  end

  def render_turbo_update(notice)
    flash.now[:notice] = notice
    @salespersons = Admin::Salespersons::Filter.new(current_user.account.users, @query).call.order(:name)
    render turbo_stream: [
      turbo_stream.replace(
        helpers.dom_id(@salesperson, :row),
        partial: "admin/salespersons/salesperson_row",
        locals: { salesperson: @salesperson, index: @salespersons.index(@salesperson) || 0, editing: false }
      ),
      toast_stream(notice, type: :success)
    ]
  end

  def salesperson_params
    params.fetch(:user, ActionController::Parameters.new).permit(:name, :email)
  end

  def selected_hotel_ids
    Array(params[:hotel_ids]).reject(&:blank?).map(&:to_i)
  end

  def search_query
    params[:query].to_s.strip
  end
end
