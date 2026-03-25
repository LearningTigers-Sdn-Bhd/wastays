class Public::SessionsController < ApplicationController
  def new
  end

  def create
    user = User.find_by(email: params[:email].downcase)
    if user&.authenticate(params[:password])
      session[:user_id] = user.id
      redirect_to_dashboard(user)
    else
      flash.now[:alert] = "Invalid email or password"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session[:user_id] = nil
    redirect_to root_path, notice: "Logged out successfully"
  end

  private

  def redirect_to_dashboard(user)
    if user.superadmin?
      redirect_to admin_dashboard_path, notice: "Welcome, Superadmin!"
    else
      redirect_to hotel_dashboard_path, notice: "Welcome, #{user.name}!"
    end
  end
end
