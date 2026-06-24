# frozen_string_literal: true

module CorporatePortal
  class BaseController < ApplicationController
    layout "corporate"

    before_action :authenticate_user!
    before_action :authenticate_corporate_user!

    private

    def authenticate_corporate_user!
      return if current_user&.corporate? && current_user.account&.corporate?

      redirect_to root_path, alert: "You are not authorized to access the corporate portal."
    end
  end
end
