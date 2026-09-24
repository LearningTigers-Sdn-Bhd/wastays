# frozen_string_literal: true

class Admin::Hotels::SettingsController < Admin::BaseController
  before_action :set_hotel

  def update_account
    owner = selected_owner! if params[:owner_id].present?
    Admin::Hotels::UpdateAccount.call(
      hotel: @hotel, owner:, account_name: params.require(:account).fetch(:name),
      owner_name: params.dig(:owner, :name), owner_email: params.dig(:owner, :email)
    )
    redirect_to admin_hotel_path(@hotel, tab: "account_information"), notice: "Account information saved."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_hotel_path(@hotel, tab: "account_information"), alert: e.record.errors.full_messages.to_sentence
  end

  def update_salesperson
    details = params.require(:salesperson).permit(:operation, :id, :name, :email)
    raise ActionController::BadRequest, "Invalid salesperson action" unless details[:operation].in?(%w[assign create update_contact])
    Admin::Hotels::UpdateSalesperson.call(
      hotel: @hotel, account: current_user.account, operation: details[:operation], salesperson_id: details[:id],
      name: details[:name].to_s.strip, email: details[:email].to_s.strip
    )
    redirect_to admin_hotel_path(@hotel, tab: "salesperson"), notice: "Salesperson saved."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_hotel_path(@hotel, tab: "salesperson"), alert: e.record.errors.full_messages.to_sentence
  end

  def send_owner_password_reset
    owner = selected_owner!
    token = OwnerPasswordReset.issue!(owner)
    OwnerPasswordResetMailer.reset(owner, @hotel, token).deliver_later
    redirect_to admin_hotel_path(@hotel, tab: "account_information", owner_id: owner.id), notice: "Password reset link sent."
  end

  def set_owner_password
    owner = selected_owner!
    Admin::Hotels::ChangeOwnerPassword.call(
      user: owner, password: params[:password], password_confirmation: params[:password_confirmation]
    )
    redirect_to admin_hotel_path(@hotel, tab: "account_information", owner_id: owner.id), notice: "Owner password updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_hotel_path(@hotel, tab: "account_information", owner_id: owner&.id), alert: e.record.errors.full_messages.to_sentence
  end

  private

  def set_hotel
    @hotel = Hotel.locate!(params[:id])
  end

  def selected_owner!
    owners = @hotel.user_hotel_accesses.active.joins(:role).where(roles: { slug: "hotel_owner" })
    owners.find_by!(user_id: params[:owner_id]).user
  end
end
