module HotelOps
  class CreateHotel
    DEFAULT_PASSWORD = "12345678".freeze

    def initialize(account_params:, user_params:, hotel_params:)
      @account_params = account_params
      @user_params = user_params
      @hotel_params = hotel_params
    end

    def call
      ActiveRecord::Base.transaction do
        account = Account.create!(@account_params.merge(status: "active"))

        # Seed account roles
        SeedAccountRoles.call(account)

        user = User.create!(user_attributes(account))

        # Assign hotel owner role to user at account level
        owner_role = Role.find_by!(account: account, slug: "hotel_owner")
        UserRole.create!(user: user, role: owner_role)

        sanitize_amenities
        hotel = Hotel.create!(@hotel_params.reverse_merge(status: "registered", amenities: []).merge(account: account))

        Financials::EnsureDefaultGlMaps.call(hotel)
        Financials::EnsureDefaultTransactionCodes.call(hotel)
        HotelBusinessDate.initialize_for_hotel!(hotel: hotel, date: hotel.business_date_for(Time.current))

        # Grant hotel access with the owner role
        UserHotelAccess.create!(user: user, hotel: hotel, role: owner_role)

        { success: true, user: user, hotel: hotel, account: account }
      end
    rescue ActiveRecord::RecordInvalid => e
      { success: false, error: e.message }
    end

    private

    def sanitize_amenities
      if @hotel_params[:amenities]
        @hotel_params[:amenities] = Array(@hotel_params[:amenities]).reject(&:blank?)
      end
    end

    def user_attributes(account)
      password = @user_params[:password].presence || DEFAULT_PASSWORD

      @user_params.reverse_merge(
        password: password,
        password_confirmation: @user_params[:password_confirmation].presence || password
      ).merge(account: account, role: "admin")
    end
  end
end
