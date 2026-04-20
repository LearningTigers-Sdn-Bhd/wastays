class Admin::SalespersonsController < Admin::BaseController
  before_action :set_salesperson, only: [ :edit, :update, :destroy ]
  before_action :set_hotels, only: [ :index, :edit, :create, :update ]

  def index
    @query = search_query
    @salespersons = Admin::Salespersons::Filter.new(current_user.account.users, @query).call.order(:name)
    @new_salesperson = User.new(role: "salesperson")
    @selected_hotel_ids = []
  end

  def create
    @salespersons = User.where(role: "salesperson").order(:name)
    @hotels = Hotel.order(:name)
    @selected_hotel_ids = selected_hotel_ids
    @new_salesperson = User.new(salesperson_params)
    @new_salesperson.role = "salesperson"
    @new_salesperson.account = current_user.account
    @new_salesperson.email ||= generated_salesperson_email
    @new_salesperson.password ||= generated_salesperson_password
    @new_salesperson.password_confirmation ||= @new_salesperson.password

    if @new_salesperson.save
      assign_hotels(@new_salesperson, @selected_hotel_ids)
      redirect_to admin_salespersons_path, notice: "Salesperson created successfully."
    else
      render :index, status: :unprocessable_content
    end
  end

  def update
    if @salesperson.update(salesperson_params)
      assign_hotels(@salesperson, selected_hotel_ids)
      redirect_to admin_salespersons_path, notice: "Salesperson updated successfully."
    else
      index
      @salespersons = @salespersons.map { |record| record.id == @salesperson.id ? @salesperson : record }
      render :index, status: :unprocessable_content
    end
  end

  def destroy
    @salesperson.update(role: "hotel_staff")
    Hotel.where(salesperson_id: @salesperson.id).update_all(salesperson_id: nil)
    redirect_to admin_salespersons_path, notice: "Salesperson removed successfully."
  end

  private

  def set_salesperson
    @salesperson = User.find(params[:id])
  end

  def salesperson_params
    params.require(:user).permit(:name)
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
end
