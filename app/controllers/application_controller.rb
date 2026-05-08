# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  helper_method :current_user, :logged_in?
  around_action :use_user_time_zone
  before_action :set_current_request_id
  before_action :redirect_legacy_hotel_portal_path

  private

  def set_current_request_id
    Current.request_id = request.uuid
    Current.user_id = session[:user_id]
  end

  def user_not_authorized
    flash[:alert] = "You are not authorized to perform this action."
    redirect_to(request.referrer || root_path)
  end

  def not_found
    respond_to do |format|
      format.html { render file: Rails.public_path.join("404.html"), status: :not_found, layout: false }
      format.json { render json: { error: "Resource not found" }, status: :not_found }
    end
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def logged_in?
    current_user.present?
  end

  def authenticate_user!
    unless logged_in?
      store_forwarding_url
      redirect_to login_path, alert: "You must be logged in to access this page"
      return false
    end

    if current_user.account.status == "suspended"
      session[:user_id] = nil
      redirect_to login_path, alert: "Your account has been suspended. Please contact support."
      return false
    end

    true
  end

  def authenticate_superadmin!
    return unless authenticate_user!
    unless current_user.superadmin?
      redirect_to root_path, alert: "You are not authorized to access this page"
    end
  end

  def current_hotel
    @current_hotel ||= if current_user.superadmin? && params[:hotel_id]
      find_hotel_for_scope(Hotel.all, params[:hotel_id])
    elsif params[:hotel_id]
      find_hotel_for_scope(current_user.hotels, params[:hotel_id])
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

  def store_forwarding_url
    return if [ login_path, register_path ].include?(request.path)
    session[:forwarding_url] = request.fullpath if request.get? && !request.xhr?
  end

  def use_user_time_zone(&block)
    timezone = current_user&.time_zone.presence || User::DEFAULT_TIME_ZONE
    Time.use_zone(timezone, &block)
  end

  def hotel_portal_params
    { hotel_id: current_hotel&.to_param }.compact
  end

  def redirect_legacy_hotel_portal_path
    return unless request.get? || request.head?
    return unless params[:hotel_id].present?
    return unless request.path.match?(%r{\A/hotel/(dashboard|profile|faq|policy|property_policy|user_profile|bookings|arrivals|audit_logs|reports|inventory|guests|settings)})
    return if request.path.match?(%r{\A/hotel/\d+/})

    redirect_to canonical_hotel_portal_path(params[:hotel_id], request.path, request.query_parameters.except(:hotel_id))
  end

  def canonical_hotel_portal_path(hotel_id, legacy_path, query_params)
    suffix = legacy_path.delete_prefix("/hotel")
    canonical_hotel_id = current_hotel&.to_param || hotel_id
    path = "/hotel/#{canonical_hotel_id}#{suffix}"
    query_string = query_params.to_query
    query_string.present? ? "#{path}?#{query_string}" : path
  end

  def find_hotel_for_scope(scope, hotel_identifier)
    hotel_key = hotel_identifier.to_s

    scope.where(slug: hotel_key).first || scope.find_by(id: hotel_key)
  end

  helper_method :current_hotel, :permitted_hotels, :hotel_portal_params
end
