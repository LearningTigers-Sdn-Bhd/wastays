module Admin
  class BaseController < ApplicationController
    layout "admin"
    before_action :authenticate_superadmin!
  end
end
