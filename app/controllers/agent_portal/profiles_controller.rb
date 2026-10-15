# frozen_string_literal: true

module AgentPortal
  class ProfilesController < BaseController
    def edit
      @user = current_user
    end

    def update
      @user = current_user

      if Users::UpdateProfile.call(user: @user, params: user_params)
        redirect_to edit_agent_profile_path, notice: "Profile updated.", status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def user_params
      params.require(:user).permit(:name, :password, :password_confirmation, :current_password)
    end
  end
end
