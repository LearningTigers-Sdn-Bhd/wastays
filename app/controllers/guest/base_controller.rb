class Guest::BaseController < ApplicationController
  include Breadcrumbable

  layout "guest"

  skip_before_action :redirect_legacy_hotel_portal_path

  helper Guest::NavigationHelper
  helper_method :current_guest, :guest_logged_in?

  private

  def current_guest
    @current_guest ||= ::Guest.find_by(id: session[:guest_id]) if session[:guest_id]
  end

  def guest_logged_in?
    current_guest.present?
  end

  def authenticate_guest!
    unless guest_logged_in?
      redirect_to guest_login_path, alert: "Please log in to continue."
    end
  end
end
