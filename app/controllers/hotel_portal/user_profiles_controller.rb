module HotelPortal
  class UserProfilesController < BaseController
    def edit
      @user = current_user
    end

    def update
      @user = current_user
      if @user.update(user_params)
        redirect_to edit_hotel_user_profile_path, notice: "Profile updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def user_params
      params.require(:user).permit(:name, :email, :time_zone, :password, :password_confirmation)
    end
  end
end
