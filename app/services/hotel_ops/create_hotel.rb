# frozen_string_literal: true

module HotelOps
  class CreateHotel
    def initialize(account_params:, user_params:, hotel_params:, owner_invitation: nil)
      @account_params = account_params
      @user_params = user_params
      @hotel_params = hotel_params
      @owner_invitation_options = owner_invitation
    end

    def call
      result = ActiveRecord::Base.transaction do
        account = Account.create!(@account_params.merge(status: "active"))
        SeedAccountRoles.call(account)

        sanitize_amenities
        hotel = Hotel.create!(@hotel_params.reverse_merge(status: "setup", amenities: []).merge(account: account))
        owner_role = Role.find_by!(account: account, slug: "hotel_owner")

        user = nil
        invitation = nil
        token = nil

        if @owner_invitation_options
          token = StaffInvitation.generate_token
          invitation = StaffInvitation.create!(
            account: account,
            hotel: hotel,
            role: owner_role,
            invited_by_user: @owner_invitation_options.fetch(:invited_by),
            name: @user_params[:name],
            email: @user_params[:email],
            token_digest: StaffInvitation.digest(token),
            expires_at: StaffInvitation::EXPIRY.from_now
          )
        else
          user = User.create!(user_attributes(account))
          UserRole.create!(user: user, role: owner_role)
          UserHotelAccess.create!(user: user, hotel: hotel, role: owner_role)
        end

        Onboarding::InitializeProgress.new(
          hotel: hotel,
          actor: @owner_invitation_options&.fetch(:invited_by, nil)
        ).call if hotel.status == "setup"

        Boats::EnsureDefaults.call(hotel)
        Financials::EnsureDefaultGlMaps.call(hotel)
        Financials::EnsureDefaultTransactionCodes.call(hotel)
        HotelBusinessDate.initialize_for_hotel!(hotel: hotel, date: hotel.business_date_for(Time.current))

        { success: true, user: user, hotel: hotel, account: account, owner_invitation: invitation, invitation_token: token }
      end

      deliver_owner_invitation(result) if @owner_invitation_options&.fetch(:deliver, false)
      result.except(:invitation_token)
    rescue ActiveRecord::RecordInvalid, KeyError => e
      { success: false, error: e.message }
    end

    private

    def deliver_owner_invitation(result)
      OwnerActivationMailer.activate(result.fetch(:owner_invitation), result.fetch(:invitation_token)).deliver_later
    end

    def sanitize_amenities
      @hotel_params[:amenities] = Array(@hotel_params[:amenities]).reject(&:blank?) if @hotel_params[:amenities]
    end

    def user_attributes(account)
      @user_params.merge(account: account, role: "admin")
    end
  end
end
