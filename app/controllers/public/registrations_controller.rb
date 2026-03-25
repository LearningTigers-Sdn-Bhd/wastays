class Public::RegistrationsController < ApplicationController
  def new
    @user = User.new
    @account = Account.new
    @hotel = Hotel.new
  end

  def create
    service = HotelOps::CreateHotel.new(
      account_params: account_params,
      user_params: user_params,
      hotel_params: hotel_params
    )

    result = service.call

    if result[:success]
      session[:user_id] = result[:user].id
      redirect_to hotel_dashboard_path, notice: "Welcome! Your hotel account has been created."
    else
      flash.now[:alert] = result[:error]
      @user = User.new(user_params)
      @account = Account.new(account_params)
      @hotel = Hotel.new(hotel_params)
      render :new, status: :unprocessable_entity
    end
  end

  private

  def account_params
    params.require(:account).permit(:name)
  end

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end

  def hotel_params
    params.require(:hotel).permit(:name, :city, :country)
  end
end
