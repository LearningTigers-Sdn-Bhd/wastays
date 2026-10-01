module HotelPortal
  class UserProfilesController < BaseController
    before_action :set_breadcrumbs

    def edit
      @user = current_user
    end

    def update
      @user = current_user
      if @user.update(user_params)
        redirect_to edit_hotel_user_profile_path, notice: "Profile updated successfully."
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def set_breadcrumbs
      override_breadcrumbs(
        { label: "Account" },
        { label: "My Profile", path: edit_hotel_user_profile_path(current_hotel) }
      )
    end

    def user_params
      params.require(:user).permit(:name, :email, :time_zone, :password, :password_confirmation)
    end
  end
end
