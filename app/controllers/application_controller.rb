class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  helper_method :current_user, :logged_in?

  private

  def user_not_authorized
    flash[:alert] = "You are not authorized to perform this action."
    redirect_to(request.referrer || root_path)
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def logged_in?
    current_user.present?
  end

  def authenticate_user!
    unless logged_in?
      redirect_to login_path, alert: "You must be logged in to access this page"
    end
  end

  def authenticate_superadmin!
    authenticate_user!
    unless current_user.superadmin?
      redirect_to root_path, alert: "You are not authorized to access this page"
    end
  end

  def current_hotel
    @current_hotel ||= if params[:hotel_id]
      current_user.hotels.find_by(id: params[:hotel_id])
    else
      current_user.hotels.first
    end
  end

  def permitted_hotels
    @permitted_hotels ||= if current_user.superadmin?
      Hotel.all
    else
      current_user.hotels
    end
  end

  def ensure_hotel_access!
    unless current_hotel || current_user.superadmin?
      redirect_to root_path, alert: "You do not have access to any hotels"
    end
  end

  helper_method :current_hotel, :permitted_hotels
end
