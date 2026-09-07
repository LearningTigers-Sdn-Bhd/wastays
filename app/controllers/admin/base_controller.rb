module Admin
  class BaseController < ApplicationController
    include Breadcrumbable

    layout "admin"
    before_action :authenticate_superadmin!
  end
end
