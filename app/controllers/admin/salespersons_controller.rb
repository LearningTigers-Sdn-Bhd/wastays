class Admin::SalespersonsController < Admin::BaseController
  before_action :set_salesperson, only: [ :update, :destroy ]

  def index
    @salespersons = User.where(role: "salesperson").order(:name)
    @hotels = Hotel.order(:name)
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
    hotel_ids = selected_hotel_ids

    if @salesperson.update(salesperson_params)
      if hotel_ids.empty?
        Hotel.where(salesperson_id: @salesperson.id).update_all(salesperson_id: nil)
        @salesperson.destroy
        redirect_to admin_salespersons_path, notice: "Salesperson removed because no hotels are assigned."
      else
        assign_hotels(@salesperson, hotel_ids)
        redirect_to admin_salespersons_path, notice: "Salesperson updated successfully."
      end
    else
      index
      @salespersons = @salespersons.map { |record| record.id == @salesperson.id ? @salesperson : record }
      render :index, status: :unprocessable_content
    end
  end

  def destroy
    Hotel.where(salesperson_id: @salesperson.id).update_all(salesperson_id: nil)
    @salesperson.update(role: "hotel_staff")
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
