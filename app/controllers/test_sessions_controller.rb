# frozen_string_literal: true

# Test-only controller that establishes a signed-in session without the login
# form, so system specs can skip the multi-interaction UI login on every
# example. Mounted only when Rails.env.test? (see config/routes.rb).
class TestSessionsController < ApplicationController
  def create
    raise ActionController::RoutingError, "Not Found" unless Rails.env.test?

    session[:user_id] = params[:user_id]
    head :ok
  end
end
