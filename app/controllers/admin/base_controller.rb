module Admin
  class BaseController < ApplicationController
    include Breadcrumbable

    layout "admin"
    before_action :authenticate_admin_panel_user!
  end
end
