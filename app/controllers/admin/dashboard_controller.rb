class Admin::DashboardController < ApplicationController
  before_action :authenticate_superadmin!

  def index
    @hotels = policy_scope(Hotel)
    @accounts = Account.all
  end
end
